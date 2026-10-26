-- Run with: nvim --headless -u NONE -l tests/display.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function drain()
	vim.wait(20, function()
		return false
	end)
end
-- Force the missing-dependency path regardless of the user's installed plugins.
package.preload.snacks = function()
	error("unavailable in this test")
end
local backend = require("arf.snacks")
check(backend.available() == false, "missing Snacks is reported")
local results = require("arf.results")
local display = require("arf.display")
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x <- 1", "plot(x)" })
local cleaned = 0
local entry = results.put(buf, 1, 1, {
	text = "text survives",
	elapsed_ms = 2430,
	paths = { "unused.png" },
	cleanup = function()
		cleaned = cleaned + 1
	end,
})
drain()
local function rendered()
	return vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, { details = true })[3].virt_lines
		or {}
end
local function timing()
	return vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, { details = true })[3]
end
check(timing().virt_text_pos == "eol_right_align", "time aligns after code without overlay")
check(timing().virt_text[1][1] == "2.43s", "time coexists with output and image warning")
local lines = rendered()
check(lines[2][1][1] == "text survives", "text displays without image dependency")
check(lines[3][1][1]:find("snacks.nvim is required", 1, true), "missing backend has inline warning")
check(#lines == 4 and lines[4][1][1] == "", "blank line follows image warning")
local created, shown, updated, closed = 0, 0, 0, 0
local opts
package.loaded.snacks = {
	image = {
		terminal = {
			env = function()
				return { supported = true, placeholders = false }
			end,
		},
		placement = {
			new = function(owner, path, options)
				check(owner == buf and path == "unused.png", "forward buffer and image path")
				created = created + 1
				opts = options
				return {
					opts = options,
					show = function()
						shown = shown + 1
					end,
					update = function()
						updated = updated + 1
					end,
					close = function()
						closed = closed + 1
					end,
				}
			end,
		},
	},
}
check(backend.available() == false, "terminal without placeholders is unsupported")
package.loaded.snacks.image.terminal.env = function()
	return { supported = true, placeholders = true }
end
check(backend.available(), "compatible terminal is accepted")
display.refresh()
display.refresh()
drain()
check(created == 1 and shown == 1 and updated == 1, "coalesce refresh and create one placement")
check(
	opts.pos[1] == 2 and opts.max_width == require("arf").config.image_max_width,
	"placement position and configured dimensions"
)
local ns = vim.api.nvim_create_namespace("arf.test.image")
for _, inline in ipairs({ false, true }) do
	local grid = { { "placeholder", "Normal" } }
	local details = inline and { virt_text = grid } or { virt_lines = { grid } }
	local id = vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, details)
	local placement = { ns = ns, eids = { id } }
	opts.on_update(placement)
	drain()
	check(
		#placement.eids == 0 and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0,
		"transfer image marks out of Snacks namespace"
	)
	check(rendered()[3][1][1] == "placeholder", "render both multi-row and one-row image grids below text")
	check(#rendered() == 4 and rendered()[4][1][1] == "", "blank line follows image grid")
end
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted" })
drain()
check(
	entry.plots[1].image.opts.pos[1] == 3 and entry.plots[1].image.opts.range[1] == 3,
	"move placement after source edit before range"
)
vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "plot(x + 1)" })
drain()
check(entry.stale and created == 1 and closed == 0 and cleaned == 0, "source edit retains image and resources")
check(
	rendered()[2][1][1] == "text survives" and rendered()[2][1][2] == "ArfOutputStale",
	"dim stale image text without adding lines"
)
check(timing().virt_text[1][2] == "ArfElapsedStale", "source edit dims elapsed time")
check(rendered()[1][1][2] == "ArfSeparator", "stale output keeps normal separator color")
results.clear(buf)
drain()
check(closed == 1 and cleaned == 1, "clear releases image and evaluation resources")
check(#vim.api.nvim_buf_get_extmarks(buf, results.namespace, 0, -1, {}) == 0, "clear removes timing mark")
for _, case in ipairs({
	{ 0, "0ms" },
	{ 142, "142ms" },
	{ 999, "999ms" },
	{ 1000, "1.00s" },
	{ 2430, "2.43s" },
	{ 59990, "59.99s" },
	{ 60000, "1m 0s" },
	{ 84000, "1m 24s" },
}) do
	entry = results.put(buf, 0, 1, { text = "", elapsed_ms = case[1], cleanup = function() end })
	drain()
	check(timing().virt_text[1][1] == case[2] and #rendered() == 0, "format assignment timing: " .. case[2])
	check(
		vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, {})[1] == 1,
		"timing anchors to final expression line"
	)
end
vim.cmd("vsplit")
local narrow = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(narrow, 12)
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { string.rep("long_code", 30) })
vim.api.nvim_exec_autocmds("WinResized", {})
drain()
check(
	timing().virt_text_pos == "eol_right_align" and #rendered() == 0,
	"resize and long code retain native per-window clipping"
)
vim.api.nvim_win_close(narrow, true)
entry = results.put(buf, 1, 1, { text = "", error = "failure", elapsed_ms = 142, cleanup = function() end })
drain()
check(timing().virt_text[1][1] == "142ms" and timing().virt_text[1][2] == "ArfElapsed", "R error shows fresh time")
entry = results.start(buf, 1, 1)
drain()
check(timing().virt_text == nil, "rerun removes previous time while running")
results.cancel(buf, entry)
check(#vim.api.nvim_buf_get_extmarks(buf, results.namespace, 0, -1, {}) == 0, "cancel removes running mark")
local deleted_buf = vim.api.nvim_create_buf(false, true)
results.put(deleted_buf, 0, 0, { text = "", elapsed_ms = 142, cleanup = function() end })
drain()
vim.api.nvim_buf_delete(deleted_buf, { force = true })
check(results.all()[deleted_buf] == nil, "buffer deletion removes timing state")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "x <- 1" })
local broken = { plots = { { image = {
	close = function()
		error("close failed")
	end,
} } } }
display.release(broken)
check(broken.plots == nil, "image close failure still clears reference")
package.loaded.snacks.image.placement.new = function()
	error("placement failed")
