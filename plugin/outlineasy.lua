if vim.fn.has("nvim-0.9") == 0 then return end

vim.api.nvim_create_user_command("Outlineasy", function(opts)
  local scope = opts.args ~= "" and opts.args or nil
  require("outlineasy").toggle(scope)
end, {
  nargs    = "?",
  complete = function() return { "file", "module", "all" } end,
  desc     = "Toggle LSP symbol outline (scope: file | module | all)",
})

vim.api.nvim_create_user_command("OutlineasyRefresh", function()
  require("outlineasy").refresh()
end, { desc = "Force-refresh LSP outline" })
