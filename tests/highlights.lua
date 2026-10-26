vim.opt.rtp:prepend(vim.fn.getcwd())
local highlights = require("arf.highlights")
assert(
	vim.api.nvim_get_hl(0, { name = "ArfFloatNormal", link = false }).bg
		== (vim.o.background == "dark" and 0x262626 or 0xf5f5f5),
	"default palette works without setup"
)
highlights.apply("auto")
local function get(name, link)
	return vim.api.nvim_get_hl(0, { name = name, link = link or false })
end
local function clear_defaults()
	vim.cmd("highlight clear")
end
for _, colors in ipairs({ { 0xffffff, 0x000000 }, { 0x000000, 0xffffff } }) do
	clear_defaults()
	vim.api.nvim_set_hl(0, "Normal", { fg = colors[1], bg = colors[2] })
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = colors[1], bg = colors[2] })
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	assert(get("ArfElapsedStale").fg == 0x808080, "auto dims elapsed time")
	assert(get("ArfOutputStale").fg == 0x808080, "stale output blends toward background")
	assert(get("ArfFloatOutputStale").fg == 0x808080, "stale float blends toward background")
	assert(get("ArfOutput").fg == (colors[1] == 0xffffff and 0xd9d9d9 or 0x262626))
	assert(get("ArfSeparator").fg == (colors[1] == 0xffffff and 0x404040 or 0xbfbfbf))
	assert(get("ArfFloatOutput").fg == (colors[1] == 0xffffff and 0xf2f2f2 or 0x0d0d0d))
	for group, source in pairs({
		ArfElapsed = "DiagnosticInfo",
		ArfMessage = "DiagnosticInfo",
		ArfSignRunning = "DiagnosticInfo",
		ArfSignSuccess = "DiagnosticOk",
		ArfSignError = "DiagnosticError",
		ArfWarning = "DiagnosticWarn",
		ArfFloatBorder = "FloatBorder",
		ArfFloatTitle = "FloatTitle",
	}) do
		assert(get(group, true).link == source, group .. " follows the colorscheme")
	end
end
vim.api.nvim_set_hl(0, "ArfOutput", { fg = 0x123456 })
highlights.apply()
assert(get("ArfOutput").fg == 0x123456, "preserve user overrides")
clear_defaults()
vim.api.nvim_set_hl(0, "Normal", { fg = 0xabcdef })
vim.api.nvim_set_hl(0, "NormalFloat", { link = "Normal" })
highlights.apply()
assert(get("ArfOutput", true).link == "Normal", "transparent output follows Normal")
assert(get("ArfElapsedStale", true).link == "Comment", "transparent stale timing uses Comment")
assert(get("ArfOutputStale", true).link == "Comment", "transparent stale output uses Comment")
assert(get("ArfFloatOutputStale", true).link == "Comment", "transparent stale float uses Comment")
assert(get("ArfSeparator", true).link == "NonText", "transparent separator follows NonText")
assert(get("ArfFloatOutput", true).link == "ArfFloatNormal", "transparent float follows its source")
local arf = require("arf")
for _, background in ipairs({ "dark", "light" }) do
	vim.o.background = background
	local original_normal = get("Normal")
	arf.setup({ theme = "default" })
	assert(get("ArfElapsed").fg == (background == "dark" and 0x8daed1 or 0x3f668d))
	assert(get("ArfElapsedStale").fg ~= get("ArfElapsed").fg, "default dims elapsed time")
	assert(get("ArfFloatNormal").bg == (background == "dark" and 0x262626 or 0xf5f5f5))
	assert(get("ArfOutputStale").fg ~= get("ArfOutput").fg, "default stale output is distinct")
	assert(get("ArfFloatOutputStale").fg ~= get("ArfFloatOutput").fg, "default stale float is distinct")
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^Arf") then
			local definition = get(name, true)
			assert(definition.fg and not definition.link, name .. " has a fixed default color")
		end
	end
	assert(vim.deep_equal(get("Normal"), original_normal), "default leaves the editor colors unchanged")
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	assert(get("ArfSignRunning").fg == (background == "dark" and 0x8daed1 or 0x3f668d))
	arf.setup({ theme = "neon" })
	local neon = {}
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^Arf") then
			neon[name] = get(name, true)
			assert(neon[name].fg and not neon[name].link, name .. " has a fixed neon color")
		end
	end
	assert(neon.ArfElapsed.fg == (background == "dark" and 0x38e8ff or 0x007f99))
	assert(neon.ArfElapsedStale.fg ~= neon.ArfElapsed.fg, "neon dims elapsed time")
	assert(neon.ArfFloatNormal.bg == (background == "dark" and 0x1b102b or 0xf5ecff))
	assert(neon.ArfFloatTitle.fg == neon.ArfFloatBorder.fg, "neon titles match the pink border")
	assert(neon.ArfSignRunning.fg ~= neon.ArfSignSuccess.fg, "running and success remain distinct")
	assert(vim.deep_equal(get("Normal"), original_normal), "neon leaves editor colors unchanged")
	clear_defaults()
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	for name, definition in pairs(neon) do
		local restored = get(name, true)
		assert(
			restored.fg == definition.fg and restored.bg == definition.bg and not restored.link,
			"restore neon after colorscheme changes: " .. name
		)
	end
	arf.setup({ theme = "default" })
	assert(get("ArfFloatNormal").bg == (background == "dark" and 0x262626 or 0xf5f5f5))
	assert(get("ArfOutputStale").fg ~= get("ArfOutput").fg, "default stale output is distinct")
	assert(get("ArfFloatOutputStale").fg ~= get("ArfFloatOutput").fg, "default stale float is distinct")
	arf.setup({ theme = "auto" })
	assert(get("ArfFloatNormal", true).link == "NormalFloat", "restore auto float background")
	assert(get("ArfSignRunning", true).link == "DiagnosticInfo", "restore auto status color")
