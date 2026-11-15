-- Run with: nvim --headless -u NONE -l tests/help.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local arf = require("arf")
local source = vim.api.nvim_get_current_buf()
local source_win = vim.api.nvim_get_current_win()
local requests, notices, opened, selections = {}, {}, {}, {}
local startup_count, startup_callback, startup_failure = 0, nil, nil
local defer_startup, fail_process, fail_float = false, false, false
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
vim.notify = function(message)
	notices[#notices + 1] = message
end
package.loaded["arf.session"] = {
	ensure = function(_, callback)
		startup_count = startup_count + 1
		if defer_startup then
			startup_callback = callback
		elseif startup_failure then
			callback(nil, startup_failure)
		else
			callback(123)
		end
	end,
	stop = function() end,
}
-- Help must remain usable while R is busy, without using the evaluation path.
package.loaded["arf.execution"] = {
	run = function()
		error("help must not evaluate R")
	end,
}
package.loaded["arf.executor"] = {
	eval = function()
		error("help must not evaluate R")
	end,
}
package.loaded["arf.float"] = {
	open = function(title, lines, opts)
		if fail_float then
			error("float failure")
		end
		opened[#opened + 1] = { title = title, lines = lines, opts = opts }
	end,
}
vim.system = function(args, opts, callback)
	if fail_process then
		error("process failure")
	end
	requests[#requests + 1] = { args = args, opts = opts, callback = callback }
	return { kill = function() end }
end
vim.ui.select = function(items, opts, callback)
	selections[#selections + 1] = { items = items, opts = opts, callback = callback }
end
local function reset(line, col)
	requests, notices, opened, selections = {}, {}, {}, {}
	startup_count, startup_callback, startup_failure = 0, nil, nil
	defer_startup, fail_process, fail_float = false, false, false
	vim.api.nvim_set_current_win(source_win)
	vim.api.nvim_set_current_buf(source)
	vim.api.nvim_buf_set_lines(source, 0, -1, false, { line or "lm(y ~ x)" })
	vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
end
local function finish(request, reply, code, stderr)
	request.callback({
		code = code or 0,
		stdout = type(reply) == "string" and reply or vim.json.encode(reply),
		stderr = stderr or "",
	})
	vim.wait(20)
end
local function page(content)
	return {
		kind = "page",
		package = "stats",
		topic = "lm",
		title = "Fitting Linear Models",
		content = content or "# Fitting Linear Models\n\n## Usage\n```r\nlm(formula, data)\n```",
		content_type = "markdown",
		entry_type = "help",
	}
end
local function arg(request, flag)
	for i, value in ipairs(request.args) do
		if value == flag then
			return request.args[i + 1]
		end
	end
end
local function topic(request)
	return arg(request, "--")
end
local function text()
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

reset(" ")
arf.help()
check(startup_count == 0 and #requests == 0 and #notices == 1, "no cursor topic: do not start a session")
reset()
arf.help()
check(startup_count == 1 and #requests == 1, "cursor topic starts or reuses session")
check(vim.deep_equal(vim.list_slice(requests[1].args, 1, 4), { "arf", "ipc", "r-help", "show" }), "use help IPC")
check(arg(requests[1], "--pid") == "123", "target the session that was ensured")
finish(requests[1], page())
check(#opened == 1 and text():find("lm(formula, data)", 1, true), "display returned help content")
check(opened[1].opts.filetype == "markdown" and opened[1].opts.wrap == true, "readable Markdown float")
check(opened[1].opts.owner == source, "float belongs to source buffer")
check(opened[1].opts.width == arf.config.float_window.width, "reuse configured width")
check(opened[1].opts.max_height == arf.config.float_window.max_height, "reuse configured height")

for _, col in ipairs({ 0, 5, 7, 8 }) do
	reset("stats::lm(y ~ x)", col)
	arf.help()
	check(topic(requests[1]) == "lm" and arg(requests[1], "--package") == "stats", "resolve qualified cursor topic")
	finish(requests[1], page())
end
reset("as.data.frame(x)", 5)
arf.help()
check(topic(requests[1]) == "as.data.frame", "preserve dotted function names")
finish(requests[1], page())
reset("`custom function`(x)", 8)
arf.help()
check(topic(requests[1]) == "custom function", "resolve backtick-quoted topics")
finish(requests[1], page())
reset("x %in% y", 3)
arf.help()
check(topic(requests[1]) == "%in%", "resolve an infix operator from its interior")
finish(requests[1], page())
reset()
arf.help("stats::lm")
check(topic(requests[1]) == "lm" and arg(requests[1], "--package") == "stats", "explicit qualified topic")
finish(requests[1], page())
reset()
local literal = 'topic; stop("unexpected")'
arf.help(literal)
check(topic(requests[1]) == literal, "explicit topic remains literal process argument")
check(requests[1].opts.stdin == nil, "help does not submit R code")
finish(requests[1], page())
for _, requested in ipairs({ "+", "[", "%in%", "-x" }) do
	reset()
	arf.help(requested)
	check(topic(requests[1]) == requested, "operators can be requested explicitly")
	finish(requests[1], page())
end

local candidates = {
	{ package = "alpha", topic = "shared", title = "First help", help_key = "shared-a" },
	{ package = "beta", topic = "shared", title = "Second help", help_key = "shared-b" },
}
reset()
arf.help("shared")
finish(requests[1], { kind = "candidates", candidates = candidates })
check(#opened == 0 and #selections == 1 and #requests == 1, "ask user instead of selecting ambiguous topic")
check(vim.deep_equal(selections[1].items, candidates), "offer every returned candidate")
check(selections[1].opts.format_item(candidates[2]):find("beta", 1, true), "identify candidate package")
selections[1].callback(candidates[2])
check(#requests == 2 and topic(requests[2]) == "shared", "retrieve selected topic")
check(arg(requests[2], "--package") == "beta", "retrieve selected package")
check(arg(requests[2], "--help-key") == "shared-b", "use exact metadata key")
finish(requests[2], page("# Selected page"))
check(#opened == 1 and text() == "# Selected page", "show selected help")
reset()
arf.help("shared")
finish(requests[1], { kind = "candidates", candidates = candidates })
selections[1].callback(nil)
check(#requests == 1 and #opened == 0 and #notices == 0, "cancel selection quietly")
reset()
arf.help("shared")
finish(requests[1], {
	kind = "candidates",
	candidates = { { package = "alpha", topic = "shared", help_key = vim.NIL } },
})
selections[1].callback(selections[1].items[1])
check(
	arg(requests[2], "--package") == "alpha" and arg(requests[2], "--help-key") == nil,
	"null help key uses topic lookup"
)
finish(requests[2], page())

reset()
startup_failure = "startup failure"
arf.help()
check(#requests == 0 and #notices == 1 and notices[1]:find("startup failure", 1, true), "report startup errors")
reset()
fail_process = true
arf.help()
check(#requests == 0 and #notices == 1, "report process creation errors")
reset()
arf.help()
finish(requests[1], "", 4, '{"error":{"code":"HELP_NOT_FOUND","message":"No matching help"}}')
check(#opened == 0 and #notices == 1 and notices[1]:find("No matching help", 1, true), "report help lookup errors")
for _, reply in ipairs({
	"not JSON",
	"null",
	"[]",
	'{"kind":"unknown"}',
	'{"kind":"page","content":3}',
	'{"kind":"candidates","candidates":false}',
	'{"kind":"candidates","candidates":[null]}',
	'{"kind":"candidates","candidates":[{"topic":"lm"}]}',
}) do
	reset()
	arf.help()
	finish(requests[1], reply)
	check(#opened == 0 and #selections == 0 and #notices == 1, "reject malformed response")
end
reset()
fail_float = true
arf.help()
finish(requests[1], page())
check(#notices == 1 and notices[1]:find("float failure", 1, true), "report float errors")

reset()
arf.help("old")
arf.help("new")
finish(requests[2], page("# New page"))
finish(requests[1], page("# Old page"))
check(#opened == 1 and text() == "# New page", "older response cannot replace newer help")
reset()
arf.help()
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other)
finish(requests[1], page())
check(#opened == 0, "do not steal focus after changing source buffer")
reset()
arf.help()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { "mean(x)" })
finish(requests[1], page())
check(#opened == 0, "do not show stale help after source is edited")
reset()
arf.help()
vim.cmd("vsplit")
finish(requests[1], page())
check(#opened == 0, "do not steal focus after changing source window")
vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
reset()
defer_startup = true
arf.help()
vim.api.nvim_set_current_buf(other)
startup_callback(123)
vim.wait(20)
check(#requests == 0, "do not start lookup after source context is lost during startup")
reset()
arf.help("shared")
finish(requests[1], { kind = "candidates", candidates = candidates })
arf.help("new")
selections[1].callback(candidates[1])
check(#requests == 2, "old selection cannot start a lookup after a newer request")
finish(requests[2], page())
print("help tests passed (" .. checks .. " checks)")
