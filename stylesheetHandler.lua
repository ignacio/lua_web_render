local string = string
local table = table
local type = type
local error = error
local ipairs = ipairs
local string_gsub = string.gsub

local M = {}

local function trim(s)
	return string_gsub(s, "^%s*(.-)%s*$", "%1")
end

local function AddSingleStylesheet (stylesheets, stylesheet)
	stylesheet = trim(stylesheet)
	-- o paso la url solamente, o paso el tag link entero
	if stylesheet == "" then
		--LogWarning("Tried to add an empty stylesheet")
		--LogDebug(debug.traceback())
		return
	end
	if not string.match(stylesheet, "^.*<") then
		stylesheet = string.format([[<link href="%s" rel="stylesheet" type="text/css">]], stylesheet)
	end
	local src = string.match(stylesheet, [[src="(.+)"]])
	if src then
		src = string.lower(trim(src))
		if not stylesheets[src] then
			stylesheets[src] = true
			table.insert(stylesheets, stylesheet)
		end
	else
		table.insert(stylesheets, stylesheet)
	end
end

local function AddStylesheet(stylesheets, stylesheet)
	if type(stylesheet) == "table" then
		for _, data in ipairs(stylesheet) do
			AddSingleStylesheet(stylesheets, data)
		end
	elseif type(stylesheet) == "string" then
		AddSingleStylesheet(stylesheets, stylesheet)
	else
		error("must be a table or a string", stylesheet)
	end
end
	
function M.MakeCollector(stylesheets)
	return {
		Add = function(stylesheet)
			AddStylesheet(stylesheets, stylesheet)
		end,
		AddRaw = function(stylesheet)
			table.insert(stylesheets, string.format([[<style type="text/css">%s</style>]], stylesheet))
		end,
		Collect = function()
			return stylesheets
		end
	}
end

function M.MakeForbiddenCollector(stylesheets)
	return {
		Add = function(stylesheet)
			error("adding stylesheets is forbidden")
		end,
		AddRaw = function(stylesheet)
			error("adding stylesheets is forbidden")
		end,
		Collect = function()
			return nil
		end
	}
end

return M
