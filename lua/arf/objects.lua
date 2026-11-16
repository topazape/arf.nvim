local M = {}

-- Return only plain names and small metadata, compatible with arf's native JSON conversion.
local collect = [=[function(args) {
  if (!base::is.null(args)) base::stop("Object lookup takes no arguments")
  rows <- base::list()
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
      rows[[base::length(rows) + 1L]] <- base::list(name = base::enc2utf8(name), class = base::enc2utf8(cls), size = base::enc2utf8(size))
    }
  }, finally = {
    base::sink(previous_message, type = "message")
    base::close(quiet)
  })
  base::unname(rows)
}
]=]

M.expose = 'base::list("nvim/objects" = ' .. collect .. ")"
-- Borrowed sessions keep the existing evaluation path, using the same collector.
M.code = [[base::evalq({
  hex <- function(x) base::paste(base::sprintf("%02x", base::as.integer(base::charToRaw(base::enc2utf8(x)))), collapse = "")
  for (row in (]] .. collect .. [[)(NULL)) {
    base::cat(hex(row$name), hex(row$class), hex(row$size), sep = "\t")
    base::cat("\n")
  }
  base::invisible(NULL)
}, envir = base::new.env(parent = .GlobalEnv))]]

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

local function native_items(value)
	assert(type(value) == "table" and vim.islist(value), "invalid object list")
	local items = {}
	for _, item in ipairs(value) do
		assert(
			type(item) == "table"
				and type(item.name) == "string"
				and item.name ~= ""
				and type(item.class) == "string"
				and type(item.size) == "string",
			"invalid object metadata"
		)
		items[#items + 1] = { name = item.name, text = item.name, class = item.class, size = item.size }
	end
	return items
end

function M.fetch(config, callback, on_timeout)
	if config.external then
		return require("arf.executor").eval(M.code, config, function(result, err)
			if not result then
				return callback(nil, err)
			end
			local ok, items = pcall(function()
				if result.error or result.truncated then
					error(result.error or "Object list exceeded output.max_bytes", 0)
				end
				return M.decode(result.text)
			end)
			local cleaned, cleanup_error = pcall(result.cleanup)
			if not cleaned then
				return callback(nil, "Object lookup cleanup failed: " .. tostring(cleanup_error))
			end
			if not ok then
				return callback(nil, "Unable to read object list: " .. tostring(items))
			end
			callback(items)
		end, on_timeout)
	end
	local cancelled, process = false, nil
	local function finish(result, err)
		if not cancelled then
			callback(result, err)
		end
	end
	local function request(args, consume, limit)
		local ok, spawned = pcall(
			vim.system,
			args,
			{ text = true },
			vim.schedule_wrap(function(reply)
				if cancelled then
					return
				end
				process = nil
				local handled, err = pcall(function()
					if reply.code ~= 0 then
						local decoded, failure = pcall(vim.json.decode, reply.stderr)
						local detail = decoded and type(failure) == "table" and failure.error
						local message = type(detail) == "table" and detail.message or reply.stderr
						error(
							type(message) == "string" and message ~= "" and message
								or "arf IPC failed (" .. tostring(reply.code) .. ")",
							0
						)
					end
					if limit and #reply.stdout > limit then
						error("Object list exceeded output.max_bytes", 0)
					end
					local value = vim.json.decode(reply.stdout)
					assert(type(value) == "table", "invalid arf response")
					consume(value)
				end)
				if not handled then
					finish(nil, "Object lookup failed: " .. tostring(err))
				end
			end)
		)
		if ok then
			process = spawned
		else
			finish(nil, tostring(spawned))
		end
	end
	-- Check the server as well as the CLI: older servers ignore deadline parameters.
	request({ config.executable, "ipc", "session", "--pid", tostring(config.pid) }, function(info)
		assert(
			type(info.capabilities) == "table" and vim.tbl_contains(info.capabilities, "call_execution_timeout"),
			"Object handler requires arf 0.7.1 or later; restart the session after updating arf"
		)
		request({
			config.executable,
			"ipc",
			"call",
			"nvim/objects",
			"--pid",
			tostring(config.pid),
			"--queue-timeout",
			"5000",
			"--execution-timeout",
			"5000",
		}, function(reply)
			finish(native_items(reply.value))
		end, config.output.max_bytes)
	end)
	return function()
		cancelled = true
		if process then
			process:kill(15)
		end
	end
end

return M
