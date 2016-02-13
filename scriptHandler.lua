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

local function AddSingleScript(scripts, script)
	script = trim(script)
	if script == "" then
		--LogWarning("Tried to add an empty script")
		--LogDebug(debug.traceback())
		return
	end
	-- o paso la url solamente, o paso el tag script entero
	if not string.match(script, "^.*<") then
		script = string.format([[<script type="text/javascript" src="%s"></script>]], script)
	end
	local src = string.match(script, [[src="(.+)"]])
	if src then
		src = string.lower(trim(src))
		if not scripts[src] then
			scripts[src] = true
			table.insert(scripts, script)
		end
	else
		table.insert(scripts, script)
	end
end

local function AddScript(scripts, script)
	if type(script) == "table" then
		for _, data in ipairs(script) do
			AddSingleScript(scripts, data)
		end
	elseif type(script) == "string" then
		AddSingleScript(scripts, script)
	else
		error("must be a table or a string", script)
	end
end

function M.MakeCollector(scripts)
	return {
		Add = function(script)
			AddScript(scripts, script)
		end,
		AddRaw = function(script)
			table.insert(scripts, string.format([[<script type="text/javascript">%s</script>]], script))
		end,
		Collect = function()
			return scripts
		end
	}
end

function M.MakeForbiddenCollector(scripts)
	return {
		Add = function(script)
			error("adding scripts is forbidden")
		end,
		AddRaw = function(script)
			error("adding scripts is forbidden")
		end,
		Collect = function()
			return nil
		end
	}
end

return M
