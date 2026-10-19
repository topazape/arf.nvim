-- Run with: nvim --headless -u NONE -l tests/session.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local calls, replies, timers = {}, {}, {}
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function drain()
	vim.wait(10, function()
		return false
	end)
end
local system, defer = vim.system, vim.defer_fn
vim.system = function(args, opts, callback)
	local process = { pid = 100 + #calls, killed = 0, waited = 0 }
	function process:kill(signal)
		check(signal == 15, "terminate owned child")
		self.killed = self.killed + 1
	end
	function process:wait(timeout)
		check(timeout == 1000, "bounded shutdown")
		self.waited = self.waited + 1
	end
	calls[#calls + 1] = { args = args, opts = opts, callback = callback, process = process }
	return process
end
vim.defer_fn = function(callback)
	local timer = { callback = callback, closed = false }
	function timer:is_closing()
		return self.closed
	end
	function timer:stop() end
	function timer:close()
		self.closed = true
	end
	timers[#timers + 1] = timer
	return timer
end
local session = require("arf.session")
local config = { executable = "arf-test", startup_timeout = 20 }
local function receive(pid, err)
	replies[#replies + 1] = { pid = pid, err = err }
end
session.ensure({ pid = 42 }, receive)
session.stop()
check(replies[1].pid == 42 and #calls == 0, "borrow external PID without starting or stopping it")
replies = {}
session.ensure(config, receive)
session.ensure(config, receive)
check(#calls == 1, "concurrent startup shares process")
local first = calls[1]
first.opts.stdout(nil, 'startup noise\n{"pid":999}\n{"pi')
drain()
check(#replies == 0, "ignore noise, wrong PID and partial JSON")
first.opts.stdout(nil, 'd":100}\n')
drain()
check(#replies == 2 and replies[1].pid == 100 and replies[2].pid == 100, "deliver split readiness to all waiters")
check(timers[1].closed, "stop startup timer after readiness")
session.ensure(config, receive)
check(#calls == 1 and replies[3].pid == 100, "reuse ready session")
session.stop()
check(first.process.killed == 1 and first.process.waited == 1, "stop owned session once")
session.stop()
check(first.process.killed == 1, "repeated stop is harmless")
replies = {}
session.ensure(config, receive)
local timed_out = calls[2]
timers[2].callback()
check(#replies == 1 and replies[1].err:find("Timed out"), "startup timeout notifies waiter")
check(timed_out.process.killed == 1 and timers[2].closed, "timeout releases process and timer")
session.ensure(config, receive)
local retry = calls[3]
timed_out.opts.stdout(nil, '{"pid":101}\n')
timed_out.callback({ code = 143 })
retry.opts.stdout(nil, '{"pid":102}\n')
drain()
check(#replies == 2 and replies[2].pid == 102, "late callbacks do not invalidate retry")
session.stop()
replies = {}
session.ensure(config, receive)
calls[4].opts.stderr(nil, "startup failure")
calls[4].callback({ code = 1 })
drain()
check(#replies == 1 and replies[1].err:find("startup failure"), "include stderr on early exit")
session.ensure(config, receive)
calls[5].opts.stdout("read failed", nil)
drain()
check(#replies == 2 and replies[2].err:find("read failed"), "report stdout read errors")
vim.system = function()
	error("spawn failure")
end
session.ensure(config, receive)
check(#replies == 3 and replies[3].err:find("spawn failure"), "report spawn exception and allow retry")
vim.system, vim.defer_fn = system, defer
print("session tests passed (" .. checks .. " checks)")