end
vim.o.background = "dark"
arf.setup({ theme = "default" })
local previous_border = get("ArfFloatBorder", true)
arf.setup({ theme = "neon" })
vim.api.nvim_set_hl(0, "ArfFloatBorder", previous_border)
arf.setup({ theme = "auto" })
assert(
	vim.deep_equal(get("ArfFloatBorder", true), previous_border),
	"an explicit color matching an older theme remains a user override"
)
vim.api.nvim_set_hl(0, "ArfFloatBorder", { fg = 0x123456 })
arf.setup({ theme = "default" })
assert(get("ArfFloatBorder").fg == 0x123456, "theme switching preserves custom highlights")
arf.setup({ theme = "neon" })
assert(get("ArfFloatBorder").fg == 0x123456, "neon preserves custom highlights")
arf.setup({ theme = "auto" })
assert(get("ArfFloatBorder").fg == 0x123456, "returning to auto preserves custom highlights")
vim.api.nvim_set_hl(0, "ArfElapsed", { fg = 0x123456 })
vim.api.nvim_set_hl(0, "ArfElapsedStale", { fg = 0x654321 })
for _, theme in ipairs({ "default", "neon", "auto" }) do
	arf.setup({ theme = theme })
	assert(get("ArfElapsed").fg == 0x123456, "preserve custom timing color")
	assert(get("ArfElapsedStale").fg == 0x654321, "preserve custom stale timing color")
end
-- OptionSet is suppressed during startup (-l). Run after startup in a child
-- editor to test actual :set background changes, without synthesizing events.
local background_test = [[
vim.schedule(function()
  local ok, err = pcall(function()
    vim.opt.rtp:prepend(vim.fn.getcwd())
    local arf = require("arf")
    local function bg()
      return vim.api.nvim_get_hl(0, { name = "ArfFloatNormal", link = false }).bg
    end
    for _, case in ipairs({
      { theme = "default", dark = 0x262626, light = 0xf5f5f5 },
      { theme = "neon", dark = 0x1b102b, light = 0xf5ecff },
    }) do
      vim.o.background = "dark"
      arf.setup({ theme = case.theme })
      vim.api.nvim_set_hl(0, "ArfFloatTitle", { fg = 0x123456 })
      vim.cmd("set background=light")
      assert(bg() == case.light, case.theme .. " follows light background")
      vim.cmd("set background=dark")
      assert(bg() == case.dark, case.theme .. " follows dark background")
      assert(vim.api.nvim_get_hl(0, { name = "ArfFloatTitle" }).fg == 0x123456,
        "background changes preserve custom highlights")
    end
  end)
  if not ok then
    print(err)
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end)
]]
local background_result = vim.system({
	vim.v.progpath,
	"--headless",
	"-u",
	"NONE",
	"-i",
	"NONE",
	"-c",
	"lua " .. background_test,
}, { text = true }):wait(10000)
assert(background_result.code == 0, background_result.stdout .. background_result.stderr)
print("highlight tests passed")
