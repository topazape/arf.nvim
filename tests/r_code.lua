-- Resolve editor-dependent "auto" widths before generating capture code.
vim.opt.rtp:prepend(vim.fn.getcwd())
local capture = require("arf.r_code").capture
local defaults = require("arf.config").get()
for _, rows in ipairs({ "inherit", 100 }) do
	for _, width in ipairs({ "inherit", "all", 80 }) do
		local config = vim.tbl_deep_extend("force", defaults, {
			output = { tibble = { max_rows = rows, width = width } },
		})
		local code = capture("1 + 1", config, "/tmp/arf-test")
		local expected_rows = rows == "inherit" and "NULL" or "100"
		local expected_width = width == "inherit" and "NULL" or width == "all" and "Inf" or "80"
		assert(code:find(".arf_tibble_rows <- " .. expected_rows .. "\n", 1, true), "resolve row settings for R")
		assert(code:find(".arf_tibble_width <- " .. expected_width .. "\n", 1, true), "resolve width settings for R")
		assert(not code:find("<- inherit", 1, true), "inherit must never become an R identifier")
	end
end
local ok, err = pcall(capture, "1", defaults, "/tmp/arf-test")
assert(not ok and err:find("resolve tibble width", 1, true), "reject unresolved auto width")
print("R capture settings tests passed")
