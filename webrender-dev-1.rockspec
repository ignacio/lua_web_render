package = "webrender"
version = "dev-1"

source = {
	url = "git://github.com/ignacio/lua_web_render.git",
	branch = "master"
}

description = {
	summary = "Template engine which uses either Cosmo pages or CGILua's LuaPages",
	detailed = [[Template engine which uses either Cosmo pages or CGILua's LuaPages.]],
	license = "MIT/X11",
	homepage = "https://github.com/ignacio/lua_web_render"
}

dependencies = {
	"lua >= 5.1",
	"orbit >= 2.2.4",
	"cosmo >= 14.03.04"
}

external_dependencies = {

}
build = {
	type = "builtin",
	modules = {
		["webrender"] = "webrender.lua",
		["webrender.cgiluaPage"] = "cgiluaPage.lua",
		["webrender.cosmoPage"] = "cosmoPage.lua",
		["webrender.scriptHandler"] = "scriptHandler.lua",
		["webrender.stylesheetHandler"] = "stylesheetHandler.lua",
		["webrender.cgilua.lp"] = "cgilua/lp.lua",
	}
}
