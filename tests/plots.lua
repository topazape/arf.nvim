-- Run with: nvim --headless -u NONE -l tests/plots.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
require("arf").setup({})
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plot(model)", "next" })
local created, closed, callbacks = {}, {}, {}
package.loaded["arf.snacks"] = {
	available = function()
		return true
	end,
	new = function(_, _, path, on_grid)
		created[#created + 1] = path
		callbacks[path] = on_grid
		on_grid({ { { path, "Normal" } } })
		return {
			opts = {},
			show = function() end,
			update = function() end,
			close = function()
				closed[#closed + 1] = path
			end,
		}
	end,
}
local results = require("arf.results")
local display = require("arf.display")
local cleaned = 0
local entry = results.put(buf, 0, 0, {
	text = "output",
	paths = { "one.png", "two.png", "three.png", "four.png" },
	cleanup = function()
		cleaned = cleaned + 1
	end,
})
local function flush()
	vim.wait(30, function()
		return false
	end)
end
local function lines()
	return vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, { details = true })[3].virt_lines
end
flush()
assert(#created == 4)
assert(lines()[3][1][1] == "one.png" and lines()[6][1][1] == "four.png", "stack in generation order")
callbacks["two.png"]({ { { "updated", "Normal" } }, { { "second row", "Normal" } } })
flush()
assert(lines()[4][1][1] == "updated" and lines()[7][1][1] == "four.png", "async resize keeps order")
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "before" })
flush()
for _, plot in ipairs(entry.plots) do
	assert(plot.image.opts.pos[1] == 2, "all images move with the expression")
end
assert(#created == 4, "refresh reuses placements")
results.put(buf, 1, 1, { text = "replacement", paths = {}, cleanup = function() end })
flush()
assert(#closed == 4 and cleaned == 1, "replacement releases every image")
results.put(buf, 1, 1, { text = "", paths = { "last.png" }, cleanup = function() end })
flush()
results.clear(buf)
assert(#closed == 5, "clear releases images")
print("plot display tests passed")
