-- Exercise lifecycle boundaries through the execution API, with asynchronous IPC mocked.
vim.opt.rtp:prepend(vim.fn.getcwd())
local execution = require("arf.execution")
local config = require("arf.config")
local startup, pending, sent, interrupts, notices = nil, nil, {}, {}, {}
local stopped, cancelled, cleaned, discarded = 0, 0, 0, 0
vim.notify = function(message)
	notices[#notices + 1] = message
end
package.loaded["arf.session"] = {
	ensure = function(options, callback)
		startup = callback
	end,
	stop = function()
		stopped = stopped + 1
	end,
}
package.loaded["arf.executor"] = {
	eval = function(code, options, callback)
		sent[#sent + 1] = { code = code, options = vim.deepcopy(options) }
		pending = callback
		return function()
			cancelled = cancelled + 1
		end
	end,
	interrupt = function(_, callback)
		interrupts[#interrupts + 1] = callback
	end,
}
local function result()
	return {
		status = "ok",
		text = "",
		cleanup = function()
			cleaned = cleaned + 1
		end,
	}
end
local function handlers(extra)
	return vim.tbl_extend("force", {
		result = function(value)
			value.cleanup()
		end,
		discard = function()
			discarded = discarded + 1
		end,
	}, extra or {})
end
local function start(extra, codes)
	execution.run(codes or { "1" }, handlers(extra))
end
local function ready()
	startup(123)
end
local function drain()
	vim.wait(20, function()
		return false
	end)
end

-- Every option is captured before startup, including nested tables and auto width.
local width = vim.api.nvim_win_get_width(0) - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
start()
config.setup({
	executable = "new-arf",
	output = { max_bytes = 42, tibble = { width = 10 } },
	image = { render = { dpi = 99 } },
})
ready()
local first = sent[#sent].options
assert(first.executable == "arf" and first.output.max_bytes == 1048576)
assert(first.output.tibble.width == width and first.image.render.dpi == 180)
assert(config.get().output.tibble.width == 10)
pending(result())

-- Consumer/start/validity errors must release the guard and unfinished resources.
start({
	result = function()
		error("consumer failed")
	end,
})
ready()
pending(result())
assert(notices[#notices]:find("consumer failed", 1, true))
assert(cleaned == 2 and discarded == 1)
start({
	start = function()
		error("start failed")
	end,
})
assert(notices[#notices]:find("start failed", 1, true) and discarded == 2)
start({
	valid = function()
		error("validity failed")
	end,
})
assert(notices[#notices]:find("validity failed", 1, true) and discarded == 3)
start()
ready()
pending(result())
assert(cleaned == 3, "can run again after each exception")

-- Stop invalidates both startup and completion callbacks, without touching a new request.
start()
local old_startup = startup
assert(execution.stop())
local sent_before = #sent
start()
old_startup(999)
assert(#sent == sent_before)
ready()
local old_complete = pending
assert(execution.stop())
start()
ready()
old_complete(result())
local count = #sent
start()
assert(#sent == count and notices[#notices]:find("R is running", 1, true))
pending(result())
assert(cancelled == 1)

-- Failed/rejected interrupts can be retried; all requests stop the remaining sequence.
start(nil, { "one", "two" })
ready()
execution.interrupt()
execution.interrupt()
assert(#interrupts == 1)
interrupts[1](nil, "interrupt failed")
execution.interrupt()
assert(#interrupts == 2)
interrupts[2](false)
execution.interrupt()
assert(#interrupts == 3)
interrupts[3](true)
count = #sent
start()
assert(#sent == count and notices[#notices]:find("R is running", 1, true))
pending(result())
drain()
assert(#sent == count, "interrupt acceptance does not run the next expression")

-- Ownership is captured at request start, independently of subsequent setup().
config.setup({ pid = 456 })
start()
ready()
local stops_before = stopped
local original_notify = vim.notify
vim.notify = function(message)
	original_notify(message)
	return {}
end
assert(not execution.stop())
assert(stopped == stops_before and notices[#notices]:find("External sessions", 1, true))
vim.notify = original_notify
pending(result())
-- Explicitly return to automatic sessions through the public setup API.
config.setup({ pid = false })
start()
config.setup({ pid = 789 })
assert(execution.stop() and stopped == stops_before + 1, "stop still owns an automatic startup")
config.setup({ pid = false })
start()
ready()
pending(result())
print("execution lifecycle tests passed")
