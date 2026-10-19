local M = {}

-- Read a name rather than evaluate arbitrary code from the source buffer.
-- Include dots independently of the user's 'iskeyword' setting.
function M.object()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local from = 1
	while true do
		local first, last = line:find("[%a_.][%w_.]*", from)
		if not first then
			return
		end
		if first <= col and col <= last then
			return line:sub(first, last)
		end
		from = last + 1
	end
end

local function identifier(name)
	return name:match("^[A-Za-z.][A-Za-z0-9._]*$") and not name:match("^%.%d")
end

function M.code(fn, name)
	if type(fn) ~= "string" then
		return nil, "inspect expects an R function name or package::function"
	end
	local package_name, function_name = fn:match("^([^:]+)::([^:]+)$")
	function_name = function_name or fn
	if
		not identifier(function_name)
		or (package_name and not package_name:match("^[A-Za-z][A-Za-z0-9.]*$"))
	then
		return nil, "inspect expects an R function name or package::function, not an R expression"
	end
	-- Resolve names as data: never parse or interpolate user-supplied R code.
	local callable
	if package_name then
		callable = string.format(
			"base::getExportedValue(%s, %s)",
			vim.json.encode(package_name),
			vim.json.encode(function_name)
		)
	else
		callable = string.format(
			'base::get(%s, envir = .GlobalEnv, mode = "function", inherits = TRUE)',
			vim.json.encode(function_name)
		)
	end
	return string.format("%s(base::get(%s, envir = .GlobalEnv, inherits = TRUE))", callable, vim.json.encode(name))
end

function M.show(title, result, owner)
	local config = require("arf").config
	require("arf.float").open(title, require("arf.output").full_lines(result), {
		width = config.summary_width,
		max_height = config.summary_max_height,
		owner = owner,
	})
end

return M
