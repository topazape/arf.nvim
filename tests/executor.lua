-- Run with: nvim --headless -u NONE -l tests/executor.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local executor = require("arf.executor")
local config = vim.tbl_extend("force", require("arf").config, { pid = 42, output_max_bytes = 8 })
local original = vim.system
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
finish(0, vim.json.encode({ stdout = "abc", stderr = "def", error = "日本" }))
check(result.text == "abcdef" and result.error == "" and result.truncated, "decode and limit combined output and error")
check(result.path == dir .. "/plot-000000002.png", "select last plot in sequence")
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
start()
finish(7, "", "IPC unavailable")
check(failure == "IPC unavailable" and vim.fn.isdirectory(dir) == 0, "nonzero exit reports stderr and cleans up")
start()
finish(7)
check(failure:find("7") ~= nil, "empty stderr has exit-code fallback")
local cancel = start()
cancel()
check(killed == 15 and vim.fn.isdirectory(dir) == 0, "cancel terminates IPC client and removes captures")
finish(0, "{}")
check(result == nil and failure == nil, "late completion after cancel does not reach consumer")
start()
finish(0, '{"stdout":false,"stderr":12,"error":false}')
check(result.text == "" and result.error == nil, "ignore non-string response fields")
result.cleanup()
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
print("executor tests passed (" .. checks .. " checks)")
