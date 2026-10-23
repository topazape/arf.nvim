-- Run with: nvim --headless -u NONE -l tests/results.lua
-- Use real buffer edits, extmarks, signs and timers; mock only image drawing/floats.
vim.opt.rtp:prepend(vim.fn.getcwd())
package.loaded["arf.display"] = {
	refresh = function() end,
	release = function(entry)
		if entry.image then
			entry.image:close()
			entry.image = nil
		end
	end,
}
local closed = {}
package.loaded["arf.float"] = {
	close = function(buf)
		closed[buf] = true
	end,
}
local results = require("arf.results")
local signs = require("arf.signs")
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d", "e", "f" })
	return buf
end
local function put(buf, first, last)
	local resources = { cleaned = 0, images_closed = 0 }
	local entry = results.put(buf, first, last, {
		text = "result",
		cleanup = function()
			resources.cleaned = resources.cleaned + 1
		end,
	})
	entry.image = {
		close = function()
			resources.images_closed = resources.images_closed + 1
		end,
	}
	return entry, resources
end
local function disposed(buf, entry, resources)
	check(resources.cleaned == 1 and resources.images_closed == 1, "release each resource exactly once")
	if vim.api.nvim_buf_is_valid(buf) then
		check(#vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, {}) == 0, "remove output mark")
		for _, id in ipairs(entry.signs) do
			check(#vim.api.nvim_buf_get_extmark_by_id(buf, signs.namespace, id, {}) == 0, "remove execution sign")
		end
	end
end

-- Insertions at the start move the range; edits inside retain stale output.
for _, row in ipairs({ 0, 2, 3, 4 }) do
	local buf = buffer()
	local entry, resources = put(buf, 2, 3)
	vim.api.nvim_buf_set_lines(buf, row, row, false, { "inserted" })
	if row == 3 then
		check(#results.all()[buf].entries == 1 and entry.stale, "insertion inside retains stale result")
		check(entry.first == 2 and entry.last == 4, "insertion extends range")
		check(resources.cleaned == 0 and #entry.signs == 0, "retain resources and clear execution signs")
		check(#vim.api.nvim_buf_get_extmarks(buf, signs.namespace, 0, -1, {}) == 0, "remove success and range signs")
	else
		local shift = row <= 2 and 1 or 0
		check(entry.first == 2 + shift and entry.last == 3 + shift, "insertion boundary moves range correctly")
		check(resources.cleaned == 0, "keep unaffected result")
		check(
			vim.api.nvim_buf_get_extmark_by_id(buf, results.namespace, entry.mark, {})[1] == entry.last,
			"mark follows range"
		)
	end
	vim.api.nvim_buf_delete(buf, { force = true })
	check(resources.cleaned == 1, "buffer deletion releases remaining result")
end
for _, row in ipairs({ 1, 2, 3, 4 }) do
	local buf = buffer()
	local entry, resources = put(buf, 2, 3)
	vim.api.nvim_buf_set_lines(buf, row, row + 1, false, {})
	if row == 2 or row == 3 then
		check(entry.stale and entry.first == 2 and entry.last == 2, "partial deletion retains stale result")
		check(resources.cleaned == 0, "partial deletion keeps resources")
	else
		check(entry.first == (row == 1 and 1 or 2), "deletion before moves range; deletion after keeps it")
		check(resources.cleaned == 0, "deletion outside keeps result")
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end
-- Repeated edits retain resources; rerunning replaces stale output.
do
	local buf = buffer()
	local entry, resources = put(buf, 1, 2)
	vim.api.nvim_buf_set_lines(buf, 1, 3, false, { "replacement" })
	check(entry.stale and entry.first == 1 and entry.last == 1, "replacement keeps an anchor")
	vim.api.nvim_buf_set_text(buf, 1, 0, 1, 1, { "changed" })
	check(resources.cleaned == 0, "repeated edit preserves result")
	local fresh = put(buf, 1, 1)
	disposed(buf, entry, resources)
	check(not fresh.stale, "rerun resets stale status")
	vim.api.nvim_buf_delete(buf, { force = true })
end
-- Deleting the entire source removes its result, including at EOF.
do
	local buf = buffer()
	local entry, resources = put(buf, 4, 5)
	vim.api.nvim_buf_set_lines(buf, 4, 6, false, {})
	disposed(buf, entry, resources)
	check(#results.all()[buf].entries == 0, "full deletion removes result")
	vim.api.nvim_buf_delete(buf, { force = true })
end
-- Failed results also lose their execution signs after edits.
do
	local buf = buffer()
	local entry = results.put(buf, 1, 2, { text = "", error = "failure", cleanup = function() end })
	vim.api.nvim_buf_set_lines(buf, 1, 3, false, { "changed" })
	local marks = vim.api.nvim_buf_get_extmarks(buf, signs.namespace, 0, -1, { details = true })
	check(entry.stale and #marks == 0 and #entry.signs == 0, "replacement removes error and range signs")
	vim.api.nvim_buf_delete(buf, { force = true })
end
-- Running output is still discarded on source edits.
do
	local buf = buffer()
	local entry = results.start(buf, 1, 2)
	local timer = entry.signs.timer
	vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "edited" })
	check(#results.all()[buf].entries == 0 and timer:is_closing(), "edit cancels running entry and timer")
	vim.api.nvim_buf_delete(buf, { force = true })
end
local buf = buffer()
local old, old_resources = put(buf, 1, 2)
local adjacent, adjacent_resources = put(buf, 3, 3)
local replacement, replacement_resources = put(buf, 0, 2)
disposed(buf, old, old_resources)
check(
	#results.all()[buf].entries == 2 and adjacent_resources.cleaned == 0,
	"replace overlap while retaining adjacent result"
)
results.cancel(buf, old)
check(#results.all()[buf].entries == 2, "stale cancellation does not remove replacement")
results.cancel(buf, replacement)
results.cancel(buf, replacement)
disposed(buf, replacement, replacement_resources)
local generation = results.generation(buf)
results.clear(buf)
check(results.generation(buf) == generation + 1 and closed[buf], "clear invalidates requests and closes owned float")
disposed(buf, adjacent, adjacent_resources)
results.clear(buf)
check(adjacent_resources.cleaned == 1, "repeated clear does not release twice")
local running = results.start(buf, 1, 2)
local timer = running.signs.timer
check(timer ~= nil, "running sign starts animation")
results.clear(buf)
check(running.signs.timer == nil and timer:is_closing(), "clear closes animation timer")
vim.wait(100, function()
	return false
end)
check(
	#vim.api.nvim_buf_get_extmarks(buf, signs.namespace, 0, -1, {}) == 0,
	"queued animation cannot recreate cleared signs"
)
vim.api.nvim_buf_delete(buf, { force = true })
check(results.all()[buf] == nil, "detach removes buffer state")
if vim.env.ARF_TEST_MODE ~= "unit" then
	local buf = buffer()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "df |> head()" })
	local expressions, err = require("arf.expression").all(buf)
	if expressions then
		local entry, resources = put(buf, 0, 0)
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "df |> head() |>" })
		results.sync_ranges(buf)
		check(entry.stale and entry.last == 0 and resources.cleaned == 0, "incomplete pipe retains result")
		vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "  transform(", "    total = 1", "  )" })
		results.sync_ranges(buf)
		check(entry.last == 3 and resources.cleaned == 0, "real R parser follows completed pipeline")
		vim.api.nvim_buf_set_lines(buf, 4, 4, false, { "print(df)" })
		results.sync_ranges(buf)
		check(entry.last == 3, "separate expression does not extend range")
		vim.api.nvim_buf_set_lines(buf, 0, 4, false, {})
		disposed(buf, entry, resources)
	else
		assert(err:find("parser"), err)
		print("R parser unavailable; range integration skipped")
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end
print("results tests passed (" .. checks .. " checks)")
