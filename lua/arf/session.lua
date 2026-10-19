local M = {}
local current

local function finish(session, pid, err)
	if session.done then
		return
	end
	session.done = true
	if session.timer and not session.timer:is_closing() then
		session.timer:stop()
		session.timer:close()
	end
	local callbacks = session.callbacks
	session.callbacks = {}
	for _, callback in ipairs(callbacks) do
		callback(pid, err)
	end
end

function M.ensure(config, callback)
	-- Explicit sessions are borrowed: never start or terminate them.
	if config.pid then
		return callback(config.pid)
	end
	if current then
		if current.done then
			return callback(current.process.pid)
		end
		table.insert(current.callbacks, callback)
		return
	end
	local session = { callbacks = { callback }, output = "", stderr = "" }
	current = session
	local function fail(err)
		if session.done then
			return
		end
		if current == session then
			current = nil
		end
		if session.process then
			session.process:kill(15)
			session.process:wait(1000)
		end
		finish(session, nil, err)
	end
	local ok, process = pcall(
		vim.system,
		{ config.executable, "headless", "--json" },
		{
			cwd = vim.fn.getcwd(),
			text = true,
			stdout = vim.schedule_wrap(function(err, data)
				if session.done or current ~= session then
					return
				end
				if err then
					return fail("Unable to read arf startup output: " .. tostring(err))
				end
				if not data then
					return
				end
				session.output = session.output .. data
				while session.output:find("\n", 1, true) do
					local line, rest = session.output:match("^([^\n]*)\n(.*)$")
					session.output = rest
					local decoded, info = pcall(vim.json.decode, line)
					if decoded and type(info) == "table" and info.pid == session.process.pid then
						return finish(session, info.pid)
					end
				end
				-- R startup files can print arbitrary text; retain only bounded data.
				session.output = session.output:sub(-8192)
			end),
			stderr = vim.schedule_wrap(function(_, data)
				if data then
					session.stderr = (session.stderr .. data):sub(-8192)
				end
			end),
		},
		vim.schedule_wrap(function(result)
			if current == session then
				current = nil
			end
			if not session.done then
				finish(
					session,
					nil,
					"Failed to start arf (exit " .. result.code .. "): " .. session.stderr
				)
			end
		end)
	)
	if not ok then
		return fail(tostring(process))
	end
	session.process = process
	session.timer = vim.defer_fn(function()
		fail("Timed out starting arf")
	end, config.startup_timeout)
end

function M.stop()
	local session = current
	current = nil
	if not session then
		return
	end
	finish(session, nil, "The arf session has ended")
	-- Signal the child process we own, never a discovered or configured PID.
	-- Bound the wait so an active R evaluation cannot hold Neovim open.
	session.process:kill(15)
	-- Neovim escalates to SIGKILL if this wait times out.
	session.process:wait(1000)
end

local group = vim.api.nvim_create_augroup("arf.session", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
return M
