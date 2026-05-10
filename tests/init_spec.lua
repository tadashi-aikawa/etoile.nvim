local keymaps
local commands
local current_win
local closed_wins

local function deepcopy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = deepcopy(item)
	end
	return result
end

local function reset_vim()
	keymaps = {}
	commands = {}
	current_win = 10
	closed_wins = {}

	_G.vim = {
		o = {
			columns = 120,
			lines = 40,
		},
		wo = setmetatable({}, {
			__index = function(table, key)
				local value = {}
				rawset(table, key, value)
				return value
			end,
		}),
		deepcopy = deepcopy,
		tbl_deep_extend = function(_, base, opts)
			for key, value in pairs(opts or {}) do
				if type(value) == "table" and type(base[key]) == "table" then
					vim.tbl_deep_extend("force", base[key], value)
				else
					base[key] = value
				end
			end
			return base
		end,
		fn = {
			fnamemodify = function(path)
				return path
			end,
			fnameescape = function(path)
				return path:gsub(" ", "\\ ")
			end,
			getcwd = function()
				return "/tmp/project"
			end,
			getpos = function()
				return { 0, 1, 0, 0 }
			end,
		},
		fs = {
			root = function()
				return "/tmp/project"
			end,
		},
		api = {
			nvim_buf_get_name = function()
				return ""
			end,
			nvim_get_current_win = function()
				return current_win
			end,
			nvim_create_buf = function()
				return 1
			end,
			nvim_set_option_value = function() end,
			nvim_buf_set_name = function() end,
			nvim_buf_set_lines = function() end,
			nvim_open_win = function()
				return 20
			end,
			nvim_win_is_valid = function(win)
				return win == 10 or (win == 20 and not closed_wins[win])
			end,
			nvim_win_close = function(win)
				closed_wins[win] = true
			end,
			nvim_set_current_win = function(win)
				current_win = win
			end,
			nvim_win_get_cursor = function()
				return { 1, 0 }
			end,
			nvim_win_set_cursor = function() end,
			nvim_win_get_position = function()
				return { 0, 0 }
			end,
			nvim_create_autocmd = function() end,
		},
		keymap = {
			set = function(mode, lhs, rhs, opts)
				keymaps[lhs] = { mode = mode, rhs = rhs, opts = deepcopy(opts) }
			end,
		},
		cmd = function(command)
			table.insert(commands, command)
		end,
		log = {
			levels = {
				WARN = "WARN",
				INFO = "INFO",
			},
		},
		notify = function() end,
		schedule = function(callback)
			callback()
		end,
		defer_fn = function(callback)
			callback()
		end,
	}

	package.loaded["etoile"] = nil
	package.loaded["etoile.config"] = nil
	package.loaded["etoile.editor"] = {
		snapshot = function(entries)
			return entries
		end,
	}
	package.loaded["etoile.preview"] = {
		close = function() end,
		is_open = function()
			return false
		end,
	}
	package.loaded["etoile.renderer"] = {
		render = function()
			local entry = {
				id = "/tmp/project/file.lua",
				path = "/tmp/project/file.lua",
				name = "file.lua",
				type = "file",
			}
			return {
				lines = { "file.lua" },
				entries = { entry },
				max_width = 8,
			}
		end,
		entries_by_id = function(entries)
			return {
				[entries[1].id] = entries[1],
			}
		end,
		decorate = function()
			return {
				[1] = "/tmp/project/file.lua",
			}
		end,
		entry_at_line = function(_, _, entries_by_id, mark_ids)
			return entries_by_id[mark_ids[1]]
		end,
	}
end

local function open_etoile()
	local etoile = require("etoile")
	etoile.setup({
		preview = {
			enabled = false,
		},
	})
	etoile.open({
		path = "/tmp/project",
	})
end

describe("etoile", function()
	before_each(reset_vim)

	it("maps split open variants to common Neovim defaults", function()
		open_etoile()

		assert.are.equal("Open etoile entry in horizontal split", keymaps["<C-x>"].opts.desc)
		assert.are.equal("Open etoile entry in vertical split", keymaps["<C-v>"].opts.desc)
		assert.are.equal("Open etoile entry in new tab", keymaps["<C-t>"].opts.desc)
	end)

	it("opens entries with edit, split, vsplit, and tabedit commands", function()
		open_etoile()

		keymaps["<CR>"].rhs()
		keymaps["<C-x>"].rhs()
		keymaps["<C-v>"].rhs()
		keymaps["<C-t>"].rhs()

		assert.are.same({
			"edit /tmp/project/file.lua",
			"split /tmp/project/file.lua",
			"vsplit /tmp/project/file.lua",
			"tabedit /tmp/project/file.lua",
		}, commands)
	end)
end)
