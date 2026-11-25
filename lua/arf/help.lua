local M = {}
local generation = 0

local function unquote(name)
	return name:sub(1, 1) == "`" and name:sub(-1) == "`" and name:sub(2, -2) or name
end

local function next_topic(line, from)
	local first, last
	for _, pattern in ipairs({ "[%a_.\128-\255][%w_.\128-\255]*", "`[^`]+`", "%%[^%%]*%%" }) do
		local start, finish = line:find(pattern, from)
		if start and (not first or start < first) then
			first, last = start, finish
		end
	end
	return first, last
end

local function cursor_topic()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local from = 1
	while true do
		local first, last = next_topic(line, from)
		if not first then
			break
		end
		local separator = line:sub(last + 1):match("^%s*:::%s*") or line:sub(last + 1):match("^%s*::%s*")
		if separator then
			local name_first, name_last = next_topic(line, last + #separator + 1)
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

function M.cancel()
	generation = generation + 1
end

function M.show(topic, search)
	M.cancel()
	local request = generation
	if topic == nil and not search then
		topic = cursor_topic()
	end
	if not nonempty(topic) or not topic:find("%S") then
		return vim.notify("arf: Place the cursor on an R topic or provide :ArfHelp {topic}", vim.log.levels.WARN)
	end
	local initial = search and nil or query(vim.trim(topic))
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
	local help_win, history, page, serial = nil, {}, nil, 0
	local function valid()
		if help_win then
			return request == generation and vim.api.nvim_win_is_valid(help_win)
		end
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
		serial = serial + 1
		local sequence = serial
		local args = { options.executable, "ipc", "r-help", "show", "--pid", tostring(pid) }
		if selection.current_package then
			vim.list_extend(args, { "--current-package", selection.current_package })
		end
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
				if not valid() or sequence ~= serial then
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
						if page and help_win and vim.api.nvim_win_is_valid(help_win) then
							page.cursor = vim.api.nvim_win_get_cursor(help_win)
							table.insert(history, page)
						end
						page = { reply = reply, lines = lines }
						local function render(item)
							help_win = require("arf.float").open(
								item.reply.package .. "::" .. item.reply.topic,
								item.lines,
								float_options
							)
							if not help_win then
								return
							end
							local buf = vim.api.nvim_win_get_buf(help_win)
							if item.cursor then
								vim.api.nvim_win_set_cursor(help_win, item.cursor)
							end
							vim.keymap.set("n", "<BS>", function()
								serial = serial + 1
								local previous = table.remove(history)
								if previous then
									page = previous
									render(previous)
								end
							end, { buffer = buf, silent = true })
							vim.keymap.set("n", "<CR>", function()
								local line = vim.api.nvim_get_current_line()
								local col = vim.api.nvim_win_get_cursor(help_win)[2] + 1
								local pos = 1
								while true do
									local a, b, target = line:find("%b[]%((x%-r%-help:[^%)]+)%)", pos)
									if not a then
										break
									end
									if col >= a and col <= b then
										local pkg, topic = target:match("^x%-r%-help:([^/]*)/(.+)$")
										if topic then
											fetch(
												{
													topic = topic,
													package = pkg ~= "" and pkg or nil,
													current_package = pkg == "" and item.reply.package or nil,
												},
												pid
											)
										end
										break
									end
									pos = b + 1
								end
							end, { buffer = buf, silent = true })
						end
						render(page)
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
							if item and valid() and sequence == serial then
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
		if not search then
			return fetch(initial, pid)
		end
		local args = { options.executable, "ipc", "r-help", "search", "--pid", tostring(pid), "--query", topic }
		local started, failure = pcall(
			vim.system,
			args,
			{ text = true },
			vim.schedule_wrap(function(process)
				if not valid() then
					return
				end
				local ok, reply = pcall(vim.json.decode, process.stdout or "")
				if process.code ~= 0 then
					return fail(process_error(process))
				end
				if
					not ok
					or type(reply) ~= "table"
					or type(reply.topics) ~= "table"
					or not vim.islist(reply.topics)
				then
					return fail("Invalid help search response")
				end
				for _, item in ipairs(reply.topics) do
					if not candidate(item) then
						return fail("Invalid help search result")
					end
				end
				if #reply.topics == 0 then
					return vim.notify("arf: No help topics found", vim.log.levels.INFO)
				end
				vim.ui.select(reply.topics, {
					prompt = "R help search:",
					format_item = function(item)
						return item.package .. "::" .. item.topic .. (item.title and " — " .. item.title or "")
					end,
				}, function(item)
					if item and valid() then
						fetch(item, pid)
					end
				end)
			end)
		)
		if not started then
			fail(failure)
		end
	end)
	if not ok then
		fail(err)
	end
end

function M.search(query_text)
	if query_text and query_text ~= "" then
		return M.show(query_text, true)
	end
	M.cancel()
	local request = generation
	vim.ui.input({ prompt = "R help search: " }, function(value)
		if request == generation and value and value:find("%S") then
			M.show(value, true)
		end
	end)
end

return M
