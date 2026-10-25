local M = {}
local ns = vim.api.nvim_create_namespace("arf.results")
local buffers, generations = {}, {}
local serial = 0
M.namespace = ns

function M.generation(buf)
	return generations[buf] or 0
end

local function dispose(buf, entry)
	require("arf.display").release(entry)
	require("arf.signs").clear(buf, entry.signs)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_del_extmark(buf, ns, entry.mark)
	end
	entry.result.cleanup()
end

function M.clear(buf)
	require("arf.float").close(buf)
	generations[buf] = M.generation(buf) + 1
	local state = buffers[buf]
	if not state then
		return
	end
	for _, entry in ipairs(state.entries) do
		dispose(buf, entry)
	end
	state.entries = {}
	require("arf.display").refresh()
end

local function stale(buf, entry)
	entry.stale = true
	require("arf.signs").clear(buf, entry.signs)
	entry.signs = {}
end

-- Parse outside on_lines (textlock), once per batch of edits. Incomplete code
-- keeps its line-based anchor until the expression becomes valid again.
function M.sync_ranges(buf)
	local state = buffers[buf]
	if not state or not state.dirty then
		return
	end
	state.dirty = false
	local expressions = require("arf.expression").all(buf)
	for _, entry in ipairs(state.entries) do
		if entry.stale then
			for _, expression in ipairs(expressions or {}) do
				if expression.first - 1 == entry.first and expression.last - 1 > entry.last then
					entry.last = expression.last - 1
					stale(buf, entry)
					break
				end
			end
		end
	end
end

local function ensure(buf)
	if buffers[buf] then
		return buffers[buf]
	end
	local state = { entries = {} }
	buffers[buf] = state
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, first, old_last, new_last)
			local delta = new_last - old_last
			state.dirty = true
			local keep = {}
			for _, entry in ipairs(state.entries) do
				local intersects = first <= entry.last and old_last > entry.first
					or (first == old_last and first > entry.first and first <= entry.last)
				local deleted = new_last == first and first <= entry.first and old_last > entry.last
				if intersects and (entry.running or deleted) then
					dispose(buf, entry)
				else
					if intersects then
						entry.first = math.min(entry.first, first)
						entry.last =
							math.max(entry.first, entry.last >= old_last and entry.last + delta or new_last - 1)
						stale(buf, entry)
					elseif old_last <= entry.first then
						entry.first = entry.first + delta
						entry.last = entry.last + delta
					end
					keep[#keep + 1] = entry
				end
			end
			state.entries = keep
			require("arf.display").refresh()
		end,
		on_detach = function()
			M.clear(buf)
			buffers[buf] = nil
		end,
	})
	return state
end

function M.put(buf, first, last, result, running)
	local state = ensure(buf)
	local keep = {}
	for _, entry in ipairs(state.entries) do
		-- Overlapping runs replace previous output, avoiding ambiguous stacking.
		if first <= entry.last and last >= entry.first then
			dispose(buf, entry)
		else
			keep[#keep + 1] = entry
		end
	end
	serial = serial + 1
	local entry = {
		serial = serial,
		first = first,
		last = last,
		result = result,
		running = running,
		mark = vim.api.nvim_buf_set_extmark(buf, ns, last, 0, {}),
	}
	entry.signs = require("arf.signs").place(buf, first, last, result.error ~= nil, running)
	keep[#keep + 1] = entry
	state.entries = keep
	require("arf.display").refresh()
	return entry
end

function M.start(buf, first, last)
	return M.put(buf, first, last, { text = "", cleanup = function() end }, true)
end

function M.cancel(buf, entry)
	local state = buffers[buf]
	if not state or not entry then
		return
	end
	for index, current in ipairs(state.entries) do
		if current == entry then
			dispose(buf, entry)
			table.remove(state.entries, index)
			require("arf.display").refresh()
			return
		end
	end
end

function M.latest_plot()
	local path, latest = nil, 0
	for _, state in pairs(buffers) do
		for _, entry in ipairs(state.entries) do
			local paths = entry.result.paths or {}
			if #paths > 0 and entry.serial > latest then
				path, latest = paths[#paths], entry.serial
			end
		end
	end
	return path
end

function M.all()
	return buffers
end
return M
