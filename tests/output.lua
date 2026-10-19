-- Run with: nvim --headless -u NONE -l tests/output.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local output = require("arf.output")
local checks = 0
local function eq(actual, expected, message)
	checks = checks + 1
	assert(vim.deep_equal(actual, expected), message .. "\nactual: " .. vim.inspect(actual))
end

-- Every byte boundary, including inside Japanese characters and emoji.
local text = "a日本😀z"
for budget = 0, #text + 1 do
	local expected = ""
	for _, prefix in ipairs({ "a", "a日", "a日本", "a日本😀", text }) do
		if #prefix <= budget then
			expected = prefix
		end
	end
	local result = output.limit({ text = text }, budget)
	eq(result.text, expected, "UTF-8 prefix at budget " .. budget)
	eq(result.truncated == true, budget < #text, "truncation at budget " .. budget)
end
local result = output.limit(
	{
		text = "abcdef",
		chunks = {
			{ text = "abc", highlight = "ArfOutput" },
			{ text = "def", highlight = "ArfStderr" },
		},
		error = "日本",
	},
	9
)
eq(result.text, "abcdef", "retain stdout and stderr")
eq(result.error, "日", "error shares the byte budget")
eq(result.truncated, true, "error truncation is reported")
eq(result.chunks[2].highlight, "ArfStderr", "retain chunk highlights")
result = output.limit(
	{
		text = "日x",
		chunks = {
			{ text = "日", highlight = "ArfMessage" },
			{ text = "x", highlight = "ArfStderr" },
		},
	},
	2
)
eq(result.text, "", "do not skip a cut character to retain a later chunk")
eq(output.limit({ text = "abc", error = "d" }, 3).error, "", "exhausted budget retains error status")

local decoded, chunks = output.decode("\27[31mout\27[0m\n", "warn\nhello\nend\n", {
	{ offset = 5, text = "hello\n" },
	{ offset = 0, text = "warn\n" }, -- stale/overlapping record
	{ offset = 11, text = "wrong" }, -- unmatched record
})
eq(decoded, "out\nwarn\nhello\nend", "strip ANSI and only the final newline")
eq(chunks, {
	{ text = "out\n", highlight = "ArfOutput" },
	{ text = "warn\n", highlight = "ArfStderr" },
	{ text = "hello\n", highlight = "ArfMessage" },
	{ text = "end", highlight = "ArfStderr" },
}, "classify messages by matching raw offsets")
local lines, total = output.lines(
	{
		text = "a\nb\n\nc",
		chunks = {
			{ text = "a", highlight = "ArfOutput" },
			{ text = "\nb\n", highlight = "ArfMessage" },
			{ text = "\nc", highlight = "ArfStderr" },
		},
	},
	3
)
eq(total, 4, "count lines across chunks")
eq(lines, {
	{ { "a", "ArfOutput" } },
	{ { "b", "ArfMessage" } },
	{ { "", "ArfOutput" } },
}, "preview preserves highlights and blank lines")
eq(output.full_lines({ text = "" }), {}, "empty output")
eq(output.full_lines({ text = "", error = "failed" }), {
	{ { "R error: failed", "ArfError" } },
}, "error-only output")
require("arf").config.output_max_lines = 2
lines = output.preview({ text = "a\nb\nc", truncated = true })
eq(#lines, 4, "notices do not consume preview body limit")
eq(lines[3][1][1], "… 1 more lines (view with :ArfOutput)", "omitted line count")
eq(lines[4][1][2], "ArfWarning", "retention notice")
print("output tests passed (" .. checks .. " checks)")
