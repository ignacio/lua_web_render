--
-- Contains code taken from Orbit (https://github.com/keplerproject/orbit)
--
--

local io = io
local setmetatable, loadstring, pcall, setfenv, type = setmetatable, loadstring, pcall, setfenv, type
local rawset = rawset
local error, xpcall = error, xpcall
local cosmo = require "cosmo"
local _G = _G

local M = {}

-- el siguiente tramo está hurtado de orbit
local m_template_cache = {}

local function remove_shebang(s)
	return s:gsub("^#![^\n]+", "")
end

---
-- Elimina el BOM (byte order mark) que indica que el archivo es unicode
--
local function remove_bom(s)
	return s:gsub("^\239\187\191", "")
end

---
-- Carga un template de disco (eventualmente lo cachea, pero comente esa parte hasta no definir un "development mode"
--
local function load(filename, contents)
	filename = filename or contents
	local template = m_template_cache[filename]
	if not template then
		if not contents then
			local file, err = io.open(filename)
			if not file then
				return nil, err
			end
			contents = file:read("*a")
			file:close()
		end
		template = cosmo.compile(remove_bom(remove_shebang(contents)), "#"..filename)
		m_template_cache[filename] = template
	end
	return template
end

local function abort(res)
	error{ abort, res or "abort" }
end

---
-- Genera el entorno donde va a ejecutar el template. Agrega algunas funciones útiles al mismo.
--
local function make_env(web, env)
	env._G = env
	env.app = _G
	env.web = web
	env.finish = abort
	function env.lua(arg)
		local f, err = loadstring(arg[1])
		if not f then error(err .. " in \n" .. arg[1]) end
		setfenv(f, env)
		local ok, res = pcall(f)
		if not ok and (type(res)~= "table" or res[1] ~= abort) then
			error(res .. " in \n" .. arg[1])
		elseif ok then
			return res or ""
		else
			abort(res[2])
		end
	end
	env["if"] = function (arg)
		if type(arg[1]) == "function" then arg[1] = arg[1](select(2, unpack(arg))) end
		if arg[1] then
			cosmo.yield{ it = arg[1], _template = 1 }
		else
			cosmo.yield{ _template = 2 }
		end
	end
	function env.redirect(target)
		if type(target) == "table" then target = target[1] end
		web:redirect(target)
		abort()
	end
	function env.fill(arg)
		cosmo.yield(arg[1])
	end
	function env.link(arg)
		local url = arg[1]
		arg[1] = nil
		return web:link(url, arg)
	end
	function env.static_link(arg)
		return web:static_link(arg[1])
	end
	function env.include(name, subt_env)
		local filename
		if type(name) == "table" then
			name = name[1]
			subt_env = name[2]
		end
		if name:sub(1, 1) == "/" then
			filename = web.doc_root .. name
		else
			-- uso el path que haya en env o sino el que haya en web, así puedo redefinir el lugar de los includes
			filename = (env.real_path or web.real_path) .. "/" .. name
		end
		local template = load(filename)
		if not template then return "" end
		if subt_env then
			if type(subt_env) ~= "table" then subt_env = { it = subt_env } end
			subt_env = setmetatable(subt_env, { __index = env })
		else
			subt_env = env
		end
		return template(subt_env)
	end
	function env.raw_include(name, subt_env)
		local filename
		if type(name) == "table" then
			name = name[1]
			subt_env = name[2]
		end
		if name:sub(1, 1) == "/" then
			filename = web.doc_root .. name
		else
			-- uso el path que haya en env o sino el que haya en web, así puedo redefinir el lugar de los includes
			filename = (env.real_path or web.real_path) .. "/" .. name
		end
		local file = io.open(filename)
		if not file then return "" end
		local contents = file:read("*a")
		file:close()
		return remove_bom(remove_shebang(contents))
	end
	function env.forward(...)
		abort(env.include(...))
	end
	return env
end

---
-- Llena el template usando el render y el entorno dados
--
local function fill(render, web, template, env)
	if not template then
		return
	end
	local function env_index(tab, name)
		local var = (env and env[name]) or render.env[name] or render.extension[name]
		rawset(tab, name, var)
		return var
	end
	-- we want a new table each time because we're polluting env
	local newEnv = setmetatable({}, { __index = env_index })
	local ok, res = xpcall(function () return template(make_env(web, newEnv)) end,
			function (msg)
				if type(msg) == "table" and msg[1] == abort then
					return msg
				else
					return debug.traceback(msg)
				end
			end)
	if not ok and (type(res) ~= "table" or res[1] ~= abort) then
		error(res)
	elseif ok then
		return res
	else
		return res[2]
	end
end

---
-- Carga un template Cosmo (absoluto o relativo) y lo llena con los datos que se sacan de 'render' y 'env'
--
function M.Fill(render, name, env)
	local filename
	if name:sub(1, 1) == "/" then
		filename = render.web.doc_root .. name
	else
		filename = render.web.real_path .. "/" .. name
	end
	local template, err = load(filename)
	if not template then
		return nil, err
	end
	return fill(render, render.web, template, env)
end

---
-- Llena un template Cosmo ya cargado con los datos que se sacan de 'render' y 'env'
--
function M.FillTemplate(render, template, env)
	template = load(nil, template)
	return fill(render, render.web, template, env)
end

return M
