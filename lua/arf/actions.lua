local M = {}
local function evaluate(codes, result, start, discard, valid)
	return require("arf.execution").run(codes, { result = result, start = start, discard = discard, valid = valid })
end

local function source_validity(buf)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local results = require("arf.results")
	local generation = results.generation(buf)
	return function()
		return vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_get_changedtick(buf) == tick
			and results.generation(buf) == generation
	end
end

local function run_expressions(buf, expressions)
	if #expressions == 0 then
		return vim.notify("arf: No executable R expressions in the buffer", vim.log.levels.WARN)
	end
	local results = require("arf.results")
	local valid = source_validity(buf)
	local pending_entry
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

function M.copy_plot()
	local path = require("arf.results").latest_plot()
	if not path then
		return vim.notify("arf: No saved plot to copy", vim.log.levels.WARN)
	end
	require("arf.clipboard").copy(path)
end

function M.clear(buf)
	if not buf or buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	return require("arf.results").clear(buf)
end

function M.output()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local entry = require("arf.results").at(buf, row)
	if entry then
		if entry.status == "running" then
			return vim.notify("arf: R is running", vim.log.levels.WARN)
		end
		local lines = require("arf.output").full_lines(entry.result)
		if entry.stale then
			require("arf.output").stale(lines)
		end
		return require("arf.float").open(
			"arf output",
			lines,
			vim.tbl_extend("force", require("arf.config").get().float_window, { owner = buf })
		)
	end
	vim.notify("arf: No saved execution result at the cursor position", vim.log.levels.WARN)
end

---@class arf.InspectOpts
---@field title? string Complete float title; defaults to function(object).

---@param fn string R function name or package::function.
---@param opts? arf.InspectOpts
local function inspect_name(fn, opts, name)
	if opts ~= nil and type(opts) ~= "table" then
		return vim.notify("arf: inspect options must be a table", vim.log.levels.ERROR)
	end
	opts = opts or {}
	if opts.title ~= nil and (type(opts.title) ~= "string" or opts.title:find("[%c]")) then
		return vim.notify("arf: inspect title must be a string without control characters", vim.log.levels.ERROR)
	end
	local inspect = require("arf.inspect")
	local global_only = name ~= nil
	name = name or inspect.object()
	if not name then
		return vim.notify("arf: Place the cursor on an R object name", vim.log.levels.WARN)
	end
	local code, err = inspect.code(fn, name, global_only)
	if not code then
		return vim.notify("arf: " .. err, vim.log.levels.ERROR)
	end
	-- Capture the title now, independently of later changes to the caller's options.
	local display_fn = type(fn) == "table" and "inspect" or (fn == "base::summary" and "summary" or fn)
	local title = opts.title or (display_fn .. "(" .. (global_only and vim.fn.strtrans(name) or name) .. ")")
	local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	local valid = source_validity(buf)
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

function M.inspect(fn, opts)
	return inspect_name(fn, opts)
end

function M.objects()
	local picker = require("arf.object_picker")
	local available, err = picker.available()
	if not available then
		return vim.notify("arf: " .. err, vim.log.levels.ERROR)
	end
	local objects = require("arf.objects")
	local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	local function load(done, valid)
		evaluate({ objects.code }, function(result)
			result.cleanup()
			if result.error or result.truncated then
				vim.notify("arf: " .. (result.error or "Object list exceeded output.max_bytes"), vim.log.levels.ERROR)
				return
			end
			local ok, items = pcall(objects.decode, result.text)
			if not ok then
				return vim.notify("arf: Unable to read object list: " .. tostring(items), vim.log.levels.ERROR)
			end
			if valid() then
				local shown, show_error = pcall(done, items)
				if not shown then
					vim.notify("arf: " .. tostring(show_error), vim.log.levels.ERROR)
				end
			end
		end, nil, nil, valid)
	end
	load(function(items)
		picker.open(items, load, function(fn, name)
			inspect_name(fn, nil, name)
		end)
	end, function()
		return vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == buf
	end)
end

return M
