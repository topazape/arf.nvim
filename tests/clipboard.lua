vim.opt.rtp:prepend(vim.fn.getcwd())
local clipboard = require("arf.clipboard")
local path = vim.fn.tempname() .. " quote' space.png"
local data = "\137PNG\r\n\26\n\0test"
local file = assert(io.open(path, "wb"))
assert(file:write(data))
file:close()
local system, available, called, message, pending = "Darwin", {}, nil, nil, nil
vim.uv.os_uname = function()
	return { sysname = system }
end
vim.fn.executable = function(name)
	return available[name] and 1 or 0
end
vim.notify = function(text)
	message = text
end
vim.system = function(args, opts, callback)
	called = { args = args, opts = opts }
	pending = callback
end
local function finish(code)
	pending({ code = code or 0, stderr = "failure" })
	vim.wait(1000, function()
		return message ~= nil
	end)
end
available.osascript = true
clipboard.copy(path)
local snapshot = called.args[#called.args]
assert(snapshot ~= path and vim.fn.filereadable(snapshot) == 1)
local copied = assert(io.open(snapshot, "rb"))
assert(copied:read("*a") == data)
copied:close()
finish()
assert(message:find("Plot copied", 1, true))
assert(vim.fn.filereadable(snapshot) == 0)
system = "Linux"
vim.env.WAYLAND_DISPLAY = "wayland-0"
available = { ["wl-copy"] = true, xclip = true }
message = nil
clipboard.copy(path)
assert(called.args[1] == "wl-copy" and called.opts.stdin == data)
finish(1)
assert(message:find("failure", 1, true))
vim.env.WAYLAND_DISPLAY = nil
clipboard.copy(path)
assert(called.args[1] == "xclip" and called.opts.stdin == data)
available = {}
clipboard.copy(path)
assert(message:find("requires wl-copy", 1, true))
system = "Windows_NT"
available = { ["powershell.exe"] = true }
message = nil
clipboard.copy(path)
assert(called.args[1] == "powershell.exe")
snapshot = called.opts.env.ARF_COPY_PLOT
assert(vim.fn.filereadable(snapshot) == 1)
finish()
assert(vim.fn.filereadable(snapshot) == 0)
vim.system = function()
	error("spawn failed")
end
clipboard.copy(path)
assert(message:find("spawn failed", 1, true))
clipboard.copy(path .. "missing")
assert(message:find("Unable to read", 1, true))
vim.fn.delete(path)
print("clipboard tests passed")
