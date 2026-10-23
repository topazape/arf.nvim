local M = {}
local theme = "default"
local managed = {}

local function set_default(name, definition)
	local current = vim.api.nvim_get_hl(0, { name = name, link = true })
	local owned = managed[name] and vim.deep_equal(current, managed[name])
	if not owned and not vim.tbl_isempty(current) then
		-- A user or colorscheme supplied this definition; leave it alone.
		managed[name] = nil
		return
	end
	-- Do not register :highlight-default values: :highlight clear should clear
	-- our definitions instead of restoring colors from a previous theme.
	vim.api.nvim_set_hl(0, name, definition)
	managed[name] = vim.api.nvim_get_hl(0, { name = name, link = true })
end

local function blend(fg, bg, alpha)
	local color = 0
	for _, shift in ipairs({ 16, 8, 0 }) do
		local divisor = 2 ^ shift
		local front = math.floor(fg / divisor) % 256
		local back = math.floor(bg / divisor) % 256
		color = color + math.floor(front * alpha + back * (1 - alpha) + 0.5) * divisor
	end
	return color
end

local function blended_default(name, source, alpha, fallback)
	local hl = vim.api.nvim_get_hl(0, { name = source, link = false })
	if hl.fg and hl.bg then
		set_default(name, { fg = blend(hl.fg, hl.bg, alpha) })
	else
		-- Transparent backgrounds and terminal colors cannot be blended as RGB.
		set_default(name, { link = fallback or source })
	end
end

local function default_palette()
	local dark = vim.o.background == "dark"
	return dark
			and {
				fg = 0xc8c8c8,
				output = 0xb8b8b8,
				separator = 0x484848,
				float_bg = 0x262626,
				float_fg = 0xdedede,
				border = 0x777777,
				title = 0xd2d2d2,
				info = 0x8daed1,
				success = 0x91b394,
				error = 0xd28b8b,
				warning = 0xc5ac7a,
			}
		or {
			fg = 0x303030,
			output = 0x505050,
			separator = 0xc6c6c6,
			float_bg = 0xf5f5f5,
			float_fg = 0x303030,
			border = 0x888888,
			title = 0x404040,
			info = 0x3f668d,
			success = 0x47734c,
			error = 0xa14f4f,
			warning = 0x876821,
		}
end

local function neon_palette()
	if vim.o.background == "dark" then
		return {
			fg = 0xe9ddff,
			output = 0xd5bfff,
			separator = 0x7546a3,
			float_bg = 0x1b102b,
			float_fg = 0xf0e5ff,
			border = 0xff4fcd,
			title = 0xff4fcd,
			info = 0x38e8ff,
			success = 0xb8f54a,
			error = 0xff4f87,
			warning = 0xffdc4a,
		}
	end
	return {
		fg = 0x392052,
		output = 0x66339a,
		separator = 0xb38bd9,
		float_bg = 0xf5ecff,
		float_fg = 0x392052,
		border = 0xc51893,
		title = 0xc51893,
		info = 0x007f99,
		success = 0x4d7800,
		error = 0xc51b55,
		warning = 0x926600,
	}
end

local function apply_palette(palette)
	local definitions = {
		ArfOutput = { fg = palette.output },
		ArfOutputStale = { fg = blend(palette.output, palette.float_bg, 0.55) },
		ArfSeparator = { fg = palette.separator },
		ArfMessage = { fg = palette.info },
		ArfStderr = { fg = palette.warning },
		ArfError = { fg = palette.error },
		ArfWarning = { fg = palette.warning },
		ArfFloatNormal = { fg = palette.fg, bg = palette.float_bg },
		ArfFloatOutput = { fg = palette.float_fg, bg = palette.float_bg },
		ArfFloatOutputStale = { fg = blend(palette.float_fg, palette.float_bg, 0.55), bg = palette.float_bg },
		ArfFloatMessage = { fg = palette.info, bg = palette.float_bg },
		ArfFloatStderr = { fg = palette.warning, bg = palette.float_bg },
		ArfFloatError = { fg = palette.error, bg = palette.float_bg },
		ArfFloatWarning = { fg = palette.warning, bg = palette.float_bg },
		ArfFloatEmpty = { fg = palette.output, bg = palette.float_bg },
		ArfFloatBorder = { fg = palette.border, bg = palette.float_bg },
		ArfFloatTitle = { fg = palette.title or palette.info, bg = palette.float_bg },
		ArfSignRange = { fg = palette.separator },
		ArfSignRunning = { fg = palette.info },
		ArfSignSuccess = { fg = palette.success },
		ArfSignError = { fg = palette.error },
	}
	for name, definition in pairs(definitions) do
		set_default(name, definition)
	end
end

function M.apply(selected_theme)
	if selected_theme then
		theme = selected_theme
	end
	if theme == "default" then
		return apply_palette(default_palette())
	elseif theme == "neon" then
		return apply_palette(neon_palette())
	end
	-- Defaults leave definitions supplied by a colorscheme or user intact.
	blended_default("ArfOutput", "Normal", 0.85)
	blended_default("ArfOutputStale", "Normal", 0.5, "Comment")
	blended_default("ArfSeparator", "Normal", 0.25, "NonText")
	set_default("ArfFloatNormal", { link = "NormalFloat" })
	blended_default("ArfFloatOutput", "ArfFloatNormal", 0.95)
	blended_default("ArfFloatOutputStale", "ArfFloatNormal", 0.5, "Comment")
	local links = {
		ArfFloatBorder = "FloatBorder",
		ArfFloatTitle = "FloatTitle",
		ArfMessage = "DiagnosticInfo",
		ArfStderr = "DiagnosticWarn",
		ArfSignRunning = "DiagnosticInfo",
		ArfError = "DiagnosticError",
		ArfWarning = "DiagnosticWarn",
		ArfFloatMessage = "ArfMessage",
		ArfFloatStderr = "ArfStderr",
		ArfFloatError = "ArfError",
		ArfFloatWarning = "ArfWarning",
		ArfFloatEmpty = "ArfFloatOutput",
		ArfSignRange = "ArfSeparator",
		ArfSignSuccess = "DiagnosticOk",
		ArfSignError = "DiagnosticError",
	}
	for name, target in pairs(links) do
		set_default(name, { link = target })
	end
end

M.apply()
local group = vim.api.nvim_create_augroup("arf.highlights", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
	group = group,
	callback = function()
		M.apply()
	end,
})

vim.api.nvim_create_autocmd("OptionSet", {
	group = group,
	pattern = "background",
	callback = function()
		M.apply()
	end,
})

return M
