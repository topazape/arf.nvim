vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local defaults = vim.deepcopy(arf.config)
assert(defaults.theme == "default", "default theme uses the neutral palette")
arf.setup({ output_width = 70, signs = { success = { text = "✓" } } })
arf.setup({ output_max_height = 12 })
assert(arf.config.output_width == 70 and arf.config.output_max_height == 12, "merge repeated setup")
assert(arf.config.signs.success.text == "✓" and arf.config.signs.success.hl == defaults.signs.success.hl)
assert(vim.deep_equal(defaults.signs.running, arf.config.signs.running), "preserve nested defaults")
assert(defaults.tibble_max_rows == false)
arf.setup({ tibble_max_rows = 100 })
assert(arf.config.tibble_max_rows == 100)
arf.setup({ tibble_max_rows = false })
assert(arf.config.tibble_max_rows == false)
local function reject(opts)
	local before = vim.deepcopy(arf.config)
	assert(not pcall(arf.setup, opts), "reject " .. vim.inspect(opts))
	assert(vim.deep_equal(before, arf.config), "failed setup preserves configuration")
end
for _, value in ipairs({ "slate", "unknown", false, 1, {} }) do
	reject({ theme = value })
end
for _, key in ipairs({
	"plot_width",
	"plot_height",
	"plot_res",
	"inspect_width",
	"inspect_max_height",
	"output_max_lines",
	"output_max_bytes",
	"output_width",
	"output_max_height",
}) do
	for _, value in ipairs({ 0, -1, 1.5, math.huge, "2", false }) do
		reject({ [key] = value })
	end
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, "100", true, {} }) do
	reject({ tibble_max_rows = value })
end
for _, signs in ipairs({
	{ enabled = "yes" },
	{ priority = -1 },
	{ priority = 0.5 },
	{ success = { text = "wide" } },
	{ error = { text = "\n" } },
	{ range = { hl = "" } },
	{ running = { frames = { "" } } },
	{ running = { frames = { bad = "x" } } },
	{ running = { interval = 0 } },
}) do
	reject({ signs = signs })
end
arf.setup({ signs = { priority = 0, running = { frames = {} } } })
assert(arf.config.signs.priority == 0 and #arf.config.signs.running.frames == 0)
print("configuration tests passed")
