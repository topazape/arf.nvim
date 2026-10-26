vim.opt.rtp:prepend(vim.fn.getcwd())
local objects = require("arf.objects")
local arf = require("arf")
local callbacks, codes, notices, floats = {}, {}, {}, {}
local cleaned = 0
vim.notify = function(message)
	notices[#notices + 1] = message
end
package.loaded["arf.session"] = {
	ensure = function(_, cb)
		cb(123)
	end,
	stop = function() end,
}
package.loaded["arf.executor"] = {
	eval = function(code, _, cb)
		codes[#codes + 1] = code
		callbacks[#callbacks + 1] = cb
		return function() end
	end,
}
package.loaded["arf.float"] = {
	open = function(title, lines)
		floats[#floats + 1] = { title = title, lines = lines }
	end,
	close = function() end,
}
local options
local picker = {
	opts = {},
	current = function(self)
		return self.opts.items[1]
	end,
	close = function(self)
		self.closed = true
	end,
	find = function(self)
		self.refreshed = true
	end,
}
package.loaded["snacks.picker"] = {
	pick = function(opts)
		options = opts
		picker.opts, picker.closed = opts, false
		return picker
	end,
}
local function hex(s)
	return (s:gsub(".", function(c)
		return string.format("%02x", c:byte())
	end))
end
local name = 'a b"); stop("bad") #\n日本語'
local function row(n, cls, size)
	return hex(n) .. "\t" .. hex(cls or "") .. "\t" .. hex(size or "") .. "\n"
end
local function complete(text, err, truncated)
	local cb = table.remove(callbacks, 1)
	assert(cb)
	cb({
		text = text or "",
		error = err,
		truncated = truncated,
		cleanup = function()
			cleaned = cleaned + 1
		end,
	})
end
local items = objects.decode(row(name, "tbl_df", "12,450 × 8"))
assert(items[1].name == name and items[1].text == name)
assert(items[1].class == "tbl_df" and items[1].size == "12,450 × 8")
assert(#objects.decode("") == 0)
assert(not pcall(objects.decode, "invalid"))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "model" })
arf.objects()
assert(codes[1] == objects.code)
arf.inspect("summary")
assert(notices[#notices]:find("R is running", 1, true))
complete(row(name, "numeric", "1,000"))
assert(options.title == "Arf Objects" and cleaned == 1)
assert(options.items[1].name == name)
assert(options.win.input.keys.p.mode == "n" and options.win.list.keys.r.mode == "n")
local before = #codes
options.format(options.items[1])
assert(#codes == before, "format does not evaluate R")
options.actions.arf_refresh(picker)
complete(row("new", "data.frame", "3 × 2"))
assert(picker.refreshed and picker.opts.items[1].name == "new")
for _, case in ipairs({
	{ "confirm", "base", "summary" },
	{ "arf_print", "base", "print" },
}) do
	picker.closed = false
	local action = options[case[1]] or options.actions[case[1]]
	local previous_floats = #floats
	action(picker, items[1])
	assert(picker.closed)
	assert(codes[#codes]:find(vim.json.encode(name), 1, true))
	assert(codes[#codes]:find("inherits = FALSE", 1, true), "selected objects stay in GlobalEnv")
	assert(codes[#codes]:find('base::getExportedValue("' .. case[2] .. '", "' .. case[3] .. '")', 1, true))
	complete("result", case[1] == "arf_print" and "object no longer exists" or nil)
	assert(#floats == previous_floats + 1, "each action opens a new result float")
end
assert(vim.inspect(floats[#floats].lines):find("object no longer exists", 1, true))
picker.closed = false
options.actions.arf_refresh(picker)
local old = picker.opts.items
complete("", "metadata failed")
assert(picker.opts.items == old and notices[#notices]:find("metadata failed", 1, true))
options.actions.arf_refresh(picker)
complete("bad")
assert(notices[#notices]:find("Unable to read object list", 1, true))
options.actions.arf_refresh(picker)
complete("", nil, true)
assert(notices[#notices]:find("output_max_bytes", 1, true))
options.actions.arf_refresh(picker)
picker.closed = true
complete(row("late"))
assert(picker.opts.items == old, "closed picker ignores refresh")
options.actions.arf_refresh(picker)
-- Closed picker fails validity before starting evaluation.
assert(#callbacks == 0)
arf.objects()
local cb = table.remove(callbacks, 1)
cb(nil, "IPC failure")
assert(notices[#notices]:find("IPC failure", 1, true))
arf.objects()
complete("")
assert(#options.items == 0)
package.loaded["snacks.picker"] = nil
package.preload["snacks.picker"] = function()
	error("unavailable")
end
before = #codes
arf.objects()
assert(#codes == before and notices[#notices]:find("requires snacks.nvim", 1, true))
print("object picker unit tests passed")

if vim.env.ARF_TEST_MODE == "unit" then
	return
end
if vim.fn.executable("Rscript") ~= 1 then
	print("Rscript unavailable; object metadata integration skipped")
	return
end
local script = [[
assign("a b", 1:1000, .GlobalEnv)
df <- data.frame(x = 1:3, y = 4:6)
model <- lm(mpg ~ wt, mtcars)
bad <- structure(1, class = "broken")
dim.broken <- function(x) stop("metadata error")
noisy <- structure(1, class = "noisy")
dim.noisy <- function(x) { base::cat("stdout noise"); base::cat("stderr noise", file = base::stderr()); message("message noise"); warning("warning noise"); NULL }
noisy_bad <- structure(1, class = "noisy_bad")
dim.noisy_bad <- function(x) { base::cat("noise before failure"); message("message before failure"); stop("metadata error") }
# Standard function names in the user's session must not affect collection.
ls <- get <- class <- dim <- length <- format <- cat <- function(...) stop("masked function called")
active_calls <- 0L
makeActiveBinding("active", function() { active_calls <<- active_calls + 1L; stop("must not run") }, .GlobalEnv)
]]
local result = vim.system({ "Rscript", "--vanilla", "-" }, {
	text = true,
	stdin = script .. objects.code .. "\nstopifnot(active_calls == 0L)\n",
}):wait(30000)
assert(result.code == 0, result.stderr)
assert(result.stderr == "", "metadata messages and warnings must be suppressed")
local by_name = {}
for _, item in ipairs(objects.decode(result.stdout)) do
	by_name[item.name] = item
end
assert(by_name["a b"].size == "1,000")
assert(by_name.df.size == "3 × 2" and by_name.df.class == "data.frame")
assert(by_name.model.class == "lm" and by_name.model.size ~= "")
assert(by_name.bad.class == "broken" and by_name.bad.size == "")
assert(by_name.noisy.class == "noisy" and by_name.noisy.size == "1")
assert(by_name.noisy_bad.class == "noisy_bad" and by_name.noisy_bad.size == "")
assert(by_name.active.class == "" and by_name.active.size == "")
print("object metadata R integration passed")
