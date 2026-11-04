vim.opt.rtp:prepend(vim.fn.getcwd())
local config = require("arf.config")
local defaults = vim.deepcopy(config.get())
local help = table.concat(vim.fn.readfile("doc/arf.txt"), "\n")
local start = assert(help:find("*arf-configuration*", 1, true))
local code = assert(help:sub(start):match(">lua\n(.-)\n<"))
local captured
local chunk = assert(loadstring(code, "@doc/arf.txt"))
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
assert(vim.deep_equal(captured, defaults), "help must document every current default")
config.setup(captured)

for _, path in ipairs({ "README.md", "README.ja.md" }) do
	local text = table.concat(vim.fn.readfile(path), "\n")
	for example in text:gmatch("```lua\n(.-)\n```") do
		local env = {}
		local run = assert(loadstring(example, "@" .. path))
		local spec = setfenv(run, env)()
		local opts = spec and spec.opts or env.opts
		assert(type(opts) == "table", "README Lua examples must contain plugin options")
		config.setup(opts)
	end
end
print("documented defaults and README examples are valid")
