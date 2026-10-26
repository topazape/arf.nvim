require("arf.highlights")

local M = {}
local pending = false

function M.release(entry)
	for _, plot in ipairs(entry.plots or {}) do
		if plot.image then
			pcall(plot.image.close, plot.image)
		end
	end
	entry.plots = nil
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
	vim.api.nvim_buf_set_extmark(buf, require("arf.results").namespace, entry.last, 0, {
		id = entry.mark,
		virt_lines = lines,
		virt_text = entry.result.elapsed_ms and {
			{ elapsed_text(entry.result.elapsed_ms), entry.stale and "ArfElapsedStale" or "ArfElapsed" },
		} or {},
		-- Let Neovim align per window and clip after EOL, without covering code.
		virt_text_pos = "eol_right_align",
	})
end

local function draw()
	local backend = require("arf.snacks")
	local available, reason
	for buf, state in pairs(require("arf.results").all()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			require("arf.results").sync_ranges(buf)
			-- Shared virtual lines use the widest text area; narrower windows clip them.
			local width = 1
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				local info = vim.fn.getwininfo(win)[1]
				if info then
					width = math.max(width, vim.api.nvim_win_get_width(win) - info.textoff)
				end
			end
			for _, entry in ipairs(state.entries) do
				local lines = require("arf.output").preview(entry.result)
				if entry.stale then
					require("arf.output").stale(lines)
				end
				if entry.result.paths and #entry.result.paths > 0 then
					if available == nil then
						local ok, value, message = pcall(backend.available)
						available, reason = ok and value, ok and message or tostring(value)
					end
					if available then
						entry.plots = entry.plots or {}
						for index, path in ipairs(entry.result.paths) do
							local plot = entry.plots[index] or {}
							entry.plots[index] = plot
							if not plot.image then
								local ok, image = pcall(backend.new, buf, entry.last, path, function(grid)
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
								plot.image.opts.pos = { entry.last + 1, 0 }
								plot.image.opts.range = { entry.last + 1, 0, entry.last + 1, 0 }
								for _, win in ipairs(vim.fn.win_findbuf(buf)) do
									if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
										plot.image:show()
										break
									end
								end
								plot.image:update()
							end
							vim.list_extend(lines, plot.grid or {})
							if plot.image_error then
								lines[#lines + 1] = { { "[plot: " .. plot.image_error .. "]", "ArfWarning" } }
							end
						end
					else
						lines[#lines + 1] = { { "[plot: " .. reason .. "]", "ArfWarning" } }
					end
				end
				if #lines > 0 then
					table.insert(lines, 1, { { string.rep("─", width), "ArfSeparator" } })
					lines[#lines + 1] = { { "", "ArfOutput" } }
				end
				set_lines(buf, entry, lines)
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
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		for buf in pairs(require("arf.results").all()) do
			require("arf.results").clear(buf)
		end
	end,
})
return M
