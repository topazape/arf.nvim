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
		running.interval,
		running.interval,
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

function M.validate(config)
	assert(type(config) == "table", "arf: signs must be a table")
	assert(type(config.enabled) == "boolean", "arf: signs.enabled must be a boolean")
	assert(
		type(config.priority) == "number"
			and config.priority >= 0
			and config.priority < math.huge
			and config.priority == math.floor(config.priority),
		"arf: signs.priority must be a non-negative integer"
	)
	for _, key in ipairs({ "range", "success", "error", "running" }) do
		local sign = config[key]
		assert(type(sign) == "table", "arf: signs." .. key .. " must be a table")
		assert(
			type(sign.text) == "string"
				and not sign.text:find("[%c]")
				and (
					sign.text == ""
					or vim.fn.strdisplaywidth(sign.text) >= 1 and vim.fn.strdisplaywidth(sign.text) <= 2
				),
			"arf: signs." .. key .. ".text must be empty or 1-2 display cells without control characters"
		)
		assert(
			type(sign.hl) == "string" and sign.hl ~= "",
			"arf: signs." .. key .. ".hl must be a highlight group name"
		)
	end
	assert(
		type(config.running.frames) == "table" and vim.islist(config.running.frames),
		"arf: signs.running.frames must be a list"
	)
	for _, text in ipairs(config.running.frames) do
		assert(
			type(text) == "string"
				and not text:find("[%c]")
				and vim.fn.strdisplaywidth(text) >= 1
				and vim.fn.strdisplaywidth(text) <= 2,
			"arf: signs.running.frames must contain symbols of 1-2 display cells"
		)
	end
	local interval = config.running.interval
	assert(
		type(interval) == "number" and interval > 0 and interval < math.huge and interval == math.floor(interval),
		"arf: signs.running.interval must be a positive integer in milliseconds"
	)
end

function M.place(buf, first, last, failed, running)
	require("arf.highlights")
	local config = require("arf").config.signs
	local ids = {}
	if not config.enabled then
		return ids
	end
	local final_id
	local status = running and config.running or failed and config.error or config.success
	for row = first, last do
		local text = row == last and status.text or config.range.text
		local hl = (running or row == last) and status.hl or config.range.hl
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
	if running and final_id then
		animate(buf, final_id, ids, config)
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
