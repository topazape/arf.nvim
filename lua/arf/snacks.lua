-- Keep Snacks-specific placement details out of result and text management.
local M = {}

function M.available()
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		return false, "snacks.nvim is required"
	end
	local env = snacks.image.terminal.env()
	if not env.supported or not env.placeholders then
		return false, "A terminal that supports Snacks inline images is required"
	end
	return true
end

function M.new(buf, row, path, on_grid)
	local config = require("arf").config
	return require("snacks").image.placement.new(buf, path, {
		pos = { row + 1, 0 },
		range = { row + 1, 0, row + 1, 0 },
		inline = true,
		conceal = false,
		auto_resize = true,
		max_width = config.image_width,
		max_height = config.image_height,
		on_update = function(placement)
			-- Snacks builds the Kitty placeholder grid. Move that grid into our
			-- single output extmark so text and image have an unambiguous order.
			-- eids/ns are internal to Snacks; covered by the real-placement test.
			local lines, inline = {}, nil
			for _, id in ipairs(placement.eids) do
				local mark = vim.api.nvim_buf_get_extmark_by_id(buf, placement.ns, id, { details = true })
				local details = mark[3] or {}
				vim.list_extend(lines, details.virt_lines or {})
				inline = details.virt_text or inline
				vim.api.nvim_buf_del_extmark(buf, placement.ns, id)
			end
			placement.eids = {}
			-- Snacks uses virt_text instead of virt_lines for a one-row image.
			if #lines == 0 and inline then
				lines = { inline }
			end
			on_grid(lines)
		end,
	})
end

return M
