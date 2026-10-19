-- Run with: nvim --headless -u NONE -l tests/snacks.lua
-- Optional real Snacks grid-renderer compatibility test. Override discovery with
-- ARF_TEST_SNACKS=/path/to/snacks.nvim. Terminal transport/image decoding are stubbed.
vim.opt.rtp:prepend(vim.fn.getcwd())
local root = vim.env.ARF_TEST_SNACKS or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
local path = root .. "/lua/snacks/image/placement.lua"
if vim.fn.filereadable(path) ~= 1 then
	assert(not vim.env.ARF_TEST_SNACKS, "ARF_TEST_SNACKS does not contain the placement module")
	print("Snacks unavailable; real grid-renderer integration skipped")
	return
end
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
_G.Snacks = {
	image = { terminal = {}, config = { debug = { placement = false }, icons = { image = "image" } } },
	util = { set_hl = function() end },
}
local real = dofile(path)
local placement
Snacks.image.placement = {
	new = function(buf, _, opts)
		placement = setmetatable({ buf = buf, opts = opts, id = 1, img = { id = 1 }, eids = {}, ns = real.ns }, real)
		return placement
	end,
}
package.loaded.snacks = Snacks
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plot(x)" })
local grid
require("arf.snacks").new(buf, 0, "unused.png", function(value)
	grid = value
end)
for _, height in ipairs({ 1, 3 }) do
	placement:render_grid({ 1, 0, width = 4, height = height })
	check(#placement.eids > 0, "real renderer creates placeholder extmarks")
	placement.opts.on_update(placement)
	check(#grid == height, "transfer real grid of height " .. height)
	check(grid[1][1][1]:find(vim.fn.nr2char(0x10EEEE), 1, true), "preserve Kitty placeholder characters")
	check(
		#placement.eids == 0 and #vim.api.nvim_buf_get_extmarks(buf, real.ns, 0, -1, {}) == 0,
		"remove real placement extmarks after transfer"
	)
end
vim.api.nvim_buf_delete(buf, { force = true })
print("Snacks grid-renderer tests passed (" .. checks .. " checks)")
