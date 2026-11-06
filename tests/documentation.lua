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
	local documented_defaults = false
	for example in text:gmatch("```lua\n(.-)\n```") do
		local env = {}
		env.require = function(name)
			assert(name == "arf")
			return {
				setup = function(opts)
					assert(vim.deep_equal(opts, defaults), path .. " must document every current default")
					documented_defaults = true
					env.opts = opts
				end,
			}
		end
		local run = assert(loadstring(example, "@" .. path))
		local spec = setfenv(run, env)()
		local opts = spec and spec.opts or env.opts
		assert(type(opts) == "table", "README Lua examples must contain plugin options")
		config.setup(opts)
	end
	assert(documented_defaults, path .. " must include a complete defaults example")
	for target in text:gmatch("%]%(([^%)]+)%)") do
		if not target:match("^%a+:") and target:sub(1, 1) ~= "#" then
			local file = target:match("^[^#]+")
			assert(vim.fn.filereadable(file) == 1, path .. " links to missing file: " .. file)
		end
	end
	for source in text:gmatch('<img[^>]+src="([^"]+)"') do
		assert(vim.fn.filereadable(source) == 1, path .. " references missing image: " .. source)
	end
end
local tags = {}
for tag in help:gmatch("%*([^%s*]+)%*") do
	assert(not tags[tag], "duplicate help tag: " .. tag)
	tags[tag] = true
end
for target in help:gmatch("|([^|%s]+)|") do
	assert(tags[target], "missing help tag: " .. target)
end
print("documented defaults and README examples are valid")
