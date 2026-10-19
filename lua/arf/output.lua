local M = {}
local function clean(text)
	return text:gsub("\27%[[0-9;]*m", "")
end

-- Offsets refer to raw stderr bytes; ANSI stripping happens after classification.
-- A record is used only if the actual emitted bytes match its condition text.
function M.read_messages(path, max_bytes)
	local file = io.open(path, "rb")
	if not file then
		return {}
	end
	local data = file:read(max_bytes or "*a") or ""
	file:close()
	local function integer(offset)
		local a, b, c, d = data:byte(offset, offset + 3)
		return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
	end
	local messages, offset = {}, 1
	while offset + 7 <= #data do
		local position, size = integer(offset), integer(offset + 4)
		offset = offset + 8
		if offset + size - 1 > #data then
			break
		end
		messages[#messages + 1] = { offset = position, text = data:sub(offset, offset + size - 1) }
		offset = offset + size
	end
	return messages
end

function M.decode(stdout, stderr, messages)
	local chunks = {}
	local function add(text, highlight)
		text = clean(text)
		if text ~= "" then
			chunks[#chunks + 1] = { text = text, highlight = highlight }
		end
	end
	add(stdout, "ArfOutput")
	local offset = 1
	for _, message in ipairs(messages or {}) do
		local first, last = message.offset + 1, message.offset + #message.text
		if first >= offset and message.text ~= "" and stderr:sub(first, last) == message.text then
			add(stderr:sub(offset, first - 1), "ArfStderr")
			add(message.text, "ArfMessage")
			offset = last + 1
		end
	end
	add(stderr:sub(offset), "ArfStderr")
	if #chunks > 0 then
		chunks[#chunks].text = chunks[#chunks].text:gsub("\n$", "")
	end
	local text = {}
	for _, chunk in ipairs(chunks) do
		text[#text + 1] = chunk.text
	end
	return table.concat(text), chunks
end

local function prefix(text, bytes)
	if #text <= bytes then
		return text
	end
	while bytes > 0 do
		local next_byte = text:byte(bytes + 1)
		if not next_byte or next_byte < 0x80 or next_byte > 0xbf then
			break
		end
		bytes = bytes - 1
	end
	return text:sub(1, bytes)
end

function M.limit(result, budget)
	local chunks, parts = {}, {}
	local cut = false
	for _, chunk in ipairs(result.chunks or { { text = result.text, highlight = "ArfOutput" } }) do
		local text = cut and "" or prefix(chunk.text, budget)
		if #text < #chunk.text then
			cut = true
			result.truncated = true
		end
		if text ~= "" then
			chunks[#chunks + 1] = { text = text, highlight = chunk.highlight }
			parts[#parts + 1] = text
		end
		budget = budget - #text
	end
	result.text, result.chunks = table.concat(parts), chunks
	if result.error then
		local error = prefix(result.error, budget)
		if #error < #result.error then
			result.truncated = true
		end
		result.error = error
	end
	return result
end

local function content(result)
	local chunks = vim.list_extend({}, result.chunks or { { text = result.text, highlight = "ArfOutput" } })
	local text = result.text
	if result.error then
		local error = (text ~= "" and "\n" or "") .. "R error: " .. result.error
		chunks[#chunks + 1] = { text = error, highlight = "ArfError" }
		text = text .. error
	end
	return text, chunks
end

-- Stop building lines once the preview is full; a million short output lines
-- should not allocate a million virtual-line tables.
function M.lines(result, limit)
	local text, chunks = content(result)
	if text == "" then
		return {}, 0
	end
	local _, newlines = text:gsub("\n", "")
	local total = newlines + 1
	local lines = { {} }
	for _, chunk in ipairs(chunks) do
		local offset = 1
		while true do
			local newline = chunk.text:find("\n", offset, true)
			local piece = chunk.text:sub(offset, newline and newline - 1 or #chunk.text)
			if piece ~= "" then
				lines[#lines][#lines[#lines] + 1] = { piece, chunk.highlight }
			end
			if not newline then
				break
			end
			if limit and #lines >= limit then
				for _, line in ipairs(lines) do
					if #line == 0 then
						line[1] = { "", "ArfOutput" }
					end
				end
				return lines, total
			end
			lines[#lines + 1] = {}
			offset = newline + 1
		end
	end
	for _, line in ipairs(lines) do
		if #line == 0 then
			line[1] = { "", "ArfOutput" }
		end
	end
	return lines, total
end

function M.full_lines(result)
	local lines = M.lines(result)
	if result.truncated then
		lines[#lines + 1] = { { "[Output exceeding the retention limit has been omitted]", "ArfWarning" } }
	end
	return lines
end

function M.preview(result)
	local lines, total = M.lines(result, require("arf").config.output_max_lines)
	if total > #lines then
		lines[#lines + 1] = { { "… " .. (total - #lines) .. " more lines (view with :ArfOutput)", "ArfWarning" } }
	end
	if result.truncated then
		lines[#lines + 1] = { { "[Output exceeding the retention limit has been omitted]", "ArfWarning" } }
	end
	return lines
end

return M
