local scriptHandler = require "webrender.scriptHandler"
local stylesHandler = require "webrender.stylesheetHandler"
local cosmoPage = require "webrender.cosmoPage"
local cgiluaPage = require "webrender.cgiluaPage"
local table, setmetatable, require, string, next = table, setmetatable, require, string, next
local type, assert, pairs = type, assert, pairs
local rawset = rawset

local wsapi_response = require "wsapi.response"
local wsapi_request = require "wsapi.request"


local M = {}

local function initialize(render, web, env, how)
	render.web = web
	--render.env = env or {}
	assert(not how or type(how) == "table", "'how' must be nil or a table")
	
	local function env_index(tab, name)
		local var = (env and env[name])
		rawset(tab, name, var)
		return var
	end
	-- we want a new table each time because we're polluting env
	render.env = setmetatable({}, { __index = env_index })
	
	if not how or how.fullpage then
		local scripts, stylesheets = {}, {}
		-- los scripts y las stylesheets no las renderizo directamente, sino que las voy juntando
		render.extension.Scripts = scriptHandler.MakeCollector(scripts)
		render.extension.Stylesheets = stylesHandler.MakeCollector(stylesheets)
	
		if render.m_commonScripts then
			render.extension.Scripts.Add(render.m_commonScripts)
		end
		if render.m_commonStylesheets then
			render.extension.Stylesheets.Add(render.m_commonStylesheets)
		end
	
		-- un widget es algo que necesita scripts y stylesheets
		render.extension.HaveWidget = function(widget)
			render.extension.Scripts.Add(widget.GetScripts())
			render.extension.Stylesheets.Add(widget.GetStylesheets())
		end
	else
		if how.snippet then
			-- un collector que loguee un error avisando que estan tratando de agregar un script o una hoja de estilos
			render.extension.Scripts = scriptHandler.MakeForbiddenCollector()
			render.extension.Stylesheets = stylesHandler.MakeForbiddenCollector()
		end
	end
end

local function finish(render, content)
	if content then
		local content_type = render.web.headers["Content-Type"]
		local stylesheets = render.extension.Stylesheets.Collect() or {}
		local scripts = render.extension.Scripts.Collect() or {}
		
		if #stylesheets ~= 0 or #scripts ~= 0 then
			-- muy tosco, por ahora, pero cuelgo los stylesheets y los scripts antes de cerrar el tag head (más vale que haya uno!)
			-- puede no haber uno, en caso de ScriptLp, ScriptCosmo, StylesheetLp y StylesheetCosmo, pero ahí no inserto Scripts
			local substitutions
			content, substitutions = string.gsub(content, "</head>", function()
				return table.concat(stylesheets, "\r\n") .. "\r\n" .. table.concat(scripts, "\r\n") .. "</head>"
			end)
			if substitutions == 0 then
				--LogWarning("No substitutions were performed for script '%s'\r\nMake sure there is a <head> node", render.web.script_name .. render.web.path_info)
			end
		end
	end
	
	content = content or ""
	
	--- Hook que se llama cuando el contenido está pronto y antes de enviarlo
	--- Me permite modificarlo
	if type(render.onContentReady) == "function" then
		content = render.onContentReady(render, content)
	end

	-- limpiamos todo
	render.web = nil
	render.env = nil
	
	return content
end

--
-- helper functions for initialize_xxx_escaping

local function make_escaping_function(substitutions)
	assert(type(substitutions) == "table")
	
	local match = "["
	for k in pairs(substitutions) do
		match = match .. k
	end
	match = match .. "]"
	
	return function(text)
		return (string.gsub(text, match, function(char)
			return substitutions[char]
		end))
	end
end

