-- Optional real-backend checks (requires arf 0.7.1+ and R):
-- nvim --headless -u NONE -l tests/integration.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local objects = require("arf.objects")
local executor = require("arf.executor")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p", 448)
local info, exited, stderr
local startup = ""
local args = { "arf", "headless", "--vanilla", "--no-history", "--json", "--ipc-expose", objects.expose }
if vim.fn.has("win32") == 0 then
	vim.list_extend(args, { "--ipc-bind", dir .. "/ipc.sock" })
end
local process = vim.system(
	args,
	{
		text = true,
		stdout = vim.schedule_wrap(function(err, data)
			assert(not err, err)
			startup = startup .. (data or "")
			if startup:find("\n", 1, true) and not info then
				info = vim.json.decode(startup:match("([^\n]+)"))
			end
		end),
		stderr = vim.schedule_wrap(function(_, data)
			stderr = (stderr or "") .. (data or "")
		end),
	},
	vim.schedule_wrap(function()
		exited = true
	end)
)

local function await(start)
	local done, value, failure = false, nil, nil
	start(function(result, err)
		done, value, failure = true, result, err
	end)
	assert(
		vim.wait(10000, function()
			return done
		end),
		"backend response did not arrive"
	)
	return value, failure
end

local ok, err = xpcall(function()
	assert(
		vim.wait(10000, function()
			return info ~= nil or exited
		end),
		"arf startup timed out"
	)
	assert(info and info.pid == process.pid, stderr or "arf failed to start")
	local config = vim.deepcopy(require("arf.config").get())
	config.pid, config.external = info.pid, false
	config.eval_timeout_ms, config.output.tibble.width = 3000, "inherit"
	local function evaluate(source)
		local result, failure = await(function(done)
			return executor.eval(source, config, done)
		end)
		assert(result, failure)
		result.cleanup()
		assert(result.status == "ok", result.text .. (result.error or ""))
		return result.text
	end
	local function fetch()
		local items, failure = await(function(done)
			return objects.fetch(config, done)
		end)
		assert(items, failure)
		return items
	end
	assert(#fetch() == 0, "empty environments return a JSON array")
	evaluate(
		'x <- matrix(1, 2, 3); assign("a b\n日本語", 1:3, .GlobalEnv); makeActiveBinding("active", function() stop("invoked"), .GlobalEnv)'
	)
	local native = fetch()
	config.external = true
	assert(vim.deep_equal(native, fetch()), "native and evaluation lookups return the same items")
	config.external = false
	local baseline = evaluate("cat(length(base::getAllConnections()))")
	local captured, capture_error = await(function(done)
		return executor.eval('cat("output"); message("message"); plot(1:3)', config, done)
	end)
	assert(captured, capture_error)
	assert(captured.status == "ok" and captured.text:find("output", 1, true) and #captured.paths == 1)
	assert(vim.uv.fs_stat(captured.paths[1]), "retain generated plots until released")
	captured.cleanup()
	local failed, evaluation_error = await(function(done)
		return executor.eval('stop("expected error")', config, done)
	end)
	assert(failed, evaluation_error)
	assert(failed.status == "error" and failed.text:find("expected error", 1, true))
	failed.cleanup()
	assert(evaluate("cat(length(base::getAllConnections()))") == baseline, "success and errors close captures")
	config.eval_timeout_ms = 100
	local timed_out
	local result, failure = await(function(done)
		return executor.eval("Sys.sleep(0.5); completed_after_timeout <- TRUE", config, done, function(id)
			timed_out = id
		end)
	end)
	assert(not result and failure:find("timed out", 1, true) and timed_out, "observe timeout completion")
	config.eval_timeout_ms = 3000
	assert(evaluate("cat(completed_after_timeout)") == "TRUE", "a response timeout does not cancel R")
	assert(evaluate("cat(length(base::getAllConnections()))") == baseline, "timeout finalization closes captures")
	config.eval_timeout_ms = 100
	local interrupted, interrupt_error
	result, failure = await(function(done)
		return executor.eval("Sys.sleep(20); must_not_run <- TRUE", config, done, function(id)
			executor.interrupt(vim.tbl_extend("force", config, { execution_id = id }), function(accepted, why)
				interrupted, interrupt_error = accepted, why
			end)
		end)
	end)
	assert(not result and failure and interrupted, interrupt_error or "timeout remains interruptible")
	config.eval_timeout_ms = 3000
	assert(evaluate('cat(exists("must_not_run", envir = .GlobalEnv))') == "FALSE")
	assert(evaluate("cat(length(base::getAllConnections()))") == baseline, "interruption closes captures")
end, debug.traceback)
process:kill(15)
process:wait(1000)
vim.fn.delete(dir, "rf")
assert(ok, err)
print("real arf integration tests passed")
