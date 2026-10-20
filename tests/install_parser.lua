-- Build the pinned grammar fetched by CI; no parser manager is required.
local root = vim.fn.getcwd() .. "/.test-deps/tree-sitter-r"
local target = vim.fn.stdpath("data") .. "/site/parser"
vim.fn.mkdir(target, "p")
local args = { "cc", "-O2", "-fPIC", "-I" .. root .. "/src" }
vim.list_extend(
	args,
	vim.uv.os_uname().sysname == "Darwin" and { "-bundle", "-undefined", "dynamic_lookup" } or { "-shared" }
)
vim.list_extend(args, { root .. "/src/parser.c", root .. "/src/scanner.c", "-o", target .. "/r.so" })
local result = vim.system(args, { text = true }):wait(60000)
assert(result.code == 0, result.stdout .. result.stderr)
vim.treesitter.language.add("r")
print("R parser installed")
