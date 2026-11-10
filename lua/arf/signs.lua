local M = {}
local ns = vim.api.nvim_create_namespace("arf.signs")
M.namespace = ns

local function stop_animation(ids)
	local timer = ids and ids.timer
	if not timer then
		return
	end
	ids.timer = nil -- Scheduled callbacks must not recreate a cleared sign.
	if not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

local function animate(buf, id, ids, config)
	local running = config.running
	if #running.frames < 2 then
		return
	end
	local timer = assert(vim.uv.new_timer())
	ids.timer = timer
	local frame = 0
	timer:start(
		running.interval_ms,
		running.interval_ms,
		vim.schedule_wrap(function()
			if ids.timer ~= timer then
				return
			end
			if not vim.api.nvim_buf_is_loaded(buf) then
				return stop_animation(ids)
			end
			local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
			if #pos == 0 then
				return stop_animation(ids)
			end
			frame = frame % #running.frames + 1
			vim.api.nvim_buf_set_extmark(buf, ns, pos[1], pos[2], {
				id = id,
				sign_text = running.frames[frame],
				sign_hl_group = running.hl,
				priority = config.priority,
				undo_restore = false,
			})
		end)
	)
end

function M.place(buf, first, last, state)
	require("arf.highlights")
	local config = require("arf.config").get().signs
	local ids = {}
	if not config.enabled then
		return ids
	end
	local final_id
	local status = config[state == "ok" and "success" or state == "unknown" and "error" or state]
	local ok, err = pcall(function()
		for row = first, last do
			local text = row == last and status.text or config.range.text
			local hl = status.hl
			if text ~= "" then
				ids[#ids + 1] = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
					sign_text = text,
					sign_hl_group = hl,
					priority = config.priority,
					undo_restore = false,
				})
				if row == last then
					final_id = ids[#ids]
				end
			end
		end
		if state == "running" and final_id then
			animate(buf, final_id, ids, config)
		end
	end)
	if not ok then
		M.clear(buf, ids)
		error(err)
	end
	return ids
end

function M.clear(buf, ids)
	stop_animation(ids)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, id in ipairs(ids or {}) do
		vim.api.nvim_buf_del_extmark(buf, ns, id)
	end
end

return M
