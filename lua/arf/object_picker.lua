-- All Snacks picker integration stays here; metadata and inspection are UI agnostic.
local M = {}

function M.available()
	local ok, picker = pcall(require, "snacks.picker")
	if not ok or type(picker) ~= "table" or type(picker.pick) ~= "function" then
		return false, "Object Picker requires snacks.nvim with Snacks.picker"
	end
	return true
end

function M.open(items, load, inspect)
	local function apply(fn)
		return function(picker, item)
			item = item or picker:current()
			if not item then
				return
			end
			picker:close()
			inspect(fn, item.name)
		end
	end
	local keys = {
		p = { "arf_print", mode = "n" },
		r = { "arf_refresh", mode = "n" },
		q = { "close", mode = "n" },
	}
	return require("snacks.picker").pick({
		title = "Arf Objects",
		items = items,
		preview = false,
		layout = { preset = "select" },
		format = function(item)
			return {
				{ vim.fn.strtrans(item.name), "SnacksPickerLabel" },
				{ "  " .. vim.fn.strtrans(item.class), "SnacksPickerComment" },
				{ "  " .. item.size, "SnacksPickerComment" },
			}
		end,
		confirm = apply("base::summary"),
		actions = {
			arf_print = apply("base::print"),
			arf_refresh = function(picker)
				load(function(updated)
					picker.opts.items = updated
					picker:find()
				end, function()
					return not picker.closed
				end)
			end,
		},
		win = {
			input = {
				keys = vim.tbl_extend("force", keys, {
					["<Esc>"] = {
						function()
							vim.cmd.stopinsert()
						end,
						mode = "i",
						desc = "Normal mode",
					},
				}),
			},
			list = { keys = keys },
		},
	})
end

return M
