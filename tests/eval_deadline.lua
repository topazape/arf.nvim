vim.opt.rtp:prepend(vim.fn.getcwd())
local executor = require("arf.executor")
local config = vim.deepcopy(require("arf.config").get())
config.pid, config.execution_timeout_ms = 42, 100
config.output.tibble.width = "inherit"

local calls, results = {}, {}
vim.system = function(args, opts, callback)
	local process = { kill = function(self) self.killed = true end }
	calls[#calls + 1] = { args = args, callback = callback, process = process }
	return process
end
local function start()
	calls, results = {}, {}
	return executor.eval("1", config, function(value, err) results[#results + 1] = { value, err } end)
end
local function reply(n, value)
	calls[n].callback({ code = 0, stdout = vim.json.encode(value), stderr = "" })
	vim.wait(20)
end
start()
reply(1, { capabilities = {} })
assert(#calls == 1 and results[1][2]:find("eval_execution_timeout"))
start()
reply(1, { capabilities = { "eval_execution_timeout" } })
assert(vim.tbl_contains(calls[2].args, "--execution-timeout"))
reply(2, { status = "interrupted", interrupt_reason = "execution_timeout", error = "Evaluation interrupted" })
assert(results[1][1].error:find("execution timeout"))
results[1][1].cleanup()
start()
reply(1, { capabilities = { "eval_execution_timeout" } })
reply(2, { status = "ok" })
assert(results[1][1].status == "ok" and results[1][1].error == nil)
results[1][1].cleanup()
local cancel = start()
cancel()
reply(1, { capabilities = { "eval_execution_timeout" } })
assert(calls[1].process.killed and #calls == 1 and #results == 0)
print("evaluation deadline tests passed")
