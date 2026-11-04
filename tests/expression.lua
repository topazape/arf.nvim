-- Run with: nvim --headless -u NONE -l tests/expression.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local expression = require("arf.expression")
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local get_parser = vim.treesitter.get_parser
vim.treesitter.get_parser = function()
	error("missing parser")
end
local value, err = expression.current(0)
check(value == nil and err:find("parser"), "missing parser is reported")
vim.treesitter.get_parser = function()
	return {
		parse = function()
			error("parse failure")
		end,
	}
end
value, err = expression.all(0)
check(value == nil and err:find("syntax tree"), "parser failure is reported")
-- Supply syntax trees directly so selection tests need no installed grammar.
local function node(kind, range, children, rhs)
	return {
		type = function()
			return kind
		end,
		named = function()
			return kind ~= ";"
		end,
		range = function()
			return unpack(range)
		end,
		field = function()
			return rhs or {}
		end,
		has_error = function()
			return false
		end,
		iter_children = function()
			local index = 0
			return function()
				index = index + 1
				return (children or {})[index]
			end
		end,
	}
end
local root
vim.treesitter.get_parser = function()
	return {
		parse = function()
			return { {
				root = function()
					return root
				end,
			} }
		end,
	}
end
local get_text = vim.treesitter.get_node_text
vim.treesitter.get_node_text = function(tree, buf)
	local sr, sc, er, ec = tree:range()
	return table.concat(vim.api.nvim_buf_get_text(buf, sr, sc, er, ec, {}), "\n")
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"# comment",
	"  x <- 1  ",
	"",
	"x |>",
	"  mean()",
	"x; y # note",
})
local assignment = node("binary_operator", { 1, 2, 1, 8 })
local pipeline = node("binary_operator", { 3, 0, 4, 8 })
root = node("program", { 0, 0, 6, 0 }, {
	node("comment", { 0, 0, 0, 9 }),
	assignment,
	pipeline,
	node("identifier", { 5, 0, 5, 1 }),
	node(";", { 5, 1, 5, 2 }),
	node("identifier", { 5, 3, 5, 4 }),
	node("comment", { 5, 5, 5, 11 }),
})
local all = assert(expression.all(0))
check(#all == 4, "exclude comments, blank lines and punctuation")
check(
	all[2].code == "x |>\n  mean()" and all[2].first == 4 and all[2].last == 5,
	"retain full multiline expression and inclusive range"
)
for _, case in ipairs({ { 2, 0, 1 }, { 2, 9, 1 }, { 4, 2, 2 }, { 5, 4, 2 }, { 6, 0, 3 }, { 6, 3, 4 } }) do
	vim.api.nvim_win_set_cursor(0, { case[1], case[2] })
	check(vim.deep_equal(expression.current(0), all[case[3]]), "select expression at cursor or adjacent whitespace")
end
for _, pos in ipairs({ { 1, 2 }, { 3, 0 }, { 6, 1 }, { 6, 7 } }) do
	vim.api.nvim_win_set_cursor(0, pos)
	check(expression.current(0) == nil, "exclude comments, blank lines and semicolons")
end
for _, kind in ipairs({ "extract_operator", "namespace_operator" }) do
	root = node("program", {}, { node("binary_operator", {}, { node(kind, {}) }) })
	check(expression.all(0) == nil and expression.current(0) == nil, "reject nested unfinished " .. kind)
	root = node("program", {}, { node(kind, { 5, 0, 5, 1 }, {}, { assignment }) })
	check(#assert(expression.all(0)) == 1, "accept completed " .. kind)
end
root = node("program", {}, {})
check(#assert(expression.all(0)) == 0, "empty tree has no expressions")
root.has_error = function()
	return true
end
check(expression.all(0) == nil, "reject syntax errors before selecting fragments")
vim.treesitter.get_node_text = get_text
vim.treesitter.get_parser = get_parser
print("expression unit tests passed (" .. checks .. " checks)")
