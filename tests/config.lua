vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local defaults = vim.deepcopy(arf.config)
arf.setup({ float_window = { width = 70 }, signs = { success = { text = "✓" } } })
arf.setup({ float_window = { max_height = 12 } })
assert(arf.config.float_window.width == 70 and arf.config.float_window.max_height == 12)
assert(arf.config.signs.success.hl == defaults.signs.success.hl)
assert(vim.deep_equal(defaults.signs.running, arf.config.signs.running))
local function reject(opts, path)
	local before = vim.deepcopy(arf.config)
	local ok, err = pcall(arf.setup, opts)
	assert(not ok, "reject " .. vim.inspect(opts))
	if path then
		assert(tostring(err):find(path, 1, true), tostring(err))
	end
	assert(vim.deep_equal(before, arf.config), "failed setup preserves configuration")
	assert(arf.config == require("arf.config").get())
end
local function setting(path, value)
	local opts, node = {}, nil
	node = opts
	local keys = vim.split(path, ".", { plain = true })
	for i = 1, #keys - 1 do
		node[keys[i]] = {}
		node = node[keys[i]]
	end
	node[keys[#keys]] = value
	return opts
end
for _, path in ipairs({
	"pid",
	"startup_timeout",
	"eval_timeout",
	"output.max_bytes",
	"output.tibble.max_rows",
	"inline.max_lines",
	"float_window.max_height",
	"image.render.width_px",
	"image.render.height_px",
	"image.render.dpi",
	"image.display.max_width",
	"image.display.max_height",
}) do
	for _, value in ipairs({ 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "2", true, {} }) do
		reject(setting(path, value), path)
	end
end
for _, value in ipairs({ false, 1, {}, "", " \n", "bad\0path" }) do
	reject({ executable = value }, "executable")
end
for _, value in ipairs({ "slate", false, 1, {} }) do
	reject({ theme = value }, "theme")
end
for _, value in ipairs({ false, 1, "options" }) do
	reject(value, "options")
end
for _, path in ipairs({ "output", "output.tibble", "image", "image.render", "inline", "float_window", "signs" }) do
	reject(setting(path, false), path)
end
for _, path in ipairs({
	"unknown",
	"float_width",
	"output_width",
	"timeout",
	"output.typo",
	"image.display.width",
	"signs.range.hl",
}) do
	reject(setting(path, 1), path)
end
for _, value in ipairs({ false, "auto", "all", 160 }) do
	arf.setup({ output = { tibble = { width = value } } })
	assert(arf.config.output.tibble.width == value)
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, 0 / 0, "160", true, {} }) do
	reject({ output = { tibble = { width = value } } }, "output.tibble.width")
end
for _, value in ipairs({ 100, false }) do
	arf.setup({ output = { tibble = { max_rows = value } } })
	assert(arf.config.output.tibble.max_rows == value)
end
for _, value in ipairs({ "auto", 80, "1%", "90%", "100%" }) do
	arf.setup({ float_window = { width = value } })
	assert(arf.config.float_window.width == value)
end
for _, value in ipairs({ 0, -1, 1.5, math.huge, "all", "80", "0%", "101%", "90.5%", "-5%", false, {} }) do
	reject({ float_window = { width = value } }, "float_window.width")
end
for _, signs in ipairs({
	{ enabled = "yes" },
	{ priority = -1 },
	{ priority = 1.5 },
	{ success = { text = "wide" } },
	{ error = { text = "\n" } },
	{ success = { hl = "" } },
	{ success = { hl = "bad\nname" } },
	{ running = { frames = { "" } } },
	{ running = { frames = { bad = "x" } } },
	{ running = { interval = 0 } },
}) do
	reject({ signs = signs })
end
arf.setup({ signs = { priority = 0, running = { frames = {} } } })
assert(arf.config.signs.priority == 0 and #arf.config.signs.running.frames == 0)
local supplied = { image = { render = { dpi = 200 } } }
arf.setup(supplied)
supplied.image.render.dpi = 300
assert(arf.config.image.render.dpi == 200, "setup does not retain caller tables")
print("configuration tests passed")
