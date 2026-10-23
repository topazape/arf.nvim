local M = {}
M.config = {
	theme = "default",
	executable = "arf",
	pid = nil,
	timeout = 300000,
	startup_timeout = 10000,
	image_width = 100,
	image_height = 30,
	plot_width = 1200,
	plot_height = 800,
	plot_res = 180,
	inspect_width = 120,
	inspect_max_height = 20,
	tibble_max_rows = false,
	output_max_lines = 20,
	output_max_bytes = 1048576,
	output_width = 120,
	output_max_height = 30,
	signs = {
		enabled = true,
		priority = 5,
		range = { text = "│", hl = "ArfSignRange" },
		success = { text = "", hl = "ArfSignSuccess" },
		error = { text = "", hl = "ArfSignError" },
		running = {
			text = "…",
			hl = "ArfSignRunning",
			frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
			interval = 80,
		},
	},
}
local busy = false
local epoch = 0
local cancel_current

function M.setup(opts)
	local config = vim.tbl_deep_extend("force", M.config, opts or {})
	assert(
		config.theme == "auto" or config.theme == "default" or config.theme == "neon",
		'arf: theme must be "default", "auto", or "neon"'
	)
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
		local value = config[key]
		assert(
			type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value),
			"arf: " .. key .. " must be a positive integer"
		)
	end
	assert(
		config.tibble_max_rows == false
			or (
				type(config.tibble_max_rows) == "number"
				and config.tibble_max_rows > 0
				and config.tibble_max_rows < math.huge
				and config.tibble_max_rows == math.floor(config.tibble_max_rows)
			),
		"arf: tibble_max_rows must be false or a positive integer"
	)
	require("arf.signs").validate(config.signs)
	M.config = config
	require("arf.highlights").apply(config.theme)
end

-- Inline execution and inspection use the same session and busy guard.
local function evaluate(codes, callback, on_start, on_error, valid)
	if busy then
		return vim.notify("arf: R is running", vim.log.levels.WARN)
	end
	busy = true
	local request_epoch = epoch
	local index = 1
	local function finish()
		busy = false
		cancel_current = nil
	end
	local function failed(err)
		finish()
		if on_error then
			on_error()
		end
		vim.notify("arf: " .. err, vim.log.levels.ERROR)
	end
	if on_start then
		on_start(index)
	end
	require("arf.session").ensure(M.config, function(pid, startup_error)
		if request_epoch ~= epoch then
			return
		end
		if startup_error then
			return failed(startup_error)
		end
		local config = vim.tbl_extend("force", M.config, { pid = pid })
		local function next_expression()
			if request_epoch ~= epoch then
				return
			end
			if valid and not valid() then
				finish()
				if on_error then
					on_error()
				end
				return
			end
			local cancel = require("arf.executor").eval(codes[index], config, function(result, err)
				if request_epoch ~= epoch then
					if result then
						result.cleanup()
					end
					return
				end
				cancel_current = nil
				if err then
					return failed(err)
				end
				local proceed = callback(result, index)
				if proceed == false or index == #codes then
					return finish()
				end
				index = index + 1
				if on_start then
					on_start(index)
				end
				-- Yield between expressions, keeping the shared busy guard held.
				vim.schedule(next_expression)
			end)
			if busy and request_epoch == epoch then
				cancel_current = cancel
			end
		end
		next_expression()
	end)
end

local function run_expressions(buf, expressions)
	if #expressions == 0 then
		return vim.notify("arf: No executable R expressions in the buffer", vim.log.levels.WARN)
	end
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local results = require("arf.results")
	local generation = results.generation(buf)
	local pending_entry
	local function valid()
		return vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_get_changedtick(buf) == tick
			and results.generation(buf) == generation
	end
	local codes = {}
	for _, expression in ipairs(expressions) do
		codes[#codes + 1] = expression.code
	end
	evaluate(codes, function(result, index)
		if not valid() then
			result.cleanup()
			results.cancel(buf, pending_entry)
			return false
		end
		local expression = expressions[index]
		results.put(buf, expression.first - 1, expression.last - 1, result)
		if result.error then
			vim.notify("arf: " .. result.error, vim.log.levels.ERROR)
			return false
		end
	end, function(index)
		local expression = expressions[index]
		pending_entry = results.start(buf, expression.first - 1, expression.last - 1)
	end, function()
		results.cancel(buf, pending_entry)
	end, valid)
end

function M.run(first, last)
	local buf = vim.api.nvim_get_current_buf()
	local expression, err
	if first == nil then
		expression, err = require("arf.expression").current(buf)
		if not expression then
			return vim.notify("arf: " .. err, vim.log.levels.WARN)
		end
	else
		last = last or first
		expression = {
			first = first,
			last = last,
			code = table.concat(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), "\n"),
		}
	end
	run_expressions(buf, { expression })
