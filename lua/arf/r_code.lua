local M = {}

-- Generate capture code from resolved evaluation options; no editor state is read here.
-- Qualify internal functions while retaining global S3 method dispatch.
function M.capture(source, config, dir)
	local tibble_width = config.output.tibble.width
	assert(tibble_width ~= "auto", "arf: resolve tibble width before generating R code")
	return string.format(
		[[
base::evalq({
  .arf_limit <- %d
  .arf_truncated_path <- %s
  .arf_stdout_path <- %s
  .arf_stdout <- base::file(.arf_stdout_path, open = "w+b")
  .arf_stdout_depth <- base::sink.number(type = "output")
  .arf_stderr_path <- %s
  .arf_stderr <- base::file(.arf_stderr_path, open = "w+b")
  .arf_previous_stderr <- base::getConnection(base::sink.number(type = "message"))
  .arf_device <- NULL
  .arf_message_written <- 0
  .arf_record_message <- function(.arf_condition) {
    .arf_offset <- base::seek(.arf_stderr, where = NA, rw = "write")
    if (.arf_offset >= .arf_limit || .arf_message_written >= .arf_limit) return(base::invisible(NULL))
    .arf_bytes <- base::charToRaw(base::enc2utf8(base::conditionMessage(.arf_condition)))
    if (base::length(.arf_bytes) + 8 > .arf_limit - .arf_message_written) return(base::invisible(NULL))
    .arf_message_written <<- .arf_message_written + base::length(.arf_bytes) + 8
    .arf_connection <- base::file(%s, open = "ab")
    base::tryCatch({
      base::writeBin(base::as.integer(.arf_offset), .arf_connection, size = 4L, endian = "big")
      base::writeBin(base::as.integer(base::length(.arf_bytes)), .arf_connection, size = 4L, endian = "big")
      base::writeBin(.arf_bytes, .arf_connection)
    }, finally = base::close(.arf_connection))
  }
  base::sink(.arf_stdout, type = "output")
  base::sink(.arf_stderr, type = "message")
  .arf_tibble_rows <- %s
  .arf_tibble_width <- %s
  .arf_options <- base::list()
  .arf_previous_options <- NULL
  base::tryCatch({
    if (!base::is.null(.arf_tibble_rows)) {
      .arf_options$pillar.print_max <- .arf_tibble_rows
      .arf_options$pillar.print_min <- .arf_tibble_rows
    }
    if (!base::is.null(.arf_tibble_width)) {
      .arf_options$pillar.width <- .arf_tibble_width
      # pillar uses width for each tier and pillar.width for the total width.
      # Keep finite widths in one tier. R restricts width to 10..10000.
      if (base::is.finite(.arf_tibble_width)) .arf_options$width <- base::max(10, base::min(10000, .arf_tibble_width))
    }
    if (base::length(.arf_options)) .arf_previous_options <- base::options(.arf_options)
    grDevices::png(%s, width = %d, height = %d, units = "px", res = %d)
    .arf_device <- grDevices::dev.cur()
    base::withCallingHandlers({
      for (.arf_expr in base::parse(text = %s)) {
        .arf_value <- base::withVisible(base::eval(.arf_expr, envir = .GlobalEnv))
        if (.arf_value$visible) base::print(.arf_value$value)
      }
    }, message = .arf_record_message)
  }, finally = {
    if (!base::is.null(.arf_previous_options)) base::options(.arf_previous_options)
    base::tryCatch({
      if (!base::is.null(.arf_device) && .arf_device %%in%% grDevices::dev.list()) grDevices::dev.off(.arf_device)
    }, finally = {
      base::sink(.arf_previous_stderr, type = "message")
      while (base::sink.number(type = "output") > .arf_stdout_depth) base::sink(type = "output")
      base::flush(.arf_stdout)
      base::flush(.arf_stderr)
      .arf_stdout_size <- base::file.info(.arf_stdout_path)$size
      .arf_stderr_size <- base::file.info(.arf_stderr_path)$size
      if (.arf_stdout_size + .arf_stderr_size > .arf_limit) base::writeLines("1", .arf_truncated_path)
      .arf_read <- function(.arf_con, .arf_n) {
        base::seek(.arf_con, where = 0, origin = "start", rw = "read")
        .arf_bytes <- base::readBin(.arf_con, what = "raw", n = .arf_n)
        base::close(.arf_con)
        base::iconv(base::rawToChar(.arf_bytes), from = "UTF-8", to = "UTF-8", sub = "")
      }
      .arf_take <- base::min(.arf_limit, .arf_stdout_size)
      base::cat(.arf_read(.arf_stdout, .arf_take))
      base::cat(.arf_read(.arf_stderr, base::min(.arf_limit - .arf_take, .arf_stderr_size)), file = base::stderr())
    })
  })
  base::invisible(NULL)
}, envir = base::new.env(parent = .GlobalEnv))]],
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
