-- Real arf headless + IPC, R, buffers, result storage and PNG capture.
vim.opt.rtp:prepend(vim.fn.getcwd())
if vim.fn.executable("arf") ~= 1 or vim.fn.executable("R") ~= 1 then
	print("arf or R unavailable; real session integration skipped")
	return
end
local arf = require("arf")
local results = require("arf.results")
local session = require("arf.session")
arf.setup({ startup_timeout = 20000, eval_timeout = 20000 })
local buf = vim.api.nvim_get_current_buf()
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end
local function run(code)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
	arf.run(1, vim.api.nvim_buf_line_count(buf))
	assert(
		vim.wait(25000, function()
			local state = results.all()[buf]
			return state and state.entries[1] and not state.entries[1].running
		end, 10),
		"evaluation timed out: " .. code .. "\n" .. table.concat(notices, "\n")
	)
	return results.all()[buf].entries[1].result
end
local ok, err = xpcall(function()
	local value = run("arf_test_value <- 41L")
	assert(not value.error)
	local pid
	session.ensure(arf.config, function(value)
		pid = value
	end)
	assert(type(pid) == "number", "auto-start provides an owned PID")
	value = run("arf_test_value + 1L")
	assert(value.text:find("42", 1, true) and not value.error, "objects persist between IPC evaluations")
	value =
		run('options(warn = 1); cat("日本語\\n"); message("notice"); warning("careful"); stop("expected failure")')
	assert(value.text:find("日本語", 1, true), "capture stdout before error")
	assert(value.text:find("notice", 1, true) and value.text:find("careful", 1, true), "capture messages and warnings")
	assert(value.error and value.error:find("expected failure", 1, true), "preserve R error")
	value = run("arf_test_value + 2L")
	assert(not value.error and value.text:find("43", 1, true), "evaluation recovers after R error")
	value = run("plot(lm(mpg ~ wt, data = mtcars))")
	assert(not value.error and #value.paths == 4, "capture four plots through real IPC")
	local paths = vim.deepcopy(value.paths)
	for _, path in ipairs(paths) do
		assert(vim.fn.getfsize(path) > 0, "PNG exists")
	end
	arf.clear(buf)
	for _, path in ipairs(paths) do
		assert(vim.fn.filereadable(path) == 0, "clear removes PNG")
	end
	arf.stop()
	assert(vim.uv.kill(pid, 0) == nil, "stop terminates owned process")
	assert(next(results.all()) == nil or #results.all()[buf].entries == 0, "stop clears results")
	value = run('exists("arf_test_value", envir = .GlobalEnv, inherits = FALSE)')
	assert(not value.error and value.text:find("FALSE", 1, true), "restart uses a fresh R session")
end, debug.traceback)
-- Always terminate our owned child, including when an assertion fails.
arf.stop()
assert(ok, err)
print("real arf session integration tests passed")
