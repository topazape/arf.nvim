local M = {}

local function incomplete(node)
	-- The R grammar intentionally accepts trailing $/@/::/::: for completion.
	local kind = node:type()
	if (kind == "extract_operator" or kind == "namespace_operator") and #node:field("rhs") == 0 then
		return true
	end
	for child in node:iter_children() do
		if incomplete(child) then
			return true
		end
	end
	return false
end

local function syntax_root(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, "r")
	if not ok or not parser then
		return nil, "An R Tree-sitter parser is required. Install it or select lines to execute in Visual mode"
	end
	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees or not trees[1] then
		return nil, "Unable to obtain the R syntax tree"
	end
	local root = trees[1]:root()
	-- Recovery can turn an unfinished assignment into a valid-looking fragment.
	-- Refuse automatic selection until the whole buffer parses successfully.
	if root:has_error() or incomplete(root) then
		return nil, "The R code contains an incomplete expression or a syntax error"
	end
	return root
end

local function expression(node, buf)
	local sr, _, er, ec = node:range()
	return { first = sr + 1, last = ec == 0 and er or er + 1, code = vim.treesitter.get_node_text(node, buf) }
end

function M.all(buf)
	local root, err = syntax_root(buf)
	if not root then
		return nil, err
	end
	local expressions = {}
	for node in root:iter_children() do
		if node:named() and node:type() ~= "comment" then
			expressions[#expressions + 1] = expression(node, buf)
		end
	end
	return expressions
end

function M.current(buf)
	local root, err = syntax_root(buf)
	if not root then
		return nil, err
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	for node in root:iter_children() do
		if node:named() and node:type() ~= "comment" then
			local sr, sc, er, ec = node:range()
			local contains = (row > sr or row == sr and col >= sc) and (row < er or row == er and col < ec)
			-- Leading indentation and trailing whitespace on an expression's line
			-- count as that expression, but comments/semicolons do not.
			local before = row == sr and col < sc and line:sub(col + 1, sc):match("^%s*$")
			local after = row == er and col >= ec and line:sub(ec + 1, col + 1):match("^%s*$")
			if contains or before or after then
				return {
					first = sr + 1,
					last = ec == 0 and er or er + 1,
					code = vim.treesitter.get_node_text(node, buf),
				}
			end
		end
	end
	return nil, "No executable R expression at the cursor position"
end

return M
