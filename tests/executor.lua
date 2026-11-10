-- Run with: nvim --headless -u NONE -l tests/executor.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local executor = require("arf.executor")
local config = vim.tbl_deep_extend(
	"force",
	require("arf").config,
	{ pid = 42, output = { max_bytes = 8, tibble = { width = "inherit" } } }
)
local original = vim.system
local original_hrtime = vim.uv.hrtime
local now = 1000000000
vim.uv.hrtime = function()
	return now
end
local original_limit = require("arf.output").limit
require("arf.output").limit = function(...)
	local value = original_limit(...)
	now = now + 7000000 -- Include result processing in the measured interval.
	return value
end
local pending, args, options, dir, killed, result, failure
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
vim.system = function(argv, opts, callback)
	args, options, pending = argv, opts, callback
	dir = vim.json.decode(assert(opts.stdin:match('%.arf_stdout_path <%- ("[^"]+")'))):gsub("/stdout.bin$", "")
	return {
		kill = function(_, signal)
			killed = signal
		end,
	}
end
local function start()
	result, failure, killed = nil, nil, nil
	return executor.eval('cat("日本"); # $HOME `literal`', config, function(value, err)
		result, failure = value, err
	end)
end
local function finish(code, stdout, stderr)
	pending({ code = code, stdout = stdout or "", stderr = stderr or "" })
	vim.wait(10, function()
		return false
	end)
end
start()
assert(not failure, failure)
check(options.stdin:find(".arf_tibble_rows <- NULL", 1, true), "inherit rows preserves R options")
check(options.stdin:find(".arf_tibble_width <- NULL", 1, true), "inherit width preserves R options")
check(
	vim.deep_equal(args, { "arf", "ipc", "eval", "--visible", "--timeout", "300000", "--pid", "42" }),
	"IPC argument vector includes timeout and PID"
)
check(
	options.stdin:find(vim.json.encode('cat("日本"); # $HOME `literal`'), 1, true),
	"source is quoted data on stdin"
)
vim.fn.writefile({}, dir .. "/plot-000000002.png")
vim.fn.writefile({}, dir .. "/plot-000000001.png")
vim.fn.writefile({}, dir .. "/truncated")
now = now + 135000000
finish(0, vim.json.encode({ stdout = "abc", stderr = "def", status = "error", error = "日本" }))
check(result.elapsed_ms == 142, "R errors retain elapsed time including result processing")
check(result.text == "abcdef" and result.error == "" and result.truncated, "decode and limit combined output and error")
check(
	vim.deep_equal(result.paths, { dir .. "/plot-000000001.png", dir .. "/plot-000000002.png" }),
	"retain plots in sequence"
)
check(vim.fn.isdirectory(dir) == 1, "retain resources until consumer releases them")
result.cleanup()
result.cleanup()
check(vim.fn.isdirectory(dir) == 0, "cleanup removes capture directory idempotently")
for _, response in ipairs({ "not json", "null", "42", '"string"' }) do
	start()
	finish(0, response)
	check(
		result == nil and failure:find("JSON") and vim.fn.isdirectory(dir) == 0,
		"invalid response releases resources: " .. response
	)
end
for _, response in ipairs({ "{}", '{"error":"old server"}', '{"status":"invalid"}', '{"status":null}' }) do
	start()
	finish(0, response)
	check(result == nil and failure:find("status") and vim.fn.isdirectory(dir) == 0, "reject missing/invalid status")
end
local old_limit = require("arf.output").limit
require("arf.output").limit = function()
	error("decode failure")
end
start()
finish(0, '{"status":"ok"}')
check(
	result == nil and failure:find("decode failure") and vim.fn.isdirectory(dir) == 0,
	"decode exception releases captures"
)
require("arf.output").limit = old_limit
local finished_cancel = start()
finish(0, '{"status":"ok"}')
finished_cancel()
check(killed == nil and vim.fn.isdirectory(dir) == 1, "completed cancellation handle cannot destroy delivered results")
result.cleanup()
start()
finish(7, "", "IPC unavailable")
check(failure == "IPC unavailable" and vim.fn.isdirectory(dir) == 0, "nonzero exit reports stderr and cleans up")
start()
finish(7)
check(failure:find("7") ~= nil, "empty stderr has exit-code fallback")
local cancel = start()
cancel()
check(killed == 15 and vim.fn.isdirectory(dir) == 0, "cancel terminates IPC client and removes captures")
finish(0, '{"status":"ok"}')
check(result == nil and failure == nil, "late completion after cancel does not reach consumer")
start()
finish(0, '{"status":"ok","stdout":false,"stderr":12,"error":false}')
check(result.elapsed_ms == 7, "independent evaluation starts a fresh clock, including empty output")
check(result.text == "" and result.error == nil, "ignore non-string response fields")
result.cleanup()
for _, status in ipairs({ "ok", "error", "interrupted", "unknown" }) do
	start()
	finish(0, vim.json.encode({ status = status, stdout = "partial", stderr = "", error = vim.NIL }))
	check(result.status == status, "preserve status: " .. status)
	check((result.error == nil) == (status == "ok"), "only ok succeeds: " .. status)
	result.cleanup()
end
local interrupt_args, interrupt_reply
vim.system = function(argv, _, callback)
	interrupt_args = argv
	callback({ code = 0, stdout = '{"accepted":true,"execution_id":7}', stderr = "" })
end
executor.interrupt(config, function(accepted, err)
	interrupt_reply = accepted
	check(err == nil, "interrupt accepted without error")
end)
vim.wait(20, function()
	return interrupt_reply ~= nil
end)
check(interrupt_reply == true, "decode accepted interrupt")
check(
	vim.deep_equal(interrupt_args, { "arf", "ipc", "interrupt", "--pid", "42" }),
	"interrupt targets explicit session"
)
vim.system = function(_, opts)
	dir = vim.json.decode(assert(opts.stdin:match('%.arf_stdout_path <%- ("[^"]+")'))):gsub("/stdout.bin$", "")
	error("cannot spawn")
end
executor.eval("1", config, function(value, err)
	result, failure = value, err
end)
check(
	result == nil and failure:find("cannot spawn") and vim.fn.isdirectory(dir) == 0,
	"spawn exception releases captures"
)
vim.system = original
vim.uv.hrtime = original_hrtime
require("arf.output").limit = original_limit
print("executor tests passed (" .. checks .. " checks)")
