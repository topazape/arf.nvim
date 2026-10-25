local M = {}

function M.copy(path)
	local function notify(message, level)
		vim.notify("arf: " .. message, level)
	end
	local system = vim.uv.os_uname().sysname
	local args, script
	if system == "Darwin" then
		args = {
			"osascript",
			"-e",
			"on run argv\nset the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)\nend run",
		}
	elseif system == "Windows_NT" then
		local executable = vim.fn.executable("powershell.exe") == 1 and "powershell.exe" or "pwsh"
		script = [[Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($env.ARF_COPY_PLOT)
try { [System.Windows.Forms.Clipboard]::SetImage($image) } finally { $image.Dispose() }]]
		args = { executable, "-NoProfile", "-NonInteractive", "-STA", "-Command", script }
	elseif system == "Linux" then
		if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-copy") == 1 then
			args = { "wl-copy", "--type", "image/png" }
		elseif vim.fn.executable("xclip") == 1 then
			args = { "xclip", "-selection", "clipboard", "-t", "image/png", "-i" }
		else
			return notify("Image copying requires wl-copy (Wayland) or xclip (X11)", vim.log.levels.ERROR)
		end
	else
		return notify("Image copying is not supported on " .. system, vim.log.levels.ERROR)
	end
	if vim.fn.executable(args[1]) ~= 1 then
		return notify("Image copying requires " .. args[1], vim.log.levels.ERROR)
	end
	local file, err = io.open(path, "rb")
	if not file then
		return notify("Unable to read plot: " .. tostring(err), vim.log.levels.ERROR)
	end
	local data = file:read("*a")
	file:close()
	local opts = {}
	local snapshot
	if system == "Linux" then
		opts.stdin = data
	else
		-- Results can be cleared while the clipboard process is starting.
		snapshot = vim.fn.tempname() .. ".png"
		local saved, save_error = io.open(snapshot, "wb")
		if not saved then
			return notify("Unable to save plot: " .. tostring(save_error), vim.log.levels.ERROR)
		end
		local written, write_error = saved:write(data)
		saved:close()
		if not written then
			vim.fn.delete(snapshot)
			return notify("Unable to save plot: " .. tostring(write_error), vim.log.levels.ERROR)
		end
		if system == "Darwin" then
			args[#args + 1] = snapshot
		else
			opts.env = { ARF_COPY_PLOT = snapshot }
		end
	end
	local function done(result)
		if snapshot then
			vim.fn.delete(snapshot)
		end
		if result.code == 0 then
			notify("Plot copied to clipboard", vim.log.levels.INFO)
		else
			notify("Unable to copy plot: " .. (result.stderr or tostring(result.code)), vim.log.levels.ERROR)
		end
	end
	local ok, process = pcall(vim.system, args, opts, vim.schedule_wrap(done))
	if not ok then
		done({ code = -1, stderr = tostring(process) })
	end
end

return M
