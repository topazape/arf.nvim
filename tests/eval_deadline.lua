vim.opt.rtp:prepend(vim.fn.getcwd())
local executor = require("arf.executor")
local config = vim.deepcopy(require("arf.config").get())
config.pid, config.execution_timeout_ms = 42, 100
config.output.tibble.width = "inherit"

local calls, results = {}, {}
vim.system = function(args, opts, callback)
	local process = {
		kill = function(self)
			self.killed = true
		end,
	}
	calls[#calls + 1] = { args = args, callback = callback, process = process }
	return process
end
local function start()
	calls, results = {}, {}
	return executor.eval("1", config, function(value, err)
		results[#results + 1] = { value, err }
	end)
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

-- Session transport/protocol errors must not masquerade as missing support.
for _, response in ipairs({
	{ code = 1, stdout = "", stderr = "session no longer exists" },
	{ code = 1, stdout = "", stderr = "" },
	{ code = 0, stdout = "invalid JSON", stderr = "" },
	{ code = 0, stdout = '{"capabilities":true}', stderr = "" },
}) do
	start()
	calls[1].callback(response)
	vim.wait(20)
	assert(#calls == 1 and #results == 1 and not results[1][2]:find("requires", 1, true))
	if response.stderr ~= "" then
		assert(results[1][2] == response.stderr)
	end
end

-- Interrupting the preflight must prevent evaluation and release the guard.
local execution = require("arf.execution")
require("arf.config").setup({ pid = 42, execution_timeout_ms = 100 })
local discarded = 0
vim.notify = function() end
calls = {}
execution.run({ "must_not_run", "nor_this" }, {
	result = function()
		error("cancelled evaluation produced a result")
	end,
	discard = function()
		discarded = discarded + 1
	end,
})
execution.interrupt()
assert(calls[2].args[3] == "interrupt")
reply(2, { accepted = false })
reply(1, { capabilities = { "eval_execution_timeout" } })
assert(#calls == 2 and discarded == 1, "interrupt cancels evaluation before submission")
local completed = false
execution.run({ "1" }, {
	result = function(value)
		value.cleanup()
		completed = true
	end,
})
reply(3, { capabilities = { "eval_execution_timeout" } })
assert(calls[4].args[3] == "eval", "guard is released after cancellation")
reply(4, { status = "ok" })
assert(completed)
print("evaluation deadline tests passed")
