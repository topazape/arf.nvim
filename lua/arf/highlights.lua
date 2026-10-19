local M = {}

local function output_color()
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local fg = normal.fg or (vim.o.background == "dark" and 0xffffff or 0x202020)
	-- Keep Normal's hue, reducing each RGB component by 15%.
	local red = math.floor(math.floor(fg / 0x10000) * 0.85)
	local green = math.floor((math.floor(fg / 0x100) % 0x100) * 0.85)
	local blue = math.floor((fg % 0x100) * 0.85)
	return red * 0x10000 + green * 0x100 + blue
end

function M.apply()
	-- Defaults leave definitions supplied by a colorscheme or user intact.
	vim.api.nvim_set_hl(0, "ArfOutput", { default = true, fg = output_color() })
	vim.api.nvim_set_hl(0, "ArfSeparator", { default = true, link = "NonText" })
	vim.api.nvim_set_hl(0, "ArfFloatNormal", { default = true, link = "NormalFloat" })
	vim.api.nvim_set_hl(0, "ArfFloatBorder", { default = true, link = "FloatBorder" })
	vim.api.nvim_set_hl(0, "ArfFloatTitle", { default = true, link = "FloatTitle" })
	vim.api.nvim_set_hl(0, "ArfMessage", { default = true, link = "DiagnosticInfo" })
	vim.api.nvim_set_hl(0, "ArfStderr", { default = true, link = "DiagnosticWarn" })
	vim.api.nvim_set_hl(0, "ArfSignRunning", { default = true, link = "DiagnosticInfo" })
	vim.api.nvim_set_hl(0, "ArfError", { default = true, link = "DiagnosticError" })
	vim.api.nvim_set_hl(0, "ArfWarning", { default = true, link = "DiagnosticWarn" })
	vim.api.nvim_set_hl(0, "ArfSignRange", { default = true, link = "ArfOutput" })
	vim.api.nvim_set_hl(0, "ArfSignSuccess", { default = true, link = "DiagnosticOk" })
	vim.api.nvim_set_hl(0, "ArfSignError", { default = true, link = "DiagnosticError" })
end

M.apply()
local group = vim.api.nvim_create_augroup("arf.highlights", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.apply })

return M
