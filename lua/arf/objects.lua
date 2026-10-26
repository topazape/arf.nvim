local M = {}

-- Only names and small metadata cross IPC. Hex fields keep arbitrary names,
-- including tabs/newlines, unambiguous without requiring an R JSON package.
M.code = [[
base::local({
  hex <- function(x) base::paste(base::sprintf("%02x", base::as.integer(base::charToRaw(base::enc2utf8(x)))), collapse = "")
  safe <- function(f, fallback) base::tryCatch(base::suppressMessages(base::suppressWarnings(f())), error = function(e) fallback)
  # Discard method output without retaining it in memory or mixing it with rows.
  quiet <- base::file(base::nullfile(), open = "w")
  previous_message <- base::getConnection(base::sink.number(type = "message"))
  base::sink(quiet, type = "message")
  base::tryCatch({
    for (name in base::ls(envir = .GlobalEnv)) {
      cls <- size <- ""
      base::sink(quiet)
      base::tryCatch(safe(function() {
        # Do not trigger active bindings just to populate the picker.
        if (base::bindingIsActive(name, .GlobalEnv)) return(NULL)
        x <- base::get(name, envir = .GlobalEnv, inherits = FALSE)
        cls <<- safe(function() base::paste(base::class(x), collapse = "/"), "")
        size <<- safe(function() {
          d <- base::dim(x)
          if (!base::is.null(d)) base::paste(base::format(d, big.mark = ",", trim = TRUE, scientific = FALSE), collapse = " × ")
          else if (base::is.atomic(x) || base::is.list(x)) base::format(base::length(x), big.mark = ",", trim = TRUE, scientific = FALSE)
          else ""
        }, "")
      }, NULL), finally = base::sink())
      base::cat(hex(name), hex(cls), hex(size), sep = "\t")
      base::cat("\n")
    }
  }, finally = {
    base::sink(previous_message, type = "message")
    base::close(quiet)
  })
  base::invisible(NULL)
})
]]

local function unhex(value)
	assert(#value % 2 == 0 and not value:find("[^%x]"), "invalid metadata field")
	return (value:gsub("%x%x", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end

function M.decode(text)
	local items = {}
	for line in text:gmatch("[^\n]+") do
		local name, class, size = line:match("^(%x*)\t(%x*)\t(%x*)$")
		assert(name and name ~= "", "invalid metadata row")
		name, class, size = unhex(name), unhex(class), unhex(size)
		items[#items + 1] = { name = name, text = name, class = class, size = size }
	end
	return items
end

return M
