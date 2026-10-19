-- Run with: nvim --headless -u NONE -l tests/inspect.lua
-- IPC and float creation are mocked; Rscript checks run when R is installed.
vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local inspect = require("arf.inspect")
local source = vim.api.nvim_get_current_buf()
local codes, callbacks, notices, opened = {}, {}, {}, {}
local generations, cleaned, cancelled = {}, 0, 0
local startup_callback, defer_startup, fail_float
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function contains(text, fragment)
	return text:find(fragment, 1, true) ~= nil
end
local function last_text()
	local lines = {}
	for _, line in ipairs(opened[#opened].lines) do
		local parts = {}
		for _, chunk in ipairs(line) do
			parts[#parts + 1] = chunk[1]
		end
		lines[#lines + 1] = table.concat(parts)
	end
	return table.concat(lines, "\n")
end
vim.notify = function(message, level)
	notices[#notices + 1] = { message = message, level = level }
end
package.loaded["arf.session"] = {
	ensure = function(_, cb)
		if defer_startup then
			startup_callback = cb
		else
			cb(123)
		end
	end,
	stop = function() end,
}
package.loaded["arf.executor"] = {
	eval = function(code, _, cb)
		codes[#codes + 1] = code
		callbacks[#callbacks + 1] = cb
		return function()
			cancelled = cancelled + 1
		end
	end,
}
package.loaded["arf.results"] = {
	generation = function(buf)
		return generations[buf] or 0
	end,
	clear = function(buf)
		generations[buf] = (generations[buf] or 0) + 1
	end,
	all = function()
		return {}
	end,
}
package.loaded["arf.float"] = {
	open = function(title, lines, opts)
		if fail_float then
			error("float failure")
		end
		opened[#opened + 1] = { title = title, lines = lines, opts = opts }
	end,
	close = function() end,
}
local function reset(line)
	arf.stop()
	codes, callbacks, notices, opened = {}, {}, {}, {}
	cleaned, cancelled = 0, 0
	startup_callback, defer_startup, fail_float = nil, false, false
	vim.api.nvim_set_current_buf(source)
	vim.api.nvim_buf_set_lines(source, 0, -1, false, { line or "model" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end
local function complete(result)
	local cb = table.remove(callbacks, 1)
	assert(cb, "missing evaluation callback")
	result = result or { text = "result" }
	result.cleanup = function()
		cleaned = cleaned + 1
	end
	cb(result)
end

reset("fit.name <- 1")
vim.api.nvim_win_set_cursor(0, { 1, 5 })
check(inspect.object() == "fit.name", "dotted object names")
reset(" ")
arf.inspect("summary")
check(#codes == 0 and #notices == 1, "no object: do not start evaluation")
reset()
local code = assert(inspect.code("summary", "model"))
check(contains(code, 'base::get("summary", envir = .GlobalEnv, mode = "function"'), "function lookup")
check(contains(code, 'base::get("model", envir = .GlobalEnv, inherits = TRUE)'), "object lookup")
code = assert(inspect.code("performance::model_performance", "model"))
check(contains(code, 'base::getExportedValue("performance", "model_performance")'), "namespace lookup")
check(inspect.code(".my_inspector", "model") ~= nil, "user-defined function names")
local quoted = 'model"); stop("unexpected") #'
check(contains(assert(inspect.code("summary", quoted)), vim.json.encode(quoted)), "quote object names as data")
for _, fn in ipairs({ "", "1fn", "_fn", ".1fn", "base:::summary", "base::summary()", "f; stop()", "function(x) x", {}, 1 }) do
	reset()
	arf.inspect(fn)
	check(#codes == 0 and #notices == 1, "reject invalid function without evaluation")
end
reset()
arf.inspect(nil)
check(#codes == 0 and #notices == 1, "reject nil function")
for _, opts in ipairs({ false, "title", { title = false }, { title = {} }, { title = "two\nlines" }, { title = "bad\0title" } }) do
	reset()
	arf.inspect("summary", opts)
	check(#codes == 0 and #notices == 1, "reject invalid options before evaluation")
end

reset()
arf.inspect("summary")
complete()
check(opened[1].title == "summary(model)", "default title")
check(last_text() == "result", "text output")
check(cleaned == 1, "release evaluation resources")
check(opened[1].opts.owner == source, "float belongs to source buffer")
check(opened[1].opts.width == arf.config.summary_width, "reuse configured float width")
check(opened[1].opts.max_height == arf.config.summary_max_height, "reuse configured float height")
local opts = { title = "Model performance" }
arf.inspect("performance::model_performance", opts)
opts.title = "changed after evaluation started"
complete()
check(opened[2].title == "Model performance", "custom title is captured, not appended")
arf.inspect("performance::check_collinearity")
complete()
check(opened[3].title == "performance::check_collinearity(model)", "calls do not share a registered function or title")
arf.inspect("summary", { title = "" })
complete()
check(opened[4].title == "", "empty title is an explicit override")
arf.summary()
complete()
check(opened[5].title == "summary(model)", "summary API remains compatible")
check(contains(codes[#codes], 'base::getExportedValue("base", "summary")'), "summary API calls base summary")
arf.inspect("base::summary")
complete()
check(opened[6].title == "summary(model)", "base summary uses a short default title")
arf.inspect("base::summary", { title = "Custom summary" })
complete()
check(opened[7].title == "Custom summary", "base summary respects a custom title")
arf.inspect("stats::coef")
complete()
check(opened[8].title == "stats::coef(model)", "other namespace-qualified titles remain unchanged")

reset()
arf.inspect("summary")
complete({ text = "partial", error = "missing package", truncated = true, path = "unused.png" })
check(contains(last_text(), "R error: missing package"), "show R errors")
check(contains(last_text(), "retention limit"), "show truncation notices")
check(cleaned == 1, "discard captured images with other resources")
arf.inspect("summary")
complete({ text = "message\nwarning", chunks = {
	{ text = "message\n", highlight = "ArfMessage" },
	{ text = "warning", highlight = "ArfStderr" },
} })
check(opened[2].lines[1][1][2] == "ArfMessage", "preserve message highlights")
check(opened[2].lines[2][1][2] == "ArfStderr", "preserve warning highlights")
arf.inspect("summary")
complete({ text = "" })
check(#opened[3].lines == 0, "let the float supply its no-output placeholder")

reset()
arf.inspect("summary")
arf.summary()
arf.inspect("stats::coef")
check(#codes == 1 and #notices == 2, "shared busy guard")
complete()
arf.inspect("summary")
complete()
check(#opened == 2, "busy guard released after completion")

reset()
arf.inspect("summary")
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "other" })
complete()
check(#opened == 0 and cleaned == 1, "discard result after editing")
reset()
arf.inspect("summary")
arf.clear()
complete()
check(#opened == 0 and cleaned == 1, "discard result after clearing")
reset()
arf.inspect("summary")
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other)
complete()
check(#opened == 0 and cleaned == 1, "do not steal focus from a different buffer")
vim.api.nvim_set_current_buf(source)
vim.api.nvim_buf_delete(other, { force = true })
reset()
arf.inspect("summary")
arf.stop()
complete()
check(#opened == 0 and cleaned == 1 and cancelled == 1, "stop invalidates pending result")
arf.inspect("summary")
complete()
check(#opened == 1, "can inspect again after stop")

reset()
defer_startup = true
arf.inspect("summary")
arf.clear()
startup_callback(123)
check(#codes == 0, "discard request invalidated during startup")
defer_startup = false
arf.inspect("summary")
complete()
check(#opened == 1, "startup invalidation releases busy guard")
reset()
defer_startup = true
arf.inspect("summary")
startup_callback(nil, "startup failure")
check(#codes == 0 and #notices == 1, "report startup failure")
defer_startup = false
arf.inspect("summary")
local cb = table.remove(callbacks, 1)
cb(nil, "IPC failure")
check(#opened == 0 and #notices == 2, "report IPC failure")
arf.inspect("summary")
complete()
check(#opened == 1, "errors release busy guard")
reset()
fail_float = true
arf.inspect("summary")
complete()
check(cleaned == 1 and #notices == 1, "float failure still releases resources")
fail_float = false
arf.inspect("summary")
complete()
check(#opened == 1, "float failure releases busy guard")

-- The command must call inspect directly, not the compatibility wrapper.
reset()
package.loaded["arf.highlights"] = {}
vim.g.loaded_arf = nil
dofile("plugin/arf.lua")
local original_inspect, original_summary = arf.inspect, arf.summary
local called
arf.inspect = function(fn)
	called = fn
end
arf.summary = function()
	error("ArfSummary must call inspect directly")
end
vim.cmd("ArfSummary")
check(called == "base::summary", "ArfSummary command delegates directly to inspect")
arf.inspect, arf.summary = original_inspect, original_summary
print("inspect Lua tests passed (" .. checks .. " checks)")

-- Optional integration: evaluate the generated R expressions without arf IPC.
if vim.fn.executable("Rscript") ~= 1 then
	print("Rscript unavailable; R integration skipped")
	return
end
local r = {
	"model <- stats::lm(mpg ~ wt + hp, data = mtcars)",
	"inspect_ci <- function(x) stats::confint(x, level = 0.90)",
	"stopifnot(identical(" .. assert(inspect.code("summary", "model")) .. ", summary(model)))",
	"stopifnot(identical(" .. assert(inspect.code("stats::coef", "model")) .. ", stats::coef(model)))",
	"stopifnot(identical(" .. assert(inspect.code("inspect_ci", "model")) .. ", inspect_ci(model)))",
	"expr_object <- quote(stop('must not evaluate a returned language object'))",
	"stopifnot(identical(" .. assert(inspect.code("identity", "expr_object")) .. ", expr_object))",
	"summary <- 1L",
	"stopifnot(identical(" .. assert(inspect.code("summary", "model")) .. ", base::summary(model)))",
	"rm(summary)",
	"stopifnot(inherits(try(" .. assert(inspect.code("arf_missing_inspector", "model")) .. ", silent = TRUE), 'try-error'))",
	"stopifnot(inherits(try(" .. assert(inspect.code("arfDefinitelyMissingPackage::inspect", "model")) .. ", silent = TRUE), 'try-error'))",
	"stopifnot(inherits(try(" .. assert(inspect.code("summary", "arf_missing_object")) .. ", silent = TRUE), 'try-error'))",
	"print('inspect R integration passed')",
}
local result = vim.system({ "Rscript", "--vanilla", "-" }, { text = true, stdin = table.concat(r, "\n") }):wait(30000)
assert(result.code == 0, result.stderr)
print(result.stdout)
