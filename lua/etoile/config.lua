local M = {}

local defaults = {
	root = {
		strategy = "git_or_cwd",
	},
	tree = {
		border = "rounded",
		width_padding = 2,
		left_padding = 3,
		icon_width_padding = 4,
		right_padding = 10,
		height_ratio = 0.8,
		max_height = 50,
		max_height_ratio = 0.8,
		min_height = 10,
		min_height_ratio = 0.2,
		min_width = 24,
		max_width = 100,
		position = "source_window",
		reserve_preview_width = true,
		row = nil,
		col = 4,
	},
	preview = {
		enabled = true,
		border = "rounded",
		min_width = 30,
		max_width = 120,
		width_ratio = 0.8,
		max_height = 50,
		max_height_ratio = 0.8,
		min_height = 10,
		min_height_ratio = 0.2,
		height_ratio = 0.8,
		debounce_ms = 80,
		directory = {
			enabled = true,
			max_depth = 2,
		},
	},
	keymaps = {
		open = "<CR>",
		open_split = "<C-x>",
		open_vsplit = "<C-v>",
		open_tab = "<C-t>",
		parent = "-",
		child = "<C-]>",
		preview = "<C-p>",
		search = "<leader>s",
		search_next = "<leader>n",
		search_prev = "<leader>N",
		search_clear = "<leader>l",
		help = "<leader>?",
		close = "q",
		focus_toggle = "<C-w>w",
		focus_preview = "<C-w>l",
		focus_tree = "<C-w>h",
	},
	search = {
		exclude = { ".git", "node_modules", ".cache" },
		expand_matches = true,
	},
	git_status = {
		show_ignored = true,
		sync_on_preview_write = true,
	},
	confirm = {
		delete = true,
		move = true,
		copy = false,
		create = false,
	},
	icons = {
		link = "",
		directory = "",
		directory_open = "",
		git_status = {
			modified = "",
			added = "",
			deleted = "",
			renamed = "",
			ignored = "",
			conflicted = "",
		},
	},
	indent = 2,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
