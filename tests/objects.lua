vim.opt.rtp:prepend(vim.fn.getcwd())
local objects = require("arf.objects")
local arf = require("arf")
-- Borrowed sessions retain the evaluation path without publishing handlers.
arf.setup({ pid = 123 })
local callbacks, codes, notices, floats = {}, {}, {}, {}
local cleaned = 0
vim.notify = function(message)
	notices[#notices + 1] = message
end
package.loaded["arf.session"] = {
	ensure = function(_, cb)
		cb(123)
	end,
	stop = function() end,
}
package.loaded["arf.executor"] = {
	eval = function(code, _, cb)
		codes[#codes + 1] = code
		callbacks[#callbacks + 1] = cb
		return function() end
	end,
}
package.loaded["arf.float"] = {
	open = function(title, lines)
		floats[#floats + 1] = { title = title, lines = lines }
	end,
	close = function() end,
}
local selections = {}
vim.ui.select = function(items, opts, callback)
	selections[#selections + 1] = { items = items, opts = opts, callback = callback }
end
local function hex(s)
	return (s:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end
local name = 'a b"); stop("bad") #\n日本語'
local function row(n, cls, size)
	return hex(n) .. "\t" .. hex(cls or "") .. "\t" .. hex(size or "") .. "\n"
end
local function complete(text, err, truncated)
	local cb = table.remove(callbacks, 1)
	assert(cb)
	cb({
		text = text or "",
		error = err,
		truncated = truncated,
		cleanup = function()
			cleaned = cleaned + 1
		end,
	})
end
local items = objects.decode(row(name, "tbl_df", "12,450 × 8"))
assert(items[1].name == name and items[1].text == name)
assert(items[1].class == "tbl_df" and items[1].size == "12,450 × 8")
assert(#objects.decode("") == 0)
assert(not pcall(objects.decode, "invalid"))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "model" })
arf.objects()
assert(codes[1] == objects.code)
arf.inspect("summary")
assert(notices[#notices]:find("R is running", 1, true))
complete(row(name, "numeric", "1,000"))
assert(vim.wait(1000, function()
	return #selections > 0
end))
assert(selections[1].opts.prompt == "R object:" and cleaned == 1)
assert(selections[1].items[1].name == name)
assert(selections[1].opts.format_item(selections[1].items[1]):find("numeric", 1, true))
for _, action in ipairs({ "summary", "print" }) do
	selections[1].callback(items[1])
	local choice = selections[#selections]
	assert(vim.deep_equal(choice.items, { "summary", "print" }))
	local previous_floats = #floats
	choice.callback(action)
	assert(codes[#codes]:find(vim.json.encode(name), 1, true))
	assert(codes[#codes]:find("inherits = FALSE", 1, true))
	assert(codes[#codes]:find('base::getExportedValue("base", "' .. action .. '")', 1, true))
	complete("result", action == "print" and "object no longer exists" or nil)
	assert(#floats == previous_floats + 1)
end
assert(vim.inspect(floats[#floats].lines):find("object no longer exists", 1, true))
local before = #codes
selections[1].callback(nil)
selections[1].callback(items[1])
selections[#selections].callback(nil)
assert(#codes == before, "cancellation does not evaluate")
local other = vim.api.nvim_create_buf(true, false)
selections[1].callback(items[1])
local pending = selections[#selections]
vim.api.nvim_win_set_buf(0, other)
pending.callback("print")
assert(#codes == before, "changed buffer invalidates selection")
vim.api.nvim_win_set_buf(0, 1)
arf.objects()
local cb = table.remove(callbacks, 1)
cb(nil, "IPC failure")
assert(notices[#notices]:find("IPC failure", 1, true))
for _, case in ipairs({
	{ "", "metadata failed", false, "metadata failed" },
	{ "bad", nil, false, "Unable to read object list" },
	{ "", nil, true, "output.max_bytes" },
}) do
	arf.objects()
	complete(case[1], case[2], case[3])
	assert(notices[#notices]:find(case[4], 1, true))
end
arf.objects()
local previous = #selections
complete("")
assert(vim.wait(1000, function()
	return #selections > previous
end))
assert(#selections[#selections].items == 0)

-- Synchronous implementations, including Neovim's default, must be able to
-- start inspection after the metadata request releases the execution guard.
vim.ui.select = function(choices, _, callback)
	callback(choices[1])
end
arf.objects()
complete(row("sync", "numeric", "1"))
assert(
	vim.wait(1000, function()
		return #callbacks > 0
	end),
	"synchronous selection starts inspection"
)
assert(codes[#codes]:find('"summary"', 1, true))
complete("result")

-- Stopping after the first or second prompt invalidates the pending selection.
vim.ui.select = function(choices, opts, callback)
	selections[#selections + 1] = { items = choices, opts = opts, callback = callback }
end
-- Use an owned session so stop succeeds.
arf.setup({ pid = false })
local original_fetch = objects.fetch
objects.fetch = function(_, callback)
	callback(items)
end
for _, stage in ipairs({ 1, 2 }) do
	local count = #selections
	arf.objects()
	assert(vim.wait(1000, function()
		return #selections > count
	end))
	local pending_selection = selections[#selections]
	if stage == 2 then
		pending_selection.callback(items[1])
		pending_selection = selections[#selections]
	end
	arf.stop()
	local old_codes, old_selections = #codes, #selections
	pending_selection.callback(stage == 1 and items[1] or "print")
	assert(#codes == old_codes and #selections == old_selections, "stop invalidates selection")
end
objects.fetch = original_fetch
print("object selection unit tests passed")
