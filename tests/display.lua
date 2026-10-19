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
	path = "unused.png",
	cleanup = function()
		cleaned = cleaned + 1
	end,
})
drain()
local function rendered()
	return vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, { details = true })[3].virt_lines
end
local lines = rendered()
check(lines[2][1][1] == "text survives", "text displays without image dependency")
check(lines[3][1][1]:find("snacks.nvim is required", 1, true), "missing backend has inline warning")
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
	opts.pos[1] == 2 and opts.max_width == require("arf").config.image_width,
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
end
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "inserted" })
drain()
check(entry.image.opts.pos[1] == 3 and entry.image.opts.range[1] == 3, "move placement after source edit before range")
results.clear(buf)
drain()
check(closed == 1 and cleaned == 1, "clear releases image and evaluation resources")
local broken = { image = {
	close = function()
		error("close failed")
	end,
} }
display.release(broken)
check(broken.image == nil, "image close failure still clears reference")
package.loaded.snacks.image.placement.new = function()
	error("placement failed")
end
entry = results.put(buf, 1, 1, { text = "still visible", path = "unused.png", cleanup = function() end })
drain()
check(
	rendered()[2][1][1] == "still visible" and rendered()[3][1][1]:find("placement failed", 1, true),
	"placement failure keeps text and shows warning"
)
results.clear(buf)
vim.api.nvim_buf_delete(buf, { force = true })
print("display tests passed (" .. checks .. " checks)")
