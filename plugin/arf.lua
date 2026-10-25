if vim.g.loaded_arf then
	return
end
vim.g.loaded_arf = true

require("arf.highlights")

vim.api.nvim_create_user_command("ArfRun", function(opts)
	if opts.range == 0 then
		require("arf").run()
	else
		require("arf").run(opts.line1, opts.line2)
	end
end, { range = true, desc = "Run the current R expression or selected lines through arf IPC" })

vim.api.nvim_create_user_command("ArfRunAll", function()
	require("arf").run_all()
end, { desc = "Run all top-level R expressions in order" })

vim.api.nvim_create_user_command("ArfClear", function()
	require("arf").clear()
end, { desc = "Clear arf results in the current buffer" })

vim.api.nvim_create_user_command("ArfSummary", function()
	require("arf").inspect("base::summary")
end, { desc = "Show summary of the R object under the cursor" })

vim.api.nvim_create_user_command("ArfStop", function()
	require("arf").stop()
end, { desc = "Stop the owned arf session and clear all results" })

vim.api.nvim_create_user_command("ArfOutput", function()
	require("arf").output()
end, { desc = "Open saved output for the execution under the cursor" })

vim.api.nvim_create_user_command("ArfCopyPlot", function()
	require("arf").copy_plot()
end, { desc = "Copy the most recently generated saved plot to the clipboard" })

vim.api.nvim_create_user_command("ArfObjects", function()
	require("arf").objects()
end, { desc = "Pick an R object to inspect" })
