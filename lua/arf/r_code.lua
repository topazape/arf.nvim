local M = {}

-- Generate capture code from resolved evaluation options; no editor state is read here.
function M.capture(source, config, dir)
	local tibble_width = config.output.tibble.width
	assert(tibble_width ~= "auto", "arf: resolve tibble width before generating R code")
	return string.format(
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
  .arf_tibble_rows <- %s
  .arf_tibble_width <- %s
  .arf_options <- list()
  .arf_previous_options <- NULL
  tryCatch({
    if (!is.null(.arf_tibble_rows)) {
      .arf_options$pillar.print_max <- .arf_tibble_rows
      .arf_options$pillar.print_min <- .arf_tibble_rows
    }
    if (!is.null(.arf_tibble_width)) {
      .arf_options$pillar.width <- .arf_tibble_width
      # pillar uses width for each tier and pillar.width for the total width.
      # Keep finite widths in one tier. R restricts width to 10..10000.
      if (is.finite(.arf_tibble_width)) .arf_options$width <- max(10, min(10000, .arf_tibble_width))
    }
    if (length(.arf_options)) .arf_previous_options <- options(.arf_options)
    grDevices::png(%s, width = %d, height = %d, units = "px", res = %d)
    .arf_device <- grDevices::dev.cur()
    withCallingHandlers({
      for (.arf_expr in parse(text = %s)) {
        .arf_value <- withVisible(eval(.arf_expr, envir = .GlobalEnv))
        if (.arf_value$visible) print(.arf_value$value)
      }
    }, message = .arf_record_message)
  }, finally = {
    if (!is.null(.arf_previous_options)) options(.arf_previous_options)
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
		config.output.max_bytes,
		vim.json.encode(dir .. "/truncated"),
		vim.json.encode(dir .. "/stdout.bin"),
		vim.json.encode(dir .. "/stderr.bin"),
		vim.json.encode(dir .. "/messages.bin"),
		config.output.tibble.max_rows and tostring(config.output.tibble.max_rows) or "NULL",
		tibble_width == "all" and "Inf" or (tibble_width and tostring(tibble_width) or "NULL"),
		vim.json.encode(dir .. "/plot-%09d.png"),
		config.image.render.width_px,
		config.image.render.height_px,
		config.image.render.dpi,
		vim.json.encode(source)
	)
end

return M
