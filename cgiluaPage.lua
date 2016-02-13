local table = table
local setmetatable, rawset = setmetatable, rawset
local _G = _G
local xpcall = xpcall

local wsapi_common = require "wsapi.common"
local lp = require "webrender.cgilua.lp"

local M = {}

lp.setcompatmode(false)

---
-- Elimina el BOM (byte order mark) que indica que el archivo es unicode
--
local function remove_bom(s)
	return s:gsub("^\239\187\191", "")
end

---
-- Carga una página LP y lo llena con los datos que se sacan de 'render' y 'env'
--
function M.Fill(render, script, input)
	local web = render.web
	local output = {}
	local env = {
		web = web,	-- web se accede derecho
		-- y el resto lo busco en el render, en _G o en web
		__index = function(env, name)
			local temp = (input and input[name]) or render.env[name] or render.extension[name] or web[name] or _G[name]
			if temp then
				rawset(env, name, temp)
				return temp
			end
		end,
		collect = function(value)
			table.insert(output, value)
		end,
		IncludeLP = function(url, env)
			return render:IncludeLP(url, env)
		end,
		captures = {}
	}
	
	-- captures are indexed only from web.input or from input table
	setmetatable(env.captures, { __index = function(t, name)
			local temp = (web.input and web.input[name]) or (input and input[name])
			if temp then
				rawset(t, name, temp)
				return temp
			end
		end})
	
	setmetatable(env, env)
	lp.setoutfunc("collect")
	local ok, result = xpcall(function() return lp.include(script, env) end, debug.traceback)
	if not ok then
		--LogError("shared.render.cgiluaPage '%s': %s", script, result)
		web.status = "404 Not found"
		return wsapi_common.status_404_html(script)
	end
	return remove_bom(table.concat(output))
end

return M
