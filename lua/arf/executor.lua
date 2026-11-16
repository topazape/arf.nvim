local M = {}
local output = require("arf.output")
local function string_field(reply, key)
	return type(reply[key]) == "string" and reply[key] or ""
end

function M.eval(source, config, callback, on_timeout)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p", 448)
	local function cleanup()
		vim.fn.delete(dir, "rf")
	end
	local generated, code = pcall(require("arf.r_code").capture, source, config, dir)
	if not generated then
		cleanup()
		return callback(nil, tostring(code))
	end
	local args = { config.executable, "ipc", "eval", "--visible", "--timeout", tostring(config.eval_timeout_ms) }
	if config.pid then
		vim.list_extend(args, { "--pid", tostring(config.pid) })
	end
	-- stdin avoids command-line size limits and shell interpretation.
	local cancelled, completed = false, false
	local timer
	local function stop_timer()
		if timer then
			timer:stop()
			timer:close()
			timer = nil
		end
	end
	local function fail(err)
		completed = true
		stop_timer()
		cleanup()
		if not cancelled then
			callback(nil, err)
		end
	end
	local function wait_for_capture(err)
		local function poll()
			if vim.uv.fs_stat(dir .. "/finished") then
				return fail(err)
			end
			local alive, reason = vim.uv.kill(config.pid, 0)
			if not alive and type(reason) == "string" and reason:find("ESRCH", 1, true) then
				fail(err)
			end
		end
		timer = assert(vim.uv.new_timer())
		timer:start(
			0,
			100,
			vim.schedule_wrap(function()
				if not cancelled and not completed then
					poll()
				end
			end)
		)
	end
	local started = vim.uv.hrtime()
	local ok, process = pcall(
		vim.system,
		args,
		{ text = true, stdin = code },
		vim.schedule_wrap(function(process)
			if cancelled then
				cleanup()
				return
			end
			if process.code ~= 0 then
				local decoded, reply = pcall(vim.json.decode, process.stderr)
				local err = decoded and type(reply) == "table" and reply.error
				local data = type(err) == "table" and err.data
				if
					type(err) == "table"
					and err.code == "TIMEOUT"
					and type(data) == "table"
					and type(data.execution_id) == "number"
					and config.pid
				then
					-- The CLI has exited, but R still owns the capture files. Keep the
					-- request active until its finalizer runs or the session exits.
					wait_for_capture(type(err.message) == "string" and err.message or "R evaluation timed out")
					if on_timeout then
						on_timeout(data.execution_id)
					end
					return
				end
			end
			completed = true
			local decoded, result = pcall(function()
				if process.code ~= 0 then
					error(process.stderr ~= "" and process.stderr or "arf IPC failed (" .. process.code .. ")", 0)
				end
				local decoded, reply = pcall(vim.json.decode, process.stdout)
				if not decoded or type(reply) ~= "table" then
					error("Unable to read the JSON response from arf", 0)
				end
				local errors = {
					error = "R evaluation failed (see captured output)",
					interrupted = "R evaluation interrupted",
					unknown = "R evaluation outcome is unknown",
				}
				local status = reply.status
				if status ~= "ok" and not errors[status] then
					error("Invalid evaluation status in arf response", 0)
				end
				local err = status ~= "ok" and (type(reply.error) == "string" and reply.error or errors[status]) or nil
				local text, chunks = output.decode(
					string_field(reply, "stdout"),
					string_field(reply, "stderr"),
					output.read_messages(dir .. "/messages.bin", config.output.max_bytes)
				)
				local files = vim.fn.glob(dir .. "/plot-*.png", false, true)
				table.sort(files)
				local result = output.limit({
					text = text,
					chunks = chunks,
					truncated = vim.uv.fs_stat(dir .. "/truncated") ~= nil,
					paths = files,
					status = status,
					error = err,
					cleanup = cleanup,
				}, config.output.max_bytes)
				result.elapsed_ms = (vim.uv.hrtime() - started) / 1e6
				return result
			end)
			if not decoded then
				cleanup()
				return callback(nil, result)
			end
			callback(result)
		end)
	)
	if not ok then
		cleanup()
		callback(nil, tostring(process))
		return
	end
	return function()
		if completed or cancelled then
			return
		end
		cancelled = true
		stop_timer()
		local killed, err = pcall(process.kill, process, 15)
		cleanup()
		if not killed then
			error(err)
		end
	end
end
function M.interrupt(config, callback)
	local args = { config.executable, "ipc", "interrupt", "--pid", tostring(config.pid) }
	if config.execution_id then
		vim.list_extend(args, { "--execution-id", tostring(config.execution_id) })
	end
	local ok, err = pcall(
		vim.system,
		args,
		{ text = true },
		vim.schedule_wrap(function(process)
			if process.code ~= 0 then
				return callback(
					nil,
					process.stderr ~= "" and process.stderr or "arf interrupt failed (" .. process.code .. ")"
				)
			end
			local decoded, reply = pcall(vim.json.decode, process.stdout)
			if not decoded or type(reply) ~= "table" or type(reply.accepted) ~= "boolean" then
				return callback(nil, "Unable to read the interrupt response from arf")
			end
			callback(reply.accepted)
		end)
	)
	if not ok then
		callback(nil, tostring(err))
	end
end
return M
