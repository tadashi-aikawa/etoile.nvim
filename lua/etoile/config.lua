local M = {}

---@class etoile.Config.Root
---@field strategy "git_or_cwd"|string Root resolution strategy; "git_or_cwd" uses the nearest Git root from the current buffer, falling back to cwd

---@class etoile.Config.Tree
---@field border string Border style for the tree window
---@field width_padding number Extra width added to the tree window beyond the content width
---@field left_padding number Left padding reserving room for Git status icons
---@field icon_width_padding number Left padding reserving room for symlink and filetype icons rendered as virtual text
---@field right_padding number Right padding added to the tree window
---@field height_ratio number Preferred height as a ratio of the editor height
---@field max_height number Maximum tree window height in lines (effective max uses the larger of size and ratio)
---@field max_height_ratio number Maximum tree window height as a ratio (effective max uses the larger of size and ratio)
---@field min_height number Minimum tree window height in lines (effective min uses the smaller of size and ratio)
---@field min_height_ratio number Minimum tree window height as a ratio (effective min uses the smaller of size and ratio)
---@field min_width number Minimum tree window width in columns
---@field max_width number Maximum tree window width in columns
---@field position "source_window"|string Window placement; "source_window" places the tree near the source window, "editor" uses a fixed col
---@field reserve_preview_width boolean Shift the tree left so the preview can open on the right when true
---@field row number? Fixed editor-relative row; nil vertically centers the tree
---@field col number Editor-relative column used when position is "editor"
---@field exclude string[] File and directory names (or glob patterns) to hide from the tree window and directory previews. Hidden entries can be toggled with the toggle_exclude keymap.

---@class etoile.Config.Preview.Directory
---@field enabled boolean Enable directory preview
---@field max_depth number Maximum depth of the directory tree rendered in the preview; direct children of the preview target are depth 0

---@class etoile.Config.Preview
---@field enabled boolean Open the preview float automatically when etoile opens
---@field border string Border style for the preview window
---@field min_width number Minimum preview window width in columns
---@field max_width number Maximum preview window width in columns
---@field width_ratio number Preferred preview width as a ratio of available space
---@field max_height number Maximum preview window height in lines (effective max uses the larger of size and ratio)
---@field max_height_ratio number Maximum preview height as a ratio (effective max uses the larger of size and ratio)
---@field min_height number Minimum preview window height in lines (effective min uses the smaller of size and ratio)
---@field min_height_ratio number Minimum preview height as a ratio (effective min uses the smaller of size and ratio)
---@field height_ratio number Preferred preview height as a ratio of the editor height
---@field debounce_ms number Delay in ms before updating the preview on cursor move; set to 0 for immediate updates
---@field directory etoile.Config.Preview.Directory Directory preview settings

---@class etoile.Config.Keymaps
---@field open string Open a file or expand/collapse a directory
---@field open_split string Open the selected file in a horizontal split
---@field open_vsplit string Open the selected file in a vertical split
---@field open_tab string Open the selected file in a new tab
---@field parent string Move the tree root to the parent directory
---@field child string Move the tree root to the directory under the cursor
---@field root_history_back string Move backward through parent/child root history
---@field root_history_forward string Move forward through parent/child root history
---@field preview string Toggle the preview float
---@field search string Search all entries under the current root
---@field search_next string Jump to the next search result
---@field search_prev string Jump to the previous search result
---@field search_clear string Clear search highlights
---@field help string Show tree/preview keymap help (mapped in both tree and preview buffers)
---@field close string Close etoile
---@field focus_toggle string Switch focus between the tree window and preview float
---@field focus_preview string Focus the preview float (mapped in the tree buffer)
---@field focus_tree string Focus the tree window (mapped in the preview buffer)
---@field toggle_exclude string Toggle visibility of entries hidden by tree.exclude

---@class etoile.Config.Search
---@field exclude string[] File and directory names (or glob patterns) to skip when searching
---@field expand_matches boolean Expand parent directories for all matched entries before jumping to the match when true

---@class etoile.Config.GitStatus
---@field show_ignored boolean Show ignored files in the Git status gutter
---@field sync_on_preview_write boolean Refresh the main tree's Git status after saving a preview buffer

---@class etoile.Config.Confirm
---@field delete boolean Ask for confirmation before deleting files or directories
---@field move boolean Ask for confirmation before moving or renaming files or directories, showing before and after paths
---@field copy boolean Ask for confirmation before copying files or directories
---@field create boolean Ask for confirmation before creating files or directories

---@class etoile.Config.Icons.GitStatus
---@field modified string Icon for modified files
---@field added string Icon for added files
---@field deleted string Icon for deleted files
---@field renamed string Icon for renamed files
---@field ignored string Icon for ignored files
---@field conflicted string Icon for conflicted files

---@class etoile.Config.Icons
---@field link string Icon for symbolic links
---@field directory string Icon for collapsed directories
---@field directory_open string Icon for expanded directories
---@field git_status etoile.Config.Icons.GitStatus Git status icons shown in the left gutter
---@field search_excluded string Icon shown in the left gutter for entries excluded from search by search.exclude

---@class etoile.Config
---@field root etoile.Config.Root Root directory resolution settings
---@field tree etoile.Config.Tree Main tree window settings
---@field preview etoile.Config.Preview Preview float settings
---@field keymaps etoile.Config.Keymaps Key mappings for tree and preview buffers
---@field search etoile.Config.Search Search behavior settings
---@field git_status etoile.Config.GitStatus Git status display settings
---@field confirm etoile.Config.Confirm Confirmation dialog settings for file operations
---@field icons etoile.Config.Icons Icon customization settings
---@field indent number Number of spaces per tree depth level, used when rendering and interpreting edited indentation
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
		exclude = { ".git" },
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
		root_history_back = "<C-o>",
		root_history_forward = "<C-i>",
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
		toggle_exclude = "<leader>i",
	},
	search = {
		exclude = { ".git", "node_modules", ".cache", "venv", ".venv", ".output", "dist", "build" },
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
		search_excluded = "󰈉",
	},
	indent = 2,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
