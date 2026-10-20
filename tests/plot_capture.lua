-- Run with: nvim --headless -u NONE -l tests/plot_capture.lua
-- Requires R. Exercise the generated R wrapper without an arf IPC session.
vim.opt.rtp:prepend(vim.fn.getcwd())
if vim.fn.executable("R") ~= 1 then
	print("R unavailable; plot capture integration skipped")
	return
end
local config = require("arf").config
local system = vim.system
vim.system = function(_, opts, callback)
	local process = system({ "R", "--vanilla", "--slave" }, { text = true, stdin = opts.stdin }):wait()
	assert(process.code == 0, process.stderr)
	callback({ code = 0, stdout = vim.json.encode({ stdout = process.stdout, stderr = process.stderr }) })
	return { kill = function() end }
end
local done = false
require("arf.executor").eval("plot(lm(mpg ~ wt, data = mtcars))", config, function(result, err)
	assert(result, err)
	assert(#result.paths == 4, "capture all four diagnostic plots")
	for index, path in ipairs(result.paths) do
		assert(vim.fn.fnamemodify(path, ":t") == string.format("plot-%09d.png", index), "capture in page order")
		assert(vim.fn.getfsize(path) > 0, "PNG exists")
	end
	result.cleanup()
	for _, path in ipairs(result.paths) do
		assert(vim.fn.filereadable(path) == 0, "cleanup removes every PNG")
	end
	done = true
end)
assert(
	vim.wait(10000, function()
		return done
	end),
	"evaluation timed out"
)
vim.system = system
print("R multi-plot capture tests passed")
