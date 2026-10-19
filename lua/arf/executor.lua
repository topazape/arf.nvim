local M = {}
local output = require("arf.output")
local function string_field(reply, key)
	return type(reply[key]) == "string" and reply[key] or ""
end

function M.eval(source, config, callback)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p", 448)
	local function cleanup()
		vim.fn.delete(dir, "rf")
	end
	local code = string.format(
		[[
local({
  .arf_limit <- %d
  .arf_truncated_path <- %s
  .arf_stdout_path <- %s
  .arf_stdout <- file(.arf_stdout_path, open = "w+b")
  .arf_stdout_depth <- sink.number(type = "output")
  .arf_stderr_path <- %s
  .arf_stderr <- file(.arf_stderr_path, open = "w+b")
  .arf_previous_stderr <- getConnection(sink.number(type = "message"))
  .arf_device <- NULL
  .arf_message_written <- 0
  .arf_record_message <- function(.arf_condition) {
    .arf_offset <- seek(.arf_stderr, where = NA, rw = "write")
    if (.arf_offset >= .arf_limit || .arf_message_written >= .arf_limit) return(invisible(NULL))
    .arf_bytes <- charToRaw(enc2utf8(conditionMessage(.arf_condition)))
    if (length(.arf_bytes) + 8 > .arf_limit - .arf_message_written) return(invisible(NULL))
    .arf_message_written <<- .arf_message_written + length(.arf_bytes) + 8
    .arf_connection <- file(%s, open = "ab")
    tryCatch({
      writeBin(as.integer(.arf_offset), .arf_connection, size = 4L, endian = "big")
      writeBin(as.integer(length(.arf_bytes)), .arf_connection, size = 4L, endian = "big")
      writeBin(.arf_bytes, .arf_connection)
    }, finally = close(.arf_connection))
  }
  sink(.arf_stdout, type = "output")
  sink(.arf_stderr, type = "message")
  tryCatch({
    grDevices::png(%s, width = %d, height = %d, units = "px", res = %d)
    .arf_device <- grDevices::dev.cur()
    withCallingHandlers({
      for (.arf_expr in parse(text = %s)) {
        .arf_value <- withVisible(eval(.arf_expr, envir = .GlobalEnv))
        if (.arf_value$visible) print(.arf_value$value)
      }
    }, message = .arf_record_message)
  }, finally = {
    tryCatch({
      if (!is.null(.arf_device) && .arf_device %%in%% grDevices::dev.list()) grDevices::dev.off(.arf_device)
    }, finally = {
      sink(.arf_previous_stderr, type = "message")
      while (sink.number(type = "output") > .arf_stdout_depth) sink(type = "output")
      flush(.arf_stdout)
      flush(.arf_stderr)
      .arf_stdout_size <- file.info(.arf_stdout_path)$size
      .arf_stderr_size <- file.info(.arf_stderr_path)$size
      if (.arf_stdout_size + .arf_stderr_size > .arf_limit) writeLines("1", .arf_truncated_path)
      .arf_read <- function(.arf_con, .arf_n) {
        seek(.arf_con, where = 0, origin = "start", rw = "read")
        .arf_bytes <- readBin(.arf_con, what = "raw", n = .arf_n)
        close(.arf_con)
        iconv(rawToChar(.arf_bytes), from = "UTF-8", to = "UTF-8", sub = "")
      }
      .arf_take <- min(.arf_limit, .arf_stdout_size)
      cat(.arf_read(.arf_stdout, .arf_take))
      cat(.arf_read(.arf_stderr, min(.arf_limit - .arf_take, .arf_stderr_size)), file = stderr())
    })
  })
  invisible(NULL)
})]],
		config.output_max_bytes,
		vim.json.encode(dir .. "/truncated"),
		vim.json.encode(dir .. "/stdout.bin"),
		vim.json.encode(dir .. "/stderr.bin"),
		vim.json.encode(dir .. "/messages.bin"),
		vim.json.encode(dir .. "/plot-%09d.png"),
		config.plot_width,
		config.plot_height,
		config.plot_res,
		vim.json.encode(source)
	)
	local args = { config.executable, "ipc", "eval", "--visible", "--timeout", tostring(config.timeout) }
	if config.pid then
		vim.list_extend(args, { "--pid", tostring(config.pid) })
	end
	-- stdin avoids command-line size limits and shell interpretation.
	local cancelled = false
	local ok, process = pcall(
		vim.system,
		args,
		{ text = true, stdin = code },
		vim.schedule_wrap(function(process)
			if cancelled then
				cleanup()
				return
			end
			if process.code ~= 0 then
				cleanup()
				return callback(
					nil,
					process.stderr ~= "" and process.stderr or "arf IPC failed (" .. process.code .. ")"
				)
			end
			local decoded, reply = pcall(vim.json.decode, process.stdout)
			if not decoded or type(reply) ~= "table" then
				cleanup()
				return callback(nil, "Unable to read the JSON response from arf")
			end
			local text, chunks = output.decode(
				string_field(reply, "stdout"),
				string_field(reply, "stderr"),
				output.read_messages(dir .. "/messages.bin", config.output_max_bytes)
			)
			local files = vim.fn.glob(dir .. "/plot-*.png", false, true)
			table.sort(files)
			callback(output.limit({
				text = text,
				chunks = chunks,
				truncated = vim.uv.fs_stat(dir .. "/truncated") ~= nil,
				paths = files,
				error = type(reply.error) == "string" and reply.error or nil,
				cleanup = cleanup,
			}, config.output_max_bytes))
		end)
	)
	if not ok then
		cleanup()
		callback(nil, tostring(process))
		return
	end
	return function()
		cancelled = true
		process:kill(15)
		cleanup()
	end
end
return M
