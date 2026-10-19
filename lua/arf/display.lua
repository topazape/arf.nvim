require("arf.highlights")

local M = {}
local pending = false

function M.release(entry)
	if entry.image then
		pcall(entry.image.close, entry.image)
		entry.image = nil
	end
end

local function set_lines(buf, entry, lines)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	vim.api.nvim_buf_set_extmark(buf, require("arf.results").namespace, entry.last, 0, {
		id = entry.mark,
		virt_lines = lines,
	})
end

local function draw()
	local backend = require("arf.snacks")
	local available, reason
	for buf, state in pairs(require("arf.results").all()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			-- Extmarks are shared by all windows showing the buffer. Use the
			-- widest text area; narrower windows clip virtual lines at their edge.
			local width = 1
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				local info = vim.fn.getwininfo(win)[1]
				if info then
					width = math.max(width, vim.api.nvim_win_get_width(win) - info.textoff)
				end
			end
			for _, entry in ipairs(state.entries) do
				local lines = require("arf.output").preview(entry.result)
				if entry.result.path then
					if available == nil then
						local ok, value, message = pcall(backend.available)
						available, reason = ok and value, ok and message or tostring(value)
					end
					if available then
						if not entry.image then
							local ok, image = pcall(backend.new, buf, entry.last, entry.result.path, function(grid)
								entry.grid = grid
								M.refresh()
							end)
							if ok then
								entry.image = image
							else
								entry.image_error = tostring(image)
							end
						end
						if entry.image then
							entry.image.opts.pos = { entry.last + 1, 0 }
							entry.image.opts.range = { entry.last + 1, 0, entry.last + 1, 0 }
							for _, win in ipairs(vim.fn.win_findbuf(buf)) do
								if vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
									entry.image:show()
									break
								end
							end
							entry.image:update()
						end
						vim.list_extend(lines, entry.grid or {})
						if entry.image_error then
							lines[#lines + 1] = { { "[plot: " .. entry.image_error .. "]", "ArfWarning" } }
						end
					else
						lines[#lines + 1] = { { "[plot: " .. reason .. "]", "ArfWarning" } }
					end
				end
				if #lines > 0 then
					table.insert(lines, 1, { { string.rep("─", width), "ArfSeparator" } })
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
