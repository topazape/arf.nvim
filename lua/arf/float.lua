local M = {}
local window, owner
local ns = vim.api.nvim_create_namespace("arf.float")
local float_highlights = {
	ArfOutput = "ArfFloatOutput",
	ArfOutputStale = "ArfFloatOutputStale",
	ArfMessage = "ArfFloatMessage",
	ArfStderr = "ArfFloatStderr",
	ArfError = "ArfFloatError",
	ArfWarning = "ArfFloatWarning",
}

function M.close(buf)
	if buf and owner ~= buf then
		return
	end
	if window and vim.api.nvim_win_is_valid(window) then
		vim.api.nvim_win_close(window, true)
	end
	window, owner = nil, nil
end

function M.open(title, lines, opts)
	require("arf.highlights")
	M.close()
	if #lines == 0 then
		lines = { { { "(no output)", "ArfFloatEmpty" } } }
	end
	local text = {}
	for _, line in ipairs(lines) do
		local parts = {}
		for _, chunk in ipairs(line) do
			parts[#parts + 1] = chunk[1]
		end
		text[#text + 1] = table.concat(parts)
	end
	local width = math.max(1, math.min(opts.width, vim.o.columns - 4))
	local height = math.max(1, math.min(#text, opts.max_height, vim.o.lines - 4))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
	for row, line in ipairs(lines) do
		local col = 0
		for _, chunk in ipairs(line) do
			if #chunk[1] > 0 and chunk[2] then
				local hl = float_highlights[chunk[2]] or chunk[2]
				vim.api.nvim_buf_set_extmark(buf, ns, row - 1, col, { end_col = col + #chunk[1], hl_group = hl })
			end
			col = col + #chunk[1]
		end
	end
	vim.bo[buf].modifiable = false
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
		title = " " .. title .. " ",
		title_pos = "center",
	})
	window, owner = win, opts.owner
	vim.wo[win].wrap = false
	vim.wo[win].winhighlight =
		"Normal:ArfFloatNormal,NormalFloat:ArfFloatNormal,FloatBorder:ArfFloatBorder,FloatTitle:ArfFloatTitle"
	vim.keymap.set("n", "q", function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, silent = true, nowait = true, desc = "Close arf output" })
	return win
end

return M