end
entry = results.put(buf, 1, 1, { text = "still visible", paths = { "unused.png" }, cleanup = function() end })
drain()
check(
	rendered()[2][1][1] == "still visible" and rendered()[3][1][1]:find("placement failed", 1, true),
	"placement failure keeps text and shows warning"
)
check(#rendered() == 4 and rendered()[4][1][1] == "", "blank line follows placement failure")
results.clear(buf)
entry = results.put(buf, 1, 1, { text = "first\nsecond", cleanup = function() end })
drain()
check(#rendered() == 4 and rendered()[4][1][1] == "", "blank line follows text output")
display.refresh()
drain()
check(#rendered() == 4, "refresh does not accumulate blank lines")
check(
	vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "inserted", "x <- 1", "plot(x + 1)" }),
	"display spacing leaves source lines unchanged"
)
results.clear(buf)
entry = results.put(buf, 1, 1, { text = "", cleanup = function() end })
drain()
check(#rendered() == 0, "empty output adds no spacing or separator")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "x <- 2" })
drain()
check(entry.stale and #rendered() == 0, "empty stale output adds no lines")
entry = results.put(buf, 1, 1, { text = "saved text", error = "failure", cleanup = function() end })
drain()
local previous_count = #rendered()
-- Editing changes color without changing output text or row count.
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "x <- 3" })
drain()
check(entry.stale and #rendered() == previous_count, "stale output keeps row count")
check(rendered()[2][1][1] == "saved text" and rendered()[2][1][2] == "ArfOutputStale", "dim stale text")
check(rendered()[3][1][2] == "ArfError", "preserve error color")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local win = require("arf").output()
local float_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
check(float_lines[1] == "saved text" and #float_lines == 2, "saved output has no extra notice")
local float_marks = vim.api.nvim_buf_get_extmarks(
	vim.api.nvim_win_get_buf(win),
	vim.api.nvim_create_namespace("arf.float"),
	0,
	-1,
	{ details = true }
)
check(float_marks[1][4].hl_group == "ArfFloatOutputStale", "dim saved output in float")
check(float_marks[2][4].hl_group == "ArfFloatError", "preserve float error color")
require("arf.float").close()
-- Parser-confirmed continuation moves the output below the extended pipeline.
local original_expression = package.loaded["arf.expression"]
package.loaded["arf.expression"] = {
	all = function()
		return { { first = 2, last = 3 } }
	end,
}
vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "continuation" })
drain()
check(entry.last == 2 and rendered()[2][1][2] == "ArfOutputStale", "follow extended expression")
check(vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, {})[1] == 2, "move output anchor")
package.loaded["arf.expression"] = original_expression
entry = results.put(buf, 1, 2, { text = "new result", cleanup = function() end })
drain()
check(rendered()[2][1][2] == "ArfOutput" and rendered()[1][1][2] == "ArfSeparator", "rerun restores normal colors")
results.clear(buf)
vim.api.nvim_buf_delete(buf, { force = true })
print("display tests passed (" .. checks .. " checks)")
