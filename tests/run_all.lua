-- Run with: nvim --headless -u NONE -l tests/run_all.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local expressions = {
	{ first = 1, last = 1, code = "x <- 1" },
	{ first = 2, last = 2, code = "print(x)" },
}
package.loaded["arf.expression"] = {
	all = function()
		return expressions
	end,
}
local callbacks, codes, entries, notices = {}, {}, {}, {}
local generation, cleaned = 0, 0
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
package.loaded["arf.results"] = {
	generation = function()
		return generation
	end,
	start = function(_, first)
		return first
	end,
	cancel = function() end,
	put = function(_, first, _, result)
		entries[#entries + 1] = { first, result }
	end,
	clear = function()
		generation = generation + 1
	end,
	all = function()
		return {}
	end,
}
vim.notify = function(message)
	notices[#notices + 1] = message
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x <- 1", "print(x)" })
local function complete(err)
	local cb = table.remove(callbacks, 1)
	assert(cb)
	cb({
		text = "",
		error = err,
		cleanup = function()
			cleaned = cleaned + 1
		end,
	})
	vim.wait(20, function()
		return false
	end)
end
local function reset()
	codes, callbacks, entries, notices = {}, {}, {}, {}
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x <- 1", "print(x)" })
end
arf.run_all()
assert(#codes == 1)
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "x <- 1", "", "print(x)", "" }),
	"real blank lines after each expression"
)
local busy_tick = vim.api.nvim_buf_get_changedtick(0)
arf.run_all()
assert(vim.api.nvim_buf_get_changedtick(0) == busy_tick, "busy request does not edit buffer")
assert(#codes == 1 and #notices == 1, "busy guard")
complete()
assert(#codes == 2 and entries[1][1] == 0)
complete()
assert(#entries == 2 and entries[2][1] == 2)
reset()
arf.run_all()
complete("failure")
assert(#codes == 1 and #entries == 1, "stop on R error")
reset()
arf.run_all()
vim.api.nvim_buf_set_lines(0, 1, 2, false, { "print(2)" })
complete()
assert(#codes == 1 and #entries == 0 and cleaned == 1, "stop after edit")
reset()
arf.run_all()
arf.clear()
complete()
assert(#codes == 1 and #entries == 0, "stop after clear")
reset()
arf.run_all()
arf.stop()
complete()
assert(#codes == 1 and #entries == 0, "stop invalidates callback")
reset()
arf.run_all()
complete()
complete()
assert(#entries == 2, "can run again after stop")
reset()
arf.run(1)
complete()
local spaced = vim.api.nvim_buf_get_lines(0, 0, -1, false)
arf.run(1)
complete()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), spaced), "rerun reuses existing blank line")
arf.run(3)
complete()
assert(vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] == "", "append real blank at EOF")
package.loaded["arf.expression"] = nil
local expression = require("arf.expression")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# comment", "x <- 1", "print(x)" })
local all, err = expression.all(0)
if all then
	assert(#all == 2 and all[1].first == 2 and all[2].first == 3)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x <- (" })
	assert(expression.all(0) == nil, "reject syntax error")
else
	assert(err:find("parser"), err)
	print("R parser unavailable; parser integration skipped")
end
print("run-all tests passed")
