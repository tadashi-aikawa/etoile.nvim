local M = {}

---@class etoile.Config.Root
---@field strategy "git_or_cwd"|string

---@class etoile.Config.Tree
---@field border string
---@field width_padding number
---@field left_padding number
---@field icon_width_padding number
---@field right_padding number
---@field height_ratio number
---@field max_height number
---@field max_height_ratio number
---@field min_height number
---@field min_height_ratio number
---@field min_width number
---@field max_width number
---@field position "source_window"|string
---@field reserve_preview_width boolean
---@field row number?
---@field col number

---@class etoile.Config.Preview.Directory
---@field enabled boolean
---@field max_depth number

---@class etoile.Config.Preview
---@field enabled boolean
---@field border string
---@field min_width number
---@field max_width number
---@field width_ratio number
---@field max_height number
---@field max_height_ratio number
---@field min_height number
---@field min_height_ratio number
---@field height_ratio number
---@field debounce_ms number
---@field directory etoile.Config.Preview.Directory

---@class etoile.Config.Keymaps
---@field open string
---@field open_split string
---@field open_vsplit string
---@field open_tab string
---@field parent string
---@field child string
---@field preview string
---@field search string
---@field search_next string
---@field search_prev string
---@field search_clear string
---@field help string
---@field close string
---@field focus_toggle string
---@field focus_preview string
---@field focus_tree string

---@class etoile.Config.Search
---@field exclude string[]
---@field expand_matches boolean

---@class etoile.Config.GitStatus
---@field show_ignored boolean
---@field sync_on_preview_write boolean

---@class etoile.Config.Confirm
---@field delete boolean
---@field move boolean
---@field copy boolean
---@field create boolean

---@class etoile.Config.Icons.GitStatus
---@field modified string
---@field added string
---@field deleted string
---@field renamed string
---@field ignored string
---@field conflicted string

---@class etoile.Config.Icons
---@field link string
---@field directory string
---@field directory_open string
---@field git_status etoile.Config.Icons.GitStatus

---@class etoile.Config
---@field root etoile.Config.Root
---@field tree etoile.Config.Tree
---@field preview etoile.Config.Preview
---@field keymaps etoile.Config.Keymaps
---@field search etoile.Config.Search
---@field git_status etoile.Config.GitStatus
---@field confirm etoile.Config.Confirm
---@field icons etoile.Config.Icons
---@field indent number
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
		exclude = { ".git", "node_modules", ".cache", "venv", ".venv" },
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
