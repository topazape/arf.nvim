-- Run with: nvim --headless -u NONE -l tests/expression.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local expression = require("arf.expression")
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function lines(value)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, value)
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
vim.treesitter.get_parser = get_parser
lines({ "x <- 1" })
local all, parser_error = expression.all(0)
if not all then
	assert(parser_error:find("parser"), parser_error)
	print("R parser unavailable; expression integration skipped")
	return
end
lines({ "# comment", "  x <- 1  ", "", "x |>", "  mean()", "f <- function(x) {", "  x + 1", "}" })
all = assert(expression.all(0))
check(#all == 3, "skip comments and blank lines")
for _, case in ipairs({ { 2, 0, 1 }, { 2, 9, 1 }, { 4, 0, 2 }, { 5, 3, 2 }, { 7, 3, 3 }, { 8, 0, 3 } }) do
	vim.api.nvim_win_set_cursor(0, { case[1], case[2] })
	check(
		vim.deep_equal(expression.current(0), all[case[3]]),
		"select whole top-level expression at " .. case[1] .. ":" .. case[2]
	)
end
for _, row in ipairs({ 1, 3 }) do
	vim.api.nvim_win_set_cursor(0, { row, 0 })
	check(expression.current(0) == nil, "comment and blank lines are not executable")
end
lines({ "x <- 1; y <- 2 # comment" })
for _, case in ipairs({ { 0, "x <- 1" }, { 8, "y <- 2" } }) do
	vim.api.nvim_win_set_cursor(0, { 1, case[1] })
	check(assert(expression.current(0)).code == case[2], "select expression on shared line")
end
for _, col in ipairs({ 6, 15, 17 }) do
	vim.api.nvim_win_set_cursor(0, { 1, col })
	check(expression.current(0) == nil, "semicolon and trailing comment excluded")
end
for _, source in ipairs({ "x <- (", "x$", "x@", "base::", "base:::", "f <- function() {", "x <- 1\ny <- (" }) do
	lines(vim.split(source, "\n"))
	check(expression.all(0) == nil and expression.current(0) == nil, "reject incomplete buffer: " .. source)
end
lines({ "# only comment", "" })
check(#assert(expression.all(0)) == 0, "comment-only buffer has no expressions")
print("expression tests passed (" .. checks .. " checks)")
