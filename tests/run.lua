-- Run all suites in separate Neovim processes to isolate module/process mocks:
-- nvim --headless -u NONE -l tests/run.lua
local unit = vim.env.ARF_TEST_MODE == "unit"
local strict = vim.env.ARF_TEST_STRICT == "1"
assert(not (unit and strict), "Unit mode cannot require integration tests")
if strict then
	for _, executable in ipairs({ "R", "Rscript", "arf" }) do
		assert(vim.fn.executable(executable) == 1, "Missing integration dependency: " .. executable)
	end
	assert(vim.env.ARF_TEST_SNACKS, "ARF_TEST_SNACKS must identify the pinned Snacks checkout")
end
local suites = {
	"run_all",
	"inspect",
	"output",
	"results",
	"session",
	"executor",
	"expression",
	"display",
	"snacks",
	"plots",
	"plot_capture",
	"config",
	"commands",
	"float",
	"signs",
	"integration",
}
if unit then
	local integration = { snacks = true, plot_capture = true, integration = true }
	suites = vim.tbl_filter(function(name)
		return not integration[name]
	end, suites)
end
local failed = {}
for _, name in ipairs(suites) do
	local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", "tests/" .. name .. ".lua" }, {
		text = true,
		env = { NVIM_LOG_FILE = vim.fn.tempname() },
	}):wait(60000)
	print("[" .. name .. "]\n" .. result.stdout .. result.stderr)
	if result.code ~= 0 or (strict and (result.stdout .. result.stderr):find("skipped", 1, true)) then
		failed[#failed + 1] = name
	end
end
assert(#failed == 0, "Failed suites: " .. table.concat(failed, ", "))
print("All " .. #suites .. " suites passed")
