vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local float = require("arf.float")
local results = require("arf.results")
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "x", "y", "z" })
arf.setup({ float_width = 500, float_max_height = 500 })
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end
-- Saved output must never start a session or perform evaluation.
package.loaded["arf.session"] = {
	ensure = function()
		error("unexpected R evaluation")
	end,
}
package.loaded["arf.executor"] = {
	eval = function()
		error("unexpected R evaluation")
	end,
}
arf.output()
assert(#notices == 1 and notices[1]:find("No saved"))
results.start(source, 0, 1)
arf.output()
assert(#notices == 2 and notices[2]:find("running"))
results.put(source, 0, 1, {
	text = "日本語\nsecond",
	error = "failure",
	cleanup = function() end,
	chunks = { { text = "日本語\n", highlight = "ArfMessage" }, { text = "second", highlight = "ArfOutput" } },
})
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local win = arf.output()
local buf = vim.api.nvim_win_get_buf(win)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[1] == "日本語" and lines[2] == "second" and table.concat(lines, "\n"):find("failure"))
local config = vim.api.nvim_win_get_config(win)
assert(config.width == vim.o.columns - 4 and config.height == #lines, "clamp width and shrink height")
assert(not vim.bo[buf].modifiable and vim.bo[buf].bufhidden == "wipe")
local marks = vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("arf.float"), 0, -1, { details = true })
assert(marks[1][4].end_col == #"日本語" and marks[1][4].hl_group == "ArfFloatMessage", "UTF-8 highlights")
assert(marks[2][4].hl_group == "ArfFloatOutput", "normal output uses the float-specific color")
assert(marks[#marks][4].hl_group == "ArfFloatError", "errors use the float-specific group")
float.close(source + 1000)
assert(vim.api.nvim_win_is_valid(win), "other owner cannot close float")
float.close(source)
assert(not vim.api.nvim_win_is_valid(win) and not vim.api.nvim_buf_is_valid(buf), "close wipes scratch buffer")
vim.api.nvim_set_current_buf(source)
local empty = float.open("empty", {}, { width = 20, max_height = 5, owner = source })
assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(empty), 0, -1, false)[1] == "(no output)")
local tall = {}
for _ = 1, 100 do
	tall[#tall + 1] = { { "line", "ArfOutput" } }
end
local replacement = float.open("tall", tall, { width = 20, max_height = 500, owner = source })
assert(not vim.api.nvim_win_is_valid(empty), "opening a float closes previous one")
assert(vim.api.nvim_win_get_config(replacement).height == vim.o.lines - 4, "clamp height to screen")
for _, map in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(replacement), "n")) do
	if map.lhs == "q" then
		map.callback()
	end
end
assert(not vim.api.nvim_win_is_valid(replacement), "q closes float")
vim.api.nvim_set_current_buf(source)
arf.setup({ float_width = "auto" })
local auto = arf.output()
assert(vim.api.nvim_win_get_config(auto).width == vim.o.columns - 4, "auto uses editor width")
float.close()
vim.o.columns = vim.o.columns + 20
vim.api.nvim_set_current_buf(source)
local resized = arf.output()
assert(vim.api.nvim_win_get_config(resized).width == vim.o.columns - 4, "auto recalculates when reopened")
float.close()
for _, percent in ipairs({ 1, 90, 100 }) do
	vim.api.nvim_set_current_buf(source)
	arf.setup({ float_width = percent .. "%" })
	local percentage = arf.output()
	local expected = math.max(1, math.min(math.floor(vim.o.columns * percent / 100), vim.o.columns - 4))
	assert(
		vim.api.nvim_win_get_config(percentage).width == expected,
		"percentage uses editor width and clamps to screen"
	)
	float.close()
end
vim.o.columns = vim.o.columns + 20
vim.api.nvim_set_current_buf(source)
arf.setup({ float_width = "90%" })
local percentage_resized = arf.output()
assert(
	vim.api.nvim_win_get_config(percentage_resized).width == math.floor(vim.o.columns * 0.9),
	"percentage recalculates when reopened"
)
float.close()
vim.api.nvim_set_current_buf(source)
arf.output()
local owned = vim.api.nvim_get_current_win()
arf.clear(source)
assert(not vim.api.nvim_win_is_valid(owned), "clear closes saved-output float")
print("saved output and float tests passed")
