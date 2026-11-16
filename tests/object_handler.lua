vim.opt.rtp:prepend(vim.fn.getcwd())
local objects = require("arf.objects")
local calls, replies, evaluations = {}, {}, 0
local config = {
	executable = "arf-test",
	pid = 123,
	external = false,
	output = { max_bytes = 1048576 },
}
vim.system = function(args, opts, callback)
	local process = { killed = false }
	function process:kill(signal)
		assert(signal == 15)
		self.killed = true
	end
	calls[#calls + 1] = { args = args, callback = callback, process = process }
	return process
end
package.loaded["arf.executor"] = {
	eval = function(code, options, callback)
		evaluations = evaluations + 1
		assert(code == objects.code and options.external)
		callback({ text = "626f72726f776564\t\t\n", cleanup = function() end })
	end,
}
local function receive(result, err)
	replies[#replies + 1] = { result = result, err = err }
end
local function finish(index, value, code, stderr)
	calls[index].callback({ code = code or 0, stdout = vim.json.encode(value), stderr = stderr or "" })
	vim.wait(10)
end
local function start()
	calls, replies = {}, {}
	return objects.fetch(config, receive)
end
local supported = { capabilities = { "call_execution_timeout" } }
local name = 'a b\n日本語"'
start()
assert(vim.deep_equal(calls[1].args, { "arf-test", "ipc", "session", "--pid", "123" }))
finish(1, supported)
assert(vim.deep_equal(calls[2].args, {
	"arf-test",
	"ipc",
	"call",
	"nvim/objects",
	"--pid",
	"123",
	"--queue-timeout",
	"5000",
	"--execution-timeout",
	"5000",
}))
finish(2, { value = { { name = name, class = "tbl_df", size = "12,450 × 8" } } })
local item = replies[1].result[1]
assert(item.name == name and item.text == name and item.class == "tbl_df" and item.size == "12,450 × 8")
assert(evaluations == 0, "owned metadata bypasses code evaluation and plot capture")

start()
finish(1, supported)
finish(2, { value = vim.empty_dict() })
assert(not replies[1].result and replies[1].err:find("invalid object list", 1, true))
start()
finish(1, supported)
finish(2, { value = {} })
assert(#replies[1].result == 0, "empty environments produce an empty picker")
for _, value in ipairs({ false, { { name = "x", class = 4, size = "" } }, { vim.NIL } }) do
	start()
	finish(1, supported)
	finish(2, { value = value })
	assert(not replies[1].result and replies[1].err, "malformed metadata fails without opening a picker")
end
start()
finish(1, { capabilities = {} })
assert(#calls == 1 and replies[1].err:find("0.7.1", 1, true), "older servers cannot silently ignore deadlines")
start()
finish(1, supported)
finish(2, {}, 4, '{"error":{"code":"HANDLER_EXECUTION_TIMEOUT","message":"Handler execution timed out"}}')
assert(replies[1].err:find("Handler execution timed out", 1, true))
start()
finish(1, {}, 2)
assert(replies[1].err:find("arf IPC failed (2)", 1, true), "empty stderr still reports the exit status")
start()
calls[1].callback({ code = 0, stdout = "{", stderr = "" })
vim.wait(10)
assert(replies[1].err and #calls == 1, "malformed capability responses fail before a handler call")
local limit = config.output.max_bytes
config.output.max_bytes = 10
start()
finish(1, supported)
finish(2, { value = { { name = "x", class = "numeric", size = "100" } } })
assert(replies[1].err:find("output.max_bytes", 1, true), "bound retained metadata responses")
config.output.max_bytes = limit

local cancel = start()
cancel()
finish(1, supported)
assert(calls[1].process.killed and #calls == 1 and #replies == 0, "cancel capability check")
cancel = start()
finish(1, supported)
cancel()
finish(2, { value = {} })
assert(calls[2].process.killed and #replies == 0, "cancel handler call and ignore its late response")
local system = vim.system
vim.system = function()
	error("spawn failure")
end
replies = {}
objects.fetch(config, receive)
assert(replies[1].err:find("spawn failure", 1, true))
vim.system = system
config.external = true
calls, replies = {}, {}
objects.fetch(config, receive)
assert(evaluations == 1 and #calls == 0 and replies[1].result[1].name == "borrowed", "borrowed sessions retain eval")

-- The existing execution lifecycle also owns native queries: no concurrent evals,
-- and stopping an otherwise empty session discards metadata that arrives later.
local arf = require("arf")
local notices, picked = {}, nil
vim.notify = function(message)
	notices[#notices + 1] = message
end
package.loaded["arf.session"] = {
	ensure = function(_, cb)
		cb(123)
	end,
	stop = function() end,
}
package.loaded["snacks.picker"] = {
	pick = function(opts)
		picked = opts
	end,
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x <- 1" })
calls, picked = {}, nil
arf.objects()
arf.run(1, 1)
assert(#calls == 1 and notices[#notices]:find("R is running", 1, true), "native query holds execution guard")
finish(1, supported)
finish(2, { value = { { name = "x", class = "numeric", size = "1" } } })
assert(picked.items[1].name == "x", "native metadata reaches the existing picker")
calls, picked = {}, nil
arf.objects()
arf.stop()
finish(1, supported)
assert(#calls == 1 and picked == nil, "stop invalidates pending native lookup")
calls = {}
arf.objects()
finish(1, supported)
finish(2, { value = {} })
assert(picked and #picked.items == 0, "lookup works again after stopping")
print("dedicated object handler tests passed")
