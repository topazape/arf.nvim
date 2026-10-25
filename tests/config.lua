vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local defaults = vim.deepcopy(arf.config)
assert(defaults.theme == "default", "default theme uses the neutral palette")
arf.setup({ float_width = 70, signs = { success = { text = "✓" } } })
arf.setup({ float_max_height = 12 })
assert(arf.config.float_width == 70 and arf.config.float_max_height == 12, "merge repeated setup")
assert(arf.config.signs.success.text == "✓" and arf.config.signs.success.hl == defaults.signs.success.hl)
assert(vim.deep_equal(defaults.signs.running, arf.config.signs.running), "preserve nested defaults")
assert(defaults.tibble_max_rows == false)
arf.setup({ tibble_max_rows = 100 })
assert(arf.config.tibble_max_rows == 100)
arf.setup({ tibble_max_rows = false })
assert(arf.config.tibble_max_rows == false)
assert(defaults.tibble_width == "auto")
for _, value in ipairs({ "auto", "all", 160, false }) do
	arf.setup({ tibble_width = value })
	assert(arf.config.tibble_width == value)
end
local function reject(opts)
	local before = vim.deepcopy(arf.config)
	assert(not pcall(arf.setup, opts), "reject " .. vim.inspect(opts))
	assert(vim.deep_equal(before, arf.config), "failed setup preserves configuration")
end
for _, value in ipairs({ "slate", "unknown", false, 1, {} }) do
	reject({ theme = value })
end
for _, key in ipairs({
	"image_max_width",
	"image_max_height",
	"plot_width_px",
	"plot_height_px",
	"plot_dpi",
	"inline_max_lines",
	"output_max_bytes",
	"float_width",
	"float_max_height",
}) do
	for _, value in ipairs({ 0, -1, 1.5, math.huge, "2", false }) do
		reject({ [key] = value })
	end
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, "100", true, {} }) do
	reject({ tibble_max_rows = value })
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "160", true, {} }) do
	reject({ tibble_width = value })
end
assert(defaults.float_width == "auto")
for _, value in ipairs({ "auto", 80 }) do
	arf.setup({ float_width = value })
	assert(arf.config.float_width == value)
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, "all", "80", false, 0 / 0 }) do
	reject({ float_width = value })
end
for old, new in pairs({
	output_width = "float_width",
	inspect_width = "float_width",
	output_max_height = "float_max_height",
	inspect_max_height = "float_max_height",
	output_max_lines = "inline_max_lines",
	image_width = "image_max_width",
	image_height = "image_max_height",
	plot_width = "plot_width_px",
	plot_height = "plot_height_px",
	plot_res = "plot_dpi",
	timeout = "eval_timeout",
}) do
	local ok, err = pcall(arf.setup, { [old] = 50 })
	assert(not ok and err:find(new, 1, true), "renamed setting identifies replacement")
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