-- javascript sanitizer
local escape_js = make_escaping_function{
	["\""] = [[\"]],
	["'"] = [[\']]
}

-- HTML sanitizer
--http://www.w3.org/TR/xhtml1/#C_16
local escape_html = make_escaping_function{
	["<"] = [[&lt;]],
	[">"] = [[&gt;]],
	["\""] = [[&quot;]],
	["&"] = [[&amp;]],
	["'"] = [[&#39;]]
}

--
local function initialize_html_escaping(render, template_engine)
	assert(type(render) == "table")
	
	local env = render.env
	env.ToJs = function(...)
		return escape_js(...)
	end
	env.ToHtml = function(...)
		return escape_html(...)
	end
end

local function initialize_js_escaping(render, template_engine)
	assert(type(render) == "table")
	
	local env = render.env
	env.ToJs = function(...)
		return escape_js(...)
	end
	env.ToHtml = function(...)
		return escape_html(...)
	end
end

---
-- Renders a Cosmo page.
-- Everything in `self` table is directly accesible in pages.
--
function M.RenderPage(self, url, web, env, how)
	initialize(self, web, env, how)
	initialize_html_escaping(self, "cosmo")
	
	return finish( self, cosmoPage.Fill(self, url, env) )
end

---
-- Renders a CGILua page.
-- Everything in `self` table is directly accesible in pages.
--
function M.RenderPageLP(self, url, web, env, how)
	initialize(self, web, env, how)
	initialize_html_escaping(self, "lp")
	
	local filename
	if url:sub(1, 1) == "/" then
		filename = web.doc_root .. url
	else
		filename = web.real_path .. "/" .. url
	end
	return finish( self, cgiluaPage.Fill(self, filename, env) )
end

---
-- Esto es para renderizar javascripts. Esta función es candidata a cambiar en un futuro, cuando se haga algo más inteligente 
-- para manipular los javascripts a que vuele o pase a su propio módulo.
-- Ojo, tienen mucho código repetido. Son candidatas a un buen refactoreo.
--
function M.ScriptLp(self, url, web, env)
	web.headers["Content-Type"] = "text/javascript"
	
	initialize(self, web, env, { snippet = true })
	initialize_js_escaping(self, "lp")
	
	local filename
	if url:sub(1, 1) == "/" then
		filename = web.doc_root .. url
	else
		filename = web.real_path .. "/" .. url
	end
	return finish( self, cgiluaPage.Fill(self, filename, env) )
end

function M.ScriptCosmo(self, url, web, env)
	web.headers["Content-Type"] = "text/javascript"
	
	initialize(self, web, env, { snippet = true })
	initialize_js_escaping(self, "cosmo")
	
	return finish( self, cosmoPage.Fill(self, url, env) )
end

---
-- Idem a la función ScriptLp y ScriptCosmo
--
function M.StylesheetLp(self, url, web, env)
	web.headers["Content-Type"] = "text/css"
	initialize(self, web, env, { snippet = true })
	
	local filename
	if url:sub(1, 1) == "/" then
		filename = web.doc_root .. url
	else
		filename = web.real_path .. "/" .. url
	end
	return finish( self, cgiluaPage.Fill(self, filename, env) )
end

---
--
function M.StylesheetCosmo(self, url, web, env)
	web.headers["Content-Type"] = "text/css"
	initialize(self, web, env, { snippet = true })
	
	return finish( self, cosmoPage.Fill(self, url, env) )
end

---
-- Mapea un objeto a ser renderizado. Estos objetos tienen que tener una función llamada "Render" de la forma:
-- 	Render(self, render, web, environment)  donde:
-- 		- render, es el renderer usado actualmente
-- 		- web es la tabla web de wsapi correspondiente al request actual
-- 		- environment, la tabla donde se propaga el entorno que usa la función para buscar datos extras
--
-- 	y una función "GetStyles" de la forma:
-- 	GetStyles(self, web, environment) donde los parámetros son análogos a la función Render
--
function M.Plug(render, name, object)
	assert(object)
	if next(object) then
		render.extension[name] = {
			Render = function()
				assert(object.Render)
				return object:Render(render, render.web, render.environment)
			end,
			GetStyles = function()
				assert(object.GetStyles)
				return object:GetStyles(render.web, render.environment)
			end
		}
	else
		--LogWarning("Render.Plug: Plugging empty object!")
		render.extension[name] = {
			Render = function() return "" end,
			GetStyles = function() return  "" end
		}
	end
end

---
-- Adds a script that is included in everything the render outputs.
--
function M.AddCommonScript(self, script)
	self.m_commonScripts = self.m_commonScripts or {}
	table.insert(self.m_commonScripts, script)
end

---
-- Adds a stylesheet that is included in everything the render outputs.
--
function M.AddCommonStylesheet(self, stylesheet)
	self.m_commonStylesheets = self.m_commonStylesheets or {}
	table.insert(self.m_commonStylesheets, stylesheet)
end

---
-- Sets an extension to the render, with a given name.
--
function M.Extend(self, name, extension)
	self.extension[name] = extension
end

---
-- IncludeLP must be called within an invocation to Render, RenderPage or RenderPageLP
--
function M.IncludeLP(self, url, env)
	assert(self.web)
	initialize_html_escaping(self, "lp")
	return cgiluaPage.Fill(self, url, env)
end

---
--
function M.IncludeCosmo(self, url, env)
	assert(self.web)
	initialize_html_escaping(self, "cosmo")
	return cosmoPage.Fill(self, url, env)
end

local moduleMT = {
	__index = M
}


function M.new (applicationName, parameters)
	local newInstance = { extension = {} }
	
	setmetatable(newInstance, moduleMT)
	
	if type(parameters) == "table" then
		for k,v in pairs(parameters) do
			newInstance.extension[k] = v
		end
	end
	return newInstance
end


--
-- filter for WSAPI. Emulates what Orbit is doing because the render is tied to Orbit's 'web'
function M.makeWsapiCompatible (applicationName, renderEngine, env)
	local render = M.new(applicationName)
	
	if type(renderEngine) == "string" then
		renderEngine = M[renderEngine]
		assert(type(renderEngine) == "function", "'render engine not found'")
	end

	return function(wsapi_env)
		local newenv = setmetatable({}, { __index = env })	-- don't pollute env
		local web = {
			status = "200 Ok",
			response = "",
			headers = { ["Content-Type"]= "text/html" },
			cookies = {},
			real_path = wsapi_env.APP_PATH,
			doc_root = wsapi_env.DOCUMENT_ROOT,
			path_translated = wsapi_env.PATH_TRANSLATED,
			prefix = wsapi_env.SCRIPT_NAME,
			script_name = wsapi_env.SCRIPT_NAME,
			vars = wsapi_env
		}
		if web.path_translated == "" then
			web.path_translated = wsapi_env.SCRIPT_FILENAME
		end
		
		local req = wsapi_request.new(wsapi_env)
		local res = wsapi_response.new(web.status, web.headers)
		
		web.path_info = req.path_info
		web.method = string.lower(req.method)
		web.input, web.cookies = req.params, req.cookies
		web.GET, web.POST = req.GET, req.POST
		
		local content = renderEngine(render, wsapi_env.PATH_INFO, web, newenv)
		res:write(content)
		return res:finish()
	end
end

return M
