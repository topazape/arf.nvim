-- Run all suites in separate Neovim processes to isolate module/process mocks:
-- nvim --headless -u NONE -l tests/run.lua
local suites = { "run_all", "inspect", "output", "results", "session", "executor", "expression", "display", "snacks" }
local failed = {}
for _, name in ipairs(suites) do
	local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", "tests/" .. name .. ".lua" }, {
		text = true,
		env = { NVIM_LOG_FILE = vim.fn.tempname() },
	}):wait(60000)
	print("[" .. name .. "]\n" .. result.stdout .. result.stderr)
	if result.code ~= 0 then
		failed[#failed + 1] = name
	end
end
assert(#failed == 0, "Failed suites: " .. table.concat(failed, ", "))
print("All " .. #suites .. " suites passed")
