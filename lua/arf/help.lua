local M = {}
local generation = 0

local function unquote(name)
	return name:sub(1, 1) == "`" and name:sub(-1) == "`" and name:sub(2, -2) or name
end

local function next_name(line, from)
	local first, last = line:find("[%a_.\128-\255][%w_.\128-\255]*", from)
	local quoted_first, quoted_last = line:find("`[^`]+`", from)
	if quoted_first and (not first or quoted_first <= first) then
		return quoted_first, quoted_last
	end
	return first, last
end

local function cursor_topic()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local from = 1
	-- Match complete infix operators before the identifier inside them.
	while true do
		local first, last = line:find("%%[^%%]*%%", from)
		if not first then
			break
		end
		if first <= col and col <= last then
			return line:sub(first, last)
		end
		from = last + 1
	end
	from = 1
	while true do
		local first, last = next_name(line, from)
		if not first then
			break
		end
		local separator = line:sub(last + 1):match("^%s*:::%s*") or line:sub(last + 1):match("^%s*::%s*")
		if separator then
			local name_first, name_last = next_name(line, last + #separator + 1)
			if name_first == last + #separator + 1 then
				last = name_last
			end
		end
		if first <= col and col <= last then
			return line:sub(first, last)
		end
		from = last + 1
	end
	-- Operators also have help topics, including infix operators and subscripts.
	for _, pattern in ipairs({ "%[%[?", "[%+%-%*/%^:$@~!?&|<>=]+" }) do
		from = 1
		while true do
			local first, last = line:find(pattern, from)
			if not first then
				break
			end
			if first <= col and col <= last then
				return line:sub(first, last)
			end
			from = last + 1
		end
	end
end

local function query(topic)
	local package_name, name = topic:match("^([%a][%w.]*)%s*:::%s*(.+)$")
	if not package_name then
		package_name, name = topic:match("^([%a][%w.]*)%s*::%s*(.+)$")
	end
	return { topic = unquote(name or topic), package = package_name }
end

local function nonempty(value)
	return type(value) == "string" and value ~= "" and not value:find("[%c]")
end

local function candidate(value)
	return type(value) == "table"
		and nonempty(value.package)
		and nonempty(value.topic)
		and (value.help_key == nil or value.help_key == vim.NIL or nonempty(value.help_key))
		and (value.title == nil or type(value.title) == "string")
end

local function process_error(process)
	local stderr = process.stderr or ""
	local decoded, reply = pcall(vim.json.decode, stderr)
	if decoded and type(reply) == "table" and type(reply.error) == "table" then
		if type(reply.error.message) == "string" then
			return reply.error.message
		end
	end
	return stderr ~= "" and stderr or "arf help lookup failed (" .. tostring(process.code) .. ")"
end

function M.show(topic)
	generation = generation + 1
	local request = generation
	if topic == nil then
		topic = cursor_topic()
	end
	if not nonempty(topic) or not topic:find("%S") then
		return vim.notify("arf: Place the cursor on an R topic or provide :ArfHelp {topic}", vim.log.levels.WARN)
	end
	local initial = query(vim.trim(topic))
	local config = require("arf.config").get()
	local options = {
		executable = config.executable,
		pid = config.pid,
		startup_timeout_ms = config.startup_timeout_ms,
	}
	local float_options = vim.tbl_extend("force", config.float_window, {
		owner = vim.api.nvim_get_current_buf(),
		filetype = "markdown",
		wrap = true,
	})
	local win = vim.api.nvim_get_current_win()
	local tick = vim.api.nvim_buf_get_changedtick(float_options.owner)
	local function valid()
		return request == generation
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_win_get_buf(win) == float_options.owner
			and vim.api.nvim_buf_get_changedtick(float_options.owner) == tick
	end
	local function fail(err)
		if valid() then
			vim.notify("arf: " .. tostring(err), vim.log.levels.ERROR)
		end
	end
	local fetch
	fetch = function(selection, pid)
		if not valid() then
			return
		end
		local args = { options.executable, "ipc", "r-help", "show", "--pid", tostring(pid) }
		if selection.package then
			vim.list_extend(args, { "--package", selection.package })
		end
		if type(selection.help_key) == "string" then
			vim.list_extend(args, { "--help-key", selection.help_key })
		end
		-- Keep even option-like topics literal; never evaluate R source or use a shell.
		vim.list_extend(args, { "--", selection.topic })
		local ok, err = pcall(
			vim.system,
			args,
			{ text = true },
			vim.schedule_wrap(function(process)
				if not valid() then
					return
				end
				local handled, failure = pcall(function()
					if process.code ~= 0 then
						error(process_error(process), 0)
					end
					local reply = vim.json.decode(process.stdout)
					if type(reply) ~= "table" then
						error("Unable to read the help response from arf", 0)
					end
					if reply.kind == "page" then
						if not candidate(reply) or type(reply.content) ~= "string" then
							error("Invalid help page in arf response", 0)
						end
						local lines = {}
						for _, line in ipairs(vim.split(reply.content, "\n", { plain = true })) do
							lines[#lines + 1] = { { line } }
						end
						require("arf.float").open(reply.package .. "::" .. reply.topic, lines, float_options)
					elseif reply.kind == "candidates" then
						if
							type(reply.candidates) ~= "table"
							or not vim.islist(reply.candidates)
							or #reply.candidates == 0
						then
							error("Invalid help candidates in arf response", 0)
						end
						for _, item in ipairs(reply.candidates) do
							if not candidate(item) then
								error("Invalid help candidate in arf response", 0)
							end
						end
						vim.ui.select(reply.candidates, {
							prompt = "R help topic:",
							format_item = function(item)
								return item.package
									.. "::"
									.. item.topic
									.. (item.title and " — " .. item.title or "")
							end,
						}, function(item)
							if item then
								fetch(item, pid)
							end
						end)
					else
						error("Invalid help response from arf", 0)
					end
				end)
				if not handled then
					fail(failure)
				end
			end)
		)
		if not ok then
			fail(err)
		end
	end
	-- Help is served without entering R; do not route it through the evaluation lock.
	local ok, err = pcall(require("arf.session").ensure, options, function(pid, failure)
		if failure then
			return fail(failure)
		end
		fetch(initial, pid)
	end)
	if not ok then
		fail(err)
	end
end

return M
