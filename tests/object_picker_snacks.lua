vim.opt.rtp:prepend(vim.fn.getcwd())
local root = vim.env.ARF_TEST_SNACKS or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
if vim.fn.filereadable(root .. "/lua/snacks/picker/init.lua") ~= 1 then
	assert(not vim.env.ARF_TEST_SNACKS, "ARF_TEST_SNACKS does not contain Snacks.picker")
	print("Snacks unavailable; real picker integration skipped")
	return
end
vim.opt.rtp:append(root)
local original_select = vim.ui.select
require("snacks").setup({ picker = { enabled = false } })
local calls, refreshes = {}, 0
local main = vim.api.nvim_get_current_win()
local function wait_for(predicate, message)
	assert(vim.wait(3000, predicate, 10), message)
end
local function keys(value)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt", false)
	-- -l scripts do not enter Neovim's main loop to emit TextChanged.
	if vim.bo.filetype == "snacks_picker_input" then
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = vim.api.nvim_get_current_buf() })
	end
end
local function open()
	local picker = require("arf.object_picker").open({
		{ name = "alpha_model", text = "alpha_model", class = "numeric", size = "1,000" },
		{ name = "beta", text = "beta", class = "apm", size = "3" },
	}, function(done)
		refreshes = refreshes + 1
		vim.schedule(function()
			done({ { name = "updated", text = "updated", class = "list", size = "3" } })
		end)
	end, function(fn, name)
		assert(vim.api.nvim_get_current_win() == main, "selection returns to source window")
		calls[#calls + 1] = { fn, name }
	end)
	wait_for(function()
		return picker.shown and not picker:is_active()
	end, "picker opens")
	vim.cmd("stopinsert")
	vim.api.nvim_set_current_win(picker.input.win.win)
	return picker
end
local function closed(picker)
	wait_for(function()
		return picker.closed and picker.layout.closed
	end, "picker closes")
end

local picker = open()
keys("iapm<Esc>")
wait_for(function()
	return picker.input.filter.pattern == "apm" and not picker:is_active() and picker.list:count() == 1
end, "fuzzy search matches names, not metadata")
assert(picker:current().name == "alpha_model")
assert(refreshes == 0, "search does not fetch metadata")
keys("<CR>")
closed(picker)
assert(vim.deep_equal(calls[1], { "base::summary", "alpha_model" }))

picker = open()
keys("iprq<Esc>")
wait_for(function()
	return picker.input.filter.pattern == "prq"
end, "action keys are searchable in insert mode")
assert(refreshes == 0 and #calls == 1 and not picker.closed)
keys("gg0D")
wait_for(function()
	return picker.input.filter.pattern == "" and not picker:is_active()
end, "clear search")
keys("r")
wait_for(function()
	return refreshes == 1 and not picker:is_active() and picker:current() and picker:current().name == "updated"
end, "refresh key replaces items")
keys("p")
closed(picker)
assert(vim.deep_equal(calls[2], { "base::print", "updated" }))

picker = open()
keys("q")
closed(picker)
assert(#calls == 2, "quit does not inspect")
assert(vim.ui.select == original_select, "Object Picker does not replace vim.ui.select")
print("real Snacks picker search and key tests passed")
