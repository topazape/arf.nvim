local config = require("arf.config")
local actions = require("arf.actions")
local M = { config = config.get() }

function M.setup(opts)
	M.config = config.setup(opts)
	require("arf.highlights").apply(M.config.theme)
end

for _, name in ipairs({ "run", "run_all", "clear", "output", "copy_plot", "inspect", "objects" }) do
	M[name] = actions[name]
end

function M.interrupt()
	return require("arf.execution").interrupt()
end

function M.help(topic)
	return require("arf.help").show(topic)
end

function M.help_search(query)
	return require("arf.help").search(query)
end

function M.stop()
	if require("arf.execution").stop() then
		require("arf.help").cancel()
		actions.cancel_objects()
		require("arf.float").close()
		require("arf.results").clear_all()
	end
end

return M
