vim.opt.rtp:prepend(vim.fn.getcwd())
local help = require("arf.help")
local calls, select_callback, input_callback = {}, nil, nil
package.loaded["arf.session"] = {
	ensure = function(_, cb)
		cb(42)
	end,
}
vim.system = function(args, _, cb)
	calls[#calls + 1] = { args = args, callback = cb }
	return { kill = function() end }
end
vim.ui.select = function(_, _, cb)
	select_callback = cb
end
vim.ui.input = function(_, cb)
	input_callback = cb
end
local function reply(i, value)
	calls[i].callback({ code = 0, stdout = vim.json.encode(value), stderr = "" })
	vim.wait(20)
end
local function arg(args, flag)
	for i, v in ipairs(args) do
		if v == flag then
			return args[i + 1]
		end
	end
end
local function page(topic, content)
	return { kind = "page", package = "stats", topic = topic, content = content, title = "" }
end
local source = vim.api.nvim_get_current_win()
help.show("lm")
reply(1, page("lm", "[link](x-r-help:/foo%20bar?x#y/z)"))
local win = vim.api.nvim_get_current_win()
assert(win ~= source)
vim.cmd.normal({ args = { vim.api.nvim_replace_termcodes("<C-]>", true, false, true) }, bang = false })
assert(arg(calls[2].args, "--current-package") == "stats")
assert(arg(calls[2].args, "--") == "foo%20bar?x#y/z")
reply(2, page("foo", "second"))
vim.cmd.normal({ args = { vim.api.nvim_replace_termcodes("<C-t>", true, false, true) }, bang = false })
assert(vim.api.nvim_get_current_line():find("link"))
vim.cmd.normal({ args = { vim.api.nvim_replace_termcodes("<C-]>", true, false, true) }, bang = false })
local pending = #calls
vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
reply(pending, page("late", "late"))
assert(vim.api.nvim_get_current_win() == source)
help.search()
input_callback("linear")
assert(arg(calls[#calls].args, "--query") == "linear")
reply(#calls, { topics = { { package = "stats", topic = "lm", help_key = "exact", title = "Linear" } } })
select_callback({ package = "stats", topic = "lm", help_key = "exact" })
assert(arg(calls[#calls].args, "--help-key") == "exact")
-- Custom mappings work across page navigation, and false disables each action.
local config = require("arf.config")
config.setup({ help = { keymaps = { follow = "<CR>", back = "<BS>" } } })
help.show("lm")
reply(#calls, page("lm", "[link](x-r-help:/foo)"))
assert(vim.fn.maparg("<C-]>", "n", false, true).buffer == nil)
vim.cmd.normal({ args = { "\r" }, bang = false })
assert(arg(calls[#calls].args, "--") == "foo")
reply(#calls, page("foo", "second"))
vim.cmd.normal({ args = { vim.api.nvim_replace_termcodes("<BS>", true, false, true) }, bang = false })
assert(vim.api.nvim_get_current_line():find("link"))
for _, action in ipairs({ "follow", "back" }) do
	config.setup({ help = { keymaps = { [action] = false } } })
	help.show("lm")
	reply(#calls, page("lm", "[link](x-r-help:/foo)"))
	local key = action == "follow" and "<CR>" or "<BS>"
	assert(vim.fn.maparg(key, "n", false, true).buffer == nil, "disabled action has no mapping")
end
print("help navigation tests passed")
