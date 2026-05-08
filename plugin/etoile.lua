if vim.g.loaded_etoile then
	return
end
vim.g.loaded_etoile = 1

vim.api.nvim_create_user_command("Etoile", function(opts)
	require("etoile").open({ path = opts.args })
end, {
	nargs = "?",
	complete = "dir",
	desc = "Open etoile.nvim file tree",
})
