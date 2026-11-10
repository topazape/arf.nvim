local M = {}
local active

local function notify(err, level)
	vim.notify("arf: " .. tostring(err), level or vim.log.levels.ERROR)
end

local function release(result)
	if result then
		local ok, err = pcall(result.cleanup)
		if not ok then
			notify(err)
		end
	end
end

local function finish(request, discard)
	if active ~= request then
		return
	end
	active = nil
	if discard and request.handlers.discard then
		local ok, err = pcall(request.handlers.discard)
		if not ok then
			notify(err)
		end
	end
end

local function fail(request, err, result)
	release(result)
	finish(request, true)
	notify(err)
end

-- Resolve editor-dependent values once, before asynchronous startup. The executor
-- receives only evaluation options, independently of future setup() calls.
local function options()
	local config = require("arf.config").get()
	local output = vim.deepcopy(config.output)
	if output.tibble.width == "auto" then
		local win = vim.api.nvim_get_current_win()
		output.tibble.width = math.max(1, vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff)
	end
	return {
		executable = config.executable,
		pid = config.pid,
		startup_timeout_ms = config.startup_timeout_ms,
		eval_timeout_ms = config.eval_timeout_ms,
		output = output,
		image = { render = vim.deepcopy(config.image.render) },
	}
end

function M.run(codes, handlers)
	if active then
		return notify("R is running", vim.log.levels.WARN)
	end
	assert(#codes > 0, "arf: evaluation requires at least one expression")
	local request = { options = options(), handlers = handlers, index = 1 }
	request.external = request.options.pid ~= nil
	active = request
	local function valid()
		return not handlers.valid or handlers.valid()
	end
	local function start()
		if handlers.start then
			handlers.start(request.index)
		end
	end
	local function advance()
		if active ~= request then
			return
		end
		local ok, err = xpcall(function()
			if request.stop_requested or not valid() then
				return finish(request, true)
			end
			local completed = false
			local cancel = require("arf.executor").eval(codes[request.index], request.options, function(result, failure)
				completed = true
				if active ~= request then
					return release(result)
				end
				request.cancel = nil
				if failure then
					return fail(request, failure, result)
				end
				local handled, proceed = xpcall(function()
					return handlers.result(result, request.index)
				end, debug.traceback)
				if not handled then
					return fail(request, proceed, result)
				end
				if active ~= request then
					return
				end
				if
					request.stop_requested
					or result.status and result.status ~= "ok"
					or proceed == false
					or request.index == #codes
				then
					return finish(request)
				end
				request.index = request.index + 1
				local started, start_error = xpcall(start, debug.traceback)
				if not started then
					return fail(request, start_error)
				end
				vim.schedule(request.advance)
			end)
			if active == request and not completed then
				request.cancel = cancel
			end
		end, debug.traceback)
		if not ok then
			fail(request, err)
		end
	end
	request.advance = advance
	local ok, err = xpcall(function()
		if not valid() then
			return finish(request, true)
		end
		start()
		require("arf.session").ensure(request.options, function(pid, failure)
			if active ~= request then
				return
			end
			if failure then
				return fail(request, failure)
			end
			request.options.pid = pid
			advance()
		end)
	end, debug.traceback)
	if not ok then
		fail(request, err)
	end
end

function M.interrupt()
	local request = active
	if not request or not request.options.pid then
		return notify("No active R evaluation to interrupt", vim.log.levels.WARN)
	end
	if request.interrupt_pending then
		return
	end
	-- An interrupt request stops the sequence; accepting it does not release the
	-- active evaluation. Rejected/failed requests may be retried until it ends.
	request.stop_requested = true
	if not request.cancel then
		return
	end
	request.interrupt_pending = true
	local ok, err = pcall(require("arf.executor").interrupt, request.options, function(accepted, failure)
		if active ~= request then
			return
		end
		if failure or not accepted then
			request.interrupt_pending = false
		end
		if failure then
			notify(failure)
		elseif not accepted then
			notify("No active IPC evaluation accepted the interrupt", vim.log.levels.WARN)
		end
	end)
	if not ok then
		request.interrupt_pending = false
		notify(err)
	end
end

function M.stop()
	local request = active
	-- Ownership belongs to the request, not the latest setup() call.
	local external = request and request.external or not request and require("arf.config").get().pid ~= nil
	if external then
		notify("External sessions with an explicitly specified PID will not be stopped", vim.log.levels.WARN)
		return false
	end
	local cancel = request and request.cancel
	if request then
		finish(request, true)
	end
	require("arf.session").stop()
	if cancel then
		local ok, err = pcall(cancel)
		if not ok then
			notify(err)
		end
	end
	return true
end

return M
