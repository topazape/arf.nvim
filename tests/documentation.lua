vim.opt.rtp:prepend(vim.fn.getcwd())
local defaults = vim.deepcopy(require("arf.config").get())
for _, path in ipairs({ "README.md", "README.ja.md", "doc/arf.txt" }) do
	local text = table.concat(vim.fn.readfile(path), "\n")
	local code
	if path:match("%.md$") then
		local start = assert(text:find("## Configuration", 1, true))
		code = assert(text:sub(start):match("```lua\n(.-)\n```"))
	else
		code = assert(text:match(">lua\n(.-)\n<"))
	end
	local captured
	local chunk = assert(loadstring(code, "@" .. path))
	setfenv(chunk, {
		require = function(name)
			assert(name == "arf")
			return {
				setup = function(opts)
					captured = opts
				end,
			}
		end,
	})()
	assert(vim.deep_equal(captured, defaults), path .. " must document every current default")
	require("arf.config").setup(captured)
end
print("documented defaults match configuration")
