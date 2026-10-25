vim.opt.rtp:prepend(vim.fn.getcwd())
local calls = {}
local api = {}
for _, name in ipairs({ "run", "run_all", "clear", "inspect", "stop", "output", "copy_plot", "objects" }) do
	api[name] = function(...)
		calls[#calls + 1] = { name, ... }
	end
end
package.loaded.arf = api
dofile("plugin/arf.lua")
dofile("plugin/arf.lua") -- Loading twice must leave command registration intact.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
for _, case in ipairs({
	{ "ArfRun", { "run" } },
	{ "2,3ArfRun", { "run", 2, 3 } },
	{ "%ArfRun", { "run", 1, 4 } },
	{ "ArfRunAll", { "run_all" } },
	{ "ArfClear", { "clear" } },
	{ "ArfSummary", { "inspect", "base::summary" } },
	{ "ArfStop", { "stop" } },
	{ "ArfOutput", { "output" } },
	{ "ArfCopyPlot", { "copy_plot" } },
	{ "ArfObjects", { "objects" } },
}) do
	vim.cmd(case[1])
	assert(vim.deep_equal(calls[#calls], case[2]), case[1])
end
assert(#calls == 10, "one dispatch per command")
print("command tests passed")
