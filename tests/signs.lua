vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local signs = require("arf.signs")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c" })
local function marks()
	return vim.api.nvim_buf_get_extmarks(buf, signs.namespace, 0, -1, { details = true })
end
assert(arf.config.signs.success.text == "│" and arf.config.signs.error.text == "│")
arf.setup({ signs = { enabled = false } })
assert(#signs.place(buf, 0, 2, "running") == 0 and #marks() == 0)
arf.setup({
	signs = {
		enabled = true,
		priority = 17,
		range = { text = "|" },
		success = { text = "+", hl = "String" },
		error = { text = "!", hl = "ErrorMsg" },
		interrupted = { text = "~", hl = "DiagnosticWarn" },
		running = { text = "?", hl = "WarningMsg", frames = {}, interval_ms = 5 },
	},
})
for _, case in ipairs({
	{ false, false, "+", "String" },
	{ true, false, "!", "ErrorMsg" },
	{ true, false, "~", "DiagnosticWarn", true },
	{ false, true, "?", "WarningMsg" },
}) do
	local ids =
		signs.place(buf, 0, 2, case[2] and "running" or case[5] and "interrupted" or case[1] and "error" or "ok")
	local placed = marks()
	assert(#placed == 3 and placed[1][4].sign_text:match("^|"))
	for _, mark in ipairs(placed) do
		assert(mark[4].sign_hl_group == case[4], "entire range uses the execution status color")
	end
	assert(placed[3][4].sign_text:sub(1, 1) == case[3] and placed[3][4].sign_hl_group == case[4])
	assert(placed[3][4].priority == 17 and ids.timer == nil)
	signs.clear(buf, ids)
end
arf.setup({ signs = { range = { text = "" }, running = { frames = { "a", "b" } } } })
local ids = signs.place(buf, 0, 2, "running")
assert(#ids == 1 and ids.timer)
assert(
	vim.wait(1000, function()
		return marks()[1][4].sign_text:match("^[ab]") ~= nil
	end),
	"spinner updates the final sign"
)
local timer = ids.timer
signs.clear(buf, ids)
assert(timer:is_closing() and #marks() == 0)
arf.setup({ signs = { running = { text = "" } } })
ids = signs.place(buf, 0, 2, "running")
assert(#ids == 0 and ids.timer == nil, "empty running text disables animation")
print("sign customization tests passed")