end

function M.run_all()
	local buf = vim.api.nvim_get_current_buf()
	local expressions, err = require("arf.expression").all(buf)
	if not expressions then
		return vim.notify("arf: " .. err, vim.log.levels.WARN)
	end
	run_expressions(buf, expressions)
end

function M.clear(buf)
	if not buf or buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	return require("arf.results").clear(buf)
end

function M.stop()
	if M.config.pid then
		return vim.notify(
			"arf: External sessions with an explicitly specified PID will not be stopped",
			vim.log.levels.WARN
		)
	end
	epoch = epoch + 1
	busy = false
	local cancel = cancel_current
	cancel_current = nil
	require("arf.session").stop()
	if cancel then
		cancel()
	end
	require("arf.float").close()
	local results = require("arf.results")
	for buf in pairs(results.all()) do
		results.clear(buf)
	end
end

function M.output()
	local buf = vim.api.nvim_get_current_buf()
	require("arf.results").sync_ranges(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local state = require("arf.results").all()[buf]
	for _, entry in ipairs(state and state.entries or {}) do
		if entry.first <= row and row <= entry.last then
			if entry.running then
				return vim.notify("arf: R is running", vim.log.levels.WARN)
			end
			local lines = require("arf.output").full_lines(entry.result)
			if entry.stale then
				require("arf.output").stale(lines)
			end
			return require("arf.float").open("arf output", lines, {
				width = M.config.output_width,
				max_height = M.config.output_max_height,
				owner = buf,
			})
		end
	end
	vim.notify("arf: No saved execution result at the cursor position", vim.log.levels.WARN)
end

---@class arf.InspectOpts
---@field title? string Complete float title; defaults to function(object).

---@param fn string R function name or package::function.
---@param opts? arf.InspectOpts
function M.inspect(fn, opts)
	if opts ~= nil and type(opts) ~= "table" then
		return vim.notify("arf: inspect options must be a table", vim.log.levels.ERROR)
	end
	opts = opts or {}
	if opts.title ~= nil and (type(opts.title) ~= "string" or opts.title:find("[%c]")) then
		return vim.notify("arf: inspect title must be a string without control characters", vim.log.levels.ERROR)
	end
	local inspect = require("arf.inspect")
	local name = inspect.object()
	if not name then
		return vim.notify("arf: Place the cursor on an R object name", vim.log.levels.WARN)
	end
	local code, err = inspect.code(fn, name)
	if not code then
		return vim.notify("arf: " .. err, vim.log.levels.ERROR)
	end
	-- Capture the title now, independently of later changes to the caller's options.
	local display_fn = type(fn) == "table" and "inspect" or (fn == "base::summary" and "summary" or fn)
	local title = opts.title or (display_fn .. "(" .. name .. ")")
	local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local results = require("arf.results")
	local generation = results.generation(buf)
	local function valid()
		return vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_get_changedtick(buf) == tick
			and results.generation(buf) == generation
	end
	evaluate({ code }, function(result)
		-- Inspection is text-only; release any captured plots as well.
		result.cleanup()
		-- Discard stale results and do not steal focus after a window/buffer change.
		if
			valid()
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == buf
		then
			local shown, show_error = pcall(inspect.show, title, result, buf)
			if not shown then
				vim.notify("arf: " .. tostring(show_error), vim.log.levels.ERROR)
			end
		end
	end, nil, nil, valid)
end

-- Keep the existing public API as a shorthand for inspection.
function M.summary()
	return M.inspect("base::summary")
end

return M
