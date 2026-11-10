local M = {}
local current = {
	executable = "arf",
	startup_timeout_ms = 10000,
	eval_timeout_ms = 300000,
	output = { max_bytes = 1048576, tibble = { max_rows = "inherit", width = "auto" } },
	inline = { max_lines = 20, border = "line" },
	float_window = { width = "60%", max_height = 30 },
	image = {
		render = { width_px = 1200, height_px = 800, dpi = 180 },
		display = { max_width = 100, max_height = 30 },
	},
	theme = "default",
	signs = {
		enabled = true,
		priority = 5,
		range = { text = "│" },
		success = { text = "│", hl = "ArfSignSuccess" },
		error = { text = "│", hl = "ArfSignError" },
		interrupted = { text = "│", hl = "ArfSignInterrupted" },
		running = {
			text = "…",
			hl = "ArfSignRunning",
			frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
			interval_ms = 80,
		},
	},
}

local function expect(ok, path, description)
	assert(ok, "arf: " .. path .. " must be " .. description)
end

local function integer(value)
	return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function positive(value, path)
	expect(integer(value) and value > 0, path, "a positive integer")
end

-- Validate the supplied shape before merging, including unknown nested keys.
local function shape(opts, defaults, prefix)
	expect(type(opts) == "table", prefix == "" and "options" or prefix, "a table")
	for key, value in pairs(opts) do
		local path = prefix == "" and tostring(key) or prefix .. "." .. tostring(key)
		assert(defaults[key] ~= nil or path == "pid", "arf: unknown setting " .. path)
		if type(defaults[key]) == "table" then
			expect(type(value) == "table", path, "a table")
			if path ~= "signs.running.frames" then
				shape(value, defaults[key], path)
			end
		end
	end
end

local function symbol(value, path, empty)
	local width = type(value) == "string" and vim.fn.strdisplaywidth(value) or 0
	expect(
		type(value) == "string" and not value:find("[%c]") and (empty and value == "" or width >= 1 and width <= 2),
		path,
		empty and "empty or 1–2 display cells without control characters"
			or "1–2 display cells without control characters"
	)
end

local function validate(config)
	expect(
		type(config.executable) == "string"
			and config.executable:find("%S") ~= nil
			and not config.executable:find("[%c]"),
		"executable",
		"a non-empty command name or path"
	)
	if config.pid ~= nil then
		positive(config.pid, "pid")
	end
	positive(config.startup_timeout_ms, "startup_timeout_ms")
	positive(config.eval_timeout_ms, "eval_timeout_ms")
	positive(config.output.max_bytes, "output.max_bytes")
	positive(config.inline.max_lines, "inline.max_lines")
	positive(config.float_window.max_height, "float_window.max_height")
	for _, key in ipairs({ "width_px", "height_px", "dpi" }) do
		positive(config.image.render[key], "image.render." .. key)
	end
	for _, key in ipairs({ "max_width", "max_height" }) do
		positive(config.image.display[key], "image.display." .. key)
	end
	expect(
		config.inline.border == "rounded"
			or config.inline.border == "single"
			or config.inline.border == "double"
			or config.inline.border == "line"
			or config.inline.border == "none",
		"inline.border",
		'"rounded", "single", "double", "line", or "none"'
	)
	local tibble = config.output.tibble
	if tibble.max_rows ~= "inherit" then
		positive(tibble.max_rows, "output.tibble.max_rows")
	end
	if tibble.width ~= "inherit" and tibble.width ~= "auto" and tibble.width ~= "all" then
		positive(tibble.width, "output.tibble.width")
	end
	local width = config.float_window.width
	local percent = type(width) == "string" and tonumber(width:match("^(%d+)%%$"))
	expect(
		width == "auto" or integer(width) and width > 0 or percent and percent >= 1 and percent <= 100,
		"float_window.width",
		'"auto", a positive integer, or "1%" to "100%"'
	)
	expect(
		config.theme == "default" or config.theme == "auto" or config.theme == "neon",
		"theme",
		'"default", "auto", or "neon"'
	)
	local signs = config.signs
	expect(type(signs.enabled) == "boolean", "signs.enabled", "a boolean")
	expect(integer(signs.priority), "signs.priority", "a non-negative integer")
	symbol(signs.range.text, "signs.range.text", true)
	for _, key in ipairs({ "success", "error", "interrupted", "running" }) do
		local sign = signs[key]
		symbol(sign.text, "signs." .. key .. ".text", true)
		expect(
			type(sign.hl) == "string" and sign.hl:match("^[%w_@.]+$") ~= nil,
			"signs." .. key .. ".hl",
			"a highlight group name"
		)
	end
	expect(vim.islist(signs.running.frames), "signs.running.frames", "a list")
	for _, frame in ipairs(signs.running.frames) do
		symbol(frame, "signs.running.frames", false)
	end
	positive(signs.running.interval_ms, "signs.running.interval_ms")
end

function M.get()
	return current
end

function M.setup(opts)
	opts = opts == nil and {} or opts
	shape(opts, current, "")
	local candidate = vim.tbl_deep_extend("force", current, opts)
	-- nil is absent from Lua option tables; false explicitly restores auto-start.
	if opts.pid == false then
		candidate.pid = nil
	end
	validate(candidate)
	current = candidate
	return current
end

return M
