require("arf.highlights")

local M = {}
local pending = false
local sources, views = {}, {}
local ns = vim.api.nvim_create_namespace("arf.results")

function M.release(entry)
	for _, plot in ipairs(views[entry] or {}) do
		plot.released = true
		if plot.image then
			pcall(require("arf.snacks").close, plot.image)
		end
	end
	views[entry] = nil
end

function M.watch(buf, entries)
	sources[buf] = entries
	M.refresh()
end

function M.forget(buf)
	sources[buf] = nil
end

local function elapsed_text(ms)
	if ms < 1000 then
		return string.format("%dms", math.floor(ms + 0.5))
	elseif ms < 60000 then
		return string.format("%.2fs", ms / 1000)
	end
	local seconds = math.floor(ms / 1000)
	return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
end

local function set_lines(buf, entry, lines)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, ns, entry.last, 0, {
		id = entry.mark,
		virt_lines = lines,
		virt_text = entry.result.elapsed_ms and {
			{ elapsed_text(entry.result.elapsed_ms), entry.stale and "ArfElapsedStale" or "ArfElapsed" },
		} or {},
		-- Let Neovim align per window and clip after EOL, without covering code.
		virt_text_pos = "eol_right_align",
	})
end

local function image_lines(backend, buf, entry)
	local lines = {}
	views[entry] = views[entry] or {}
	for index, path in ipairs(entry.result.paths) do
		local plot = views[entry][index] or {}
		views[entry][index] = plot
		if not plot.image then
			local ok, image = pcall(backend.new, buf, entry.last, path, function(grid)
				if plot.released then
					return
				end
				plot.grid = grid
				M.refresh()
			end)
			if ok then
				plot.image = image
			else
				plot.image_error = tostring(image)
			end
		end
		if plot.image then
			local ok, err = pcall(backend.update, plot.image, buf, entry.last)
			plot.image_error = not ok and tostring(err) or nil
		end
		vim.list_extend(lines, plot.grid or {})
		if plot.image_error then
			lines[#lines + 1] = { { "[plot: " .. plot.image_error .. "]", "ArfWarning" } }
		end
	end
	return lines
end

local function text_width(buf)
	local width = 1
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local info = vim.fn.getwininfo(win)[1]
		if info then
			width = math.max(width, vim.api.nvim_win_get_width(win) - info.textoff)
		end
	end
	return width
end

local function draw_entry(buf, entry, width, images)
	local output = require("arf.output")
	local lines = output.preview(entry.result, require("arf.config").get().inline.max_lines)
	if entry.stale then
		output.stale(lines)
	end
	if entry.result.paths and #entry.result.paths > 0 then
		vim.list_extend(lines, images(buf, entry))
	end
	if #lines > 0 then
		table.insert(lines, 1, { { string.rep("─", width), "ArfSeparator" } })
		lines[#lines + 1] = { { "", "ArfOutput" } }
	end
	set_lines(buf, entry, lines)
end

local function draw()
	local backend = require("arf.snacks")
	local available, reason
	local function images(buf, entry)
		if available == nil then
			local ok, value, message = pcall(backend.available)
			available, reason = ok and value, ok and message or tostring(value)
		end
		if not available then
			return { { { "[plot: " .. reason .. "]", "ArfWarning" } } }
		end
		return image_lines(backend, buf, entry)
	end
	for buf, read_entries in pairs(sources) do
		if vim.api.nvim_buf_is_loaded(buf) then
			-- Shared virtual lines use the widest text area; narrower windows clip them.
			local width = text_width(buf)
			for _, entry in ipairs(read_entries()) do
				draw_entry(buf, entry, width, images)
			end
		end
	end
end

function M.refresh()
	if pending then
		return
	end
	pending = true
	vim.schedule(function()
		pending = false
		draw()
	end)
end

local group = vim.api.nvim_create_augroup("arf.display", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinResized", "VimResized", "TabEnter" }, {
	group = group,
	callback = M.refresh,
})
vim.api.nvim_create_autocmd("OptionSet", {
	group = group,
	pattern = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn" },
	callback = M.refresh,
})
return M
