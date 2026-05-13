local keymaps
local commands
local current_win
local closed_wins
local autocmds
local buffer_lines
local cursor
local rendered_entries
local set_cursors
local current_entry
local preview_open
local preview_calls
local last_render_expanded
local input_value
local last_search
local opened_win_configs
local set_win_configs
local highlights
local rendered_entries_by_root
local last_render_root
local notifications

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
	autocmds = {}
	buffer_lines = { "file.lua" }
	cursor = { 1, 0 }
	rendered_entries = {
		{
			id = "/tmp/project/file.lua",
			path = "/tmp/project/file.lua",
			name = "file.lua",
			type = "file",
		},
	}
	set_cursors = {}
	current_entry = nil
	preview_open = false
	preview_calls = {}
	last_render_expanded = nil
	input_value = ""
	last_search = nil
	opened_win_configs = {}
	set_win_configs = {}
	highlights = {}
	rendered_entries_by_root = nil
	last_render_root = nil
	notifications = {}

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
		tbl_map = function(callback, items)
			local result = {}
			for index, item in ipairs(items) do
				result[index] = callback(item)
			end
			return result
		end,
		fn = {
			fnamemodify = function(path)
				return path
			end,
			fnameescape = function(path)
				return path:gsub(" ", "\\ ")
			end,
			input = function()
				return input_value
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
			nvim_create_namespace = function(name)
				return name
			end,
			nvim_buf_get_name = function()
				return ""
			end,
			nvim_get_current_win = function()
				return current_win
			end,
			nvim_create_buf = function()
				return 1
			end,
			nvim_get_option_value = function()
				return 1000
			end,
			nvim_set_option_value = function() end,
			nvim_buf_set_name = function() end,
			nvim_buf_set_lines = function(_, _, _, _, lines)
				buffer_lines = deepcopy(lines)
			end,
			nvim_buf_clear_namespace = function() end,
			nvim_buf_add_highlight = function(_, ns, hl_group, line, start_col, end_col)
				table.insert(highlights, {
					ns = ns,
					hl_group = hl_group,
					line = line,
					start_col = start_col,
					end_col = end_col,
				})
			end,
			nvim_buf_get_lines = function()
				return deepcopy(buffer_lines)
			end,
			nvim_open_win = function(_, _, opts)
				table.insert(opened_win_configs, deepcopy(opts))
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
				return deepcopy(cursor)
			end,
			nvim_win_set_cursor = function(_, value)
				cursor = deepcopy(value)
				table.insert(set_cursors, deepcopy(value))
			end,
			nvim_win_get_position = function()
				return { 0, 0 }
			end,
			nvim_win_set_config = function(_, opts)
				table.insert(set_win_configs, deepcopy(opts))
			end,
			nvim_create_autocmd = function(event, opts)
				if type(event) == "table" then
					for _, item in ipairs(event) do
						autocmds[item] = opts
					end
				else
					autocmds[event] = opts
				end
			end,
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
		notify = function(message, level)
			table.insert(notifications, { message = message, level = level })
		end,
		schedule = function(callback)
			callback()
		end,
		defer_fn = function(callback)
			callback()
		end,
	}

	package.loaded["etoile"] = nil
	package.loaded["etoile.config"] = nil
	package.loaded["etoile.help"] = nil
	package.loaded["etoile.editor"] = {
		snapshot = function(entries)
			return entries
		end,
		path_at_line = function(root, lines, line)
			local raw = lines[line] and lines[line].line
			return raw and (root .. "/" .. raw:match("%S+")) or nil
		end,
		expanded_paths = function()
			return {}
		end,
		diff = function()
			return {
				{ type = "create", path = "/tmp/project/ddd.md", entry_type = "file" },
			}
		end,
		apply = function()
			return true, nil
		end,
	}
	package.loaded["etoile.preview"] = {
		close = function() end,
		is_open = function()
			return preview_open
		end,
		clear = function(_, title)
			table.insert(preview_calls, { type = "clear", title = title })
		end,
		sync = function(_, file_path, entry_type)
			table.insert(preview_calls, { type = "sync", path = file_path, entry_type = entry_type })
		end,
	}
	package.loaded["etoile.renderer"] = {
		render = function(root, expanded, opts)
			last_render_root = root
			last_render_expanded = deepcopy(expanded or {})
			local entries = rendered_entries_by_root and rendered_entries_by_root[root] or rendered_entries
			if opts and opts.id_for_path then
				for _, entry in ipairs(entries) do
					entry.id = opts.id_for_path(entry.path)
				end
			end
			return {
				lines = vim.tbl_map(function(entry)
					return string.rep(" ", (entry.depth or 0) * 2) .. entry.id .. " " .. entry.name
				end, entries),
				entries = entries,
				max_width = 8,
			}
		end,
		entries_by_id = function(entries)
			local result = {}
			for _, entry in ipairs(entries) do
				result[entry.id] = entry
			end
			return result
		end,
		decorate = function(_, _, search)
			last_search = search
		end,
		lines_with_ids = function()
			local result = {}
			for _, line in ipairs(buffer_lines) do
				local id = line:match("^%s*(%d%d%d%d%d%d)%s")
				table.insert(result, { line = line, id = id })
			end
			return result
		end,
		sync_decorations = function() end,
		entry_at_line = function(_, line, entries_by_id)
			if current_entry then
				return current_entry
			end
			local id = buffer_lines[line or 1] and buffer_lines[line or 1]:match("^%s*(%d%d%d%d%d%d)%s")
			return id and entries_by_id[id] or nil
		end,
	}
	package.loaded["etoile.scanner"] = {
		list_dir = function()
			return {}
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

	it("maps root history keys from config", function()
		local etoile = require("etoile")
		etoile.setup({
			preview = {
				enabled = false,
			},
			keymaps = {
				root_history_back = "H",
				root_history_forward = "L",
			},
		})
		etoile.open({
			path = "/tmp/project",
		})

		assert.are.equal("Move backward through etoile root history", keymaps.H.opts.desc)
		assert.are.equal("Move forward through etoile root history", keymaps.L.opts.desc)
		assert.is_nil(keymaps["<C-o>"])
		assert.is_nil(keymaps["<C-i>"])
	end)

	it("shows tree keymap help by default", function()
		open_etoile()

		assert.are.equal("Show etoile keymaps", keymaps["<leader>?"].opts.desc)

		keymaps["<leader>?"].rhs()

		assert.is_truthy(buffer_lines[1]:find("Tree  Preview", 1, true))
		local help_height = opened_win_configs[#opened_win_configs].height
		local help_width = opened_win_configs[#opened_win_configs].width
		assert.are.equal(math.floor((help_width - #"Tree  Preview") / 2), buffer_lines[1]:find("Tree", 1, true) - 1)
		assert.are.same({
			ns = "etoile_help",
			hl_group = "TabLineSel",
			line = 0,
			start_col = buffer_lines[1]:find("Tree", 1, true) - 1,
			end_col = buffer_lines[1]:find("Tree", 1, true) - 1 + #"Tree",
		}, highlights[#highlights])
		assert.is_truthy(buffer_lines[3]:find("<CR>", 1, true))
		assert.is_truthy(buffer_lines[3]:find("Open etoile entry", 1, true))
		assert.is_truthy(buffer_lines[17]:find("q", 1, true))
		assert.is_truthy(buffer_lines[17]:find("Close etoile", 1, true))

		keymaps["<Tab>"].rhs()

		assert.is_truthy(buffer_lines[1]:find("Tree  Preview", 1, true))
		assert.is_truthy(buffer_lines[3]:find("<C-w>w", 1, true))
		assert.is_truthy(buffer_lines[4]:find("<C-w>h", 1, true))
		assert.is_truthy(buffer_lines[5]:find("<leader>?", 1, true))
		assert.are.equal(help_height, set_win_configs[#set_win_configs].height)
		assert.are.same({
			ns = "etoile_help",
			hl_group = "TabLineSel",
			line = 0,
			start_col = buffer_lines[1]:find("Preview", 1, true) - 1,
			end_col = buffer_lines[1]:find("Preview", 1, true) - 1 + #"Preview",
		}, highlights[#highlights])
		assert.is_nil(keymaps["["])
		assert.is_nil(keymaps["]"])

		keymaps["<S-Tab>"].rhs()

		assert.is_truthy(buffer_lines[1]:find("Tree  Preview", 1, true))
		assert.are.equal(help_height, set_win_configs[#set_win_configs].height)
		assert.are.equal("Close etoile keymap help", keymaps["q"].opts.desc)
		assert.are.equal("Close etoile keymap help", keymaps["<Esc>"].opts.desc)
		assert.are.equal("Close etoile keymap help", keymaps["<CR>"].opts.desc)
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

	it("moves the cursor to the saved path when the current line is sorted elsewhere", function()
		rendered_entries = {
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
			{ id = "/tmp/project/bbb.md", path = "/tmp/project/bbb.md", name = "bbb.md", type = "file" },
			{ id = "/tmp/project/ccc.md", path = "/tmp/project/ccc.md", name = "ccc.md", type = "file" },
		}
		open_etoile()
		buffer_lines = { "aaa.md", "bbb.md", "ddd.md", "ccc.md" }
		cursor = { 3, 0 }
		rendered_entries = {
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
			{ id = "/tmp/project/bbb.md", path = "/tmp/project/bbb.md", name = "bbb.md", type = "file" },
			{ id = "/tmp/project/ccc.md", path = "/tmp/project/ccc.md", name = "ccc.md", type = "file" },
			{ id = "/tmp/project/ddd.md", path = "/tmp/project/ddd.md", name = "ddd.md", type = "file" },
		}

		autocmds.BufWriteCmd.callback()

		assert.are.same({ 4, 0 }, set_cursors[#set_cursors])
	end)

	it("expands ancestors and moves the cursor to a newly created nested file", function()
		rendered_entries = {
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			{ id = "/tmp/project/dir2", path = "/tmp/project/dir2", name = "dir2", type = "directory" },
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
		}
		open_etoile()
		buffer_lines = { "dir", "dir2", "c/cc/ccc.c", "aaa.md" }
		cursor = { 3, 0 }
		rendered_entries = {
			{ id = "/tmp/project/c", path = "/tmp/project/c", name = "c", type = "directory" },
			{ id = "/tmp/project/c/cc", path = "/tmp/project/c/cc", name = "cc", type = "directory" },
			{ id = "/tmp/project/c/cc/ccc.c", path = "/tmp/project/c/cc/ccc.c", name = "ccc.c", type = "file" },
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			{ id = "/tmp/project/dir2", path = "/tmp/project/dir2", name = "dir2", type = "directory" },
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
		}

		autocmds.BufWriteCmd.callback()

		assert.is_true(last_render_expanded["/tmp/project/c"])
		assert.is_true(last_render_expanded["/tmp/project/c/cc"])
		assert.are.same({ 3, 0 }, set_cursors[#set_cursors])
	end)

	it("falls back to the nearest visible ancestor when the saved path is not rendered", function()
		rendered_entries = {
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			{ id = "/tmp/project/dir2", path = "/tmp/project/dir2", name = "dir2", type = "directory" },
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
		}
		open_etoile()
		buffer_lines = { "dir", "dir2", "c/cc/ccc.c", "aaa.md" }
		cursor = { 3, 0 }
		rendered_entries = {
			{ id = "/tmp/project/c", path = "/tmp/project/c", name = "c", type = "directory" },
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			{ id = "/tmp/project/dir2", path = "/tmp/project/dir2", name = "dir2", type = "directory" },
			{ id = "/tmp/project/aaa.md", path = "/tmp/project/aaa.md", name = "aaa.md", type = "file" },
		}

		autocmds.BufWriteCmd.callback()

		assert.are.same({ 1, 0 }, set_cursors[#set_cursors])
	end)

	it("keeps preview content for renamed copied entries with an existing source", function()
		open_etoile()
		preview_open = true
		current_entry = {
			name = "renamed.md",
			path = "/tmp/project/base.md",
			source_path = "/tmp/project/base.md",
			type = "file",
			searchable = false,
		}

		autocmds.CursorMoved.callback()

		assert.are.same({
			{ type = "sync", path = "/tmp/project/base.md", entry_type = "file" },
		}, preview_calls)
	end)

	it("clears preview for new unsaved entries without an existing source", function()
		open_etoile()
		preview_open = true
		current_entry = {
			name = "new.md",
			path = "new.md",
			type = "file",
			searchable = false,
		}

		autocmds.CursorMoved.callback()

		assert.are.same({
			{ type = "clear", title = "new.md" },
		}, preview_calls)
	end)

	it("keeps the cursor out of the concealed id prefix", function()
		open_etoile()
		cursor = { 1, 0 }

		autocmds.CursorMoved.callback()

		assert.are.same({ 1, 7 }, set_cursors[#set_cursors])
	end)

	it("keeps the cursor out of an indented concealed id prefix", function()
		rendered_entries = {
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory", depth = 0 },
			{
				id = "/tmp/project/dir/child.md",
				path = "/tmp/project/dir/child.md",
				name = "child.md",
				type = "file",
				depth = 1,
			},
		}
		open_etoile()
		cursor = { 2, 3 }

		autocmds.CursorMoved.callback()

		assert.are.same({ 2, 9 }, set_cursors[#set_cursors])
	end)

	it("continues searching inside matched directories", function()
		rendered_entries = {
			{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			{ id = "/tmp/project/dir/ccc.c", path = "/tmp/project/dir/ccc.c", name = "ccc.c", type = "file" },
			{ id = "/tmp/project/dir/ddd.d", path = "/tmp/project/dir/ddd.d", name = "ddd.d", type = "file" },
		}
		package.loaded["etoile.scanner"].list_dir = function(dir)
			if dir == "/tmp/project" then
				return {
					{ path = "/tmp/project/dir", name = "dir", type = "directory" },
				}
			end
			if dir == "/tmp/project/dir" then
				return {
					{ path = "/tmp/project/dir/ccc.c", name = "ccc.c", type = "file" },
					{ path = "/tmp/project/dir/ddd.d", name = "ddd.d", type = "file" },
				}
			end
			return {}
		end
		input_value = "d"
		open_etoile()

		keymaps["<leader>s"].rhs()

		assert.are.equal(2, last_search.total)
		assert.is_true(last_search.matches_by_path["/tmp/project/dir"])
		assert.is_true(last_search.matches_by_path["/tmp/project/dir/ddd.d"])
		assert.is_nil(last_search.matches_by_path["/tmp/project/dir/ccc.c"])
	end)

	it("moves backward and forward through child root history", function()
		rendered_entries_by_root = {
			["/tmp/project"] = {
				{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			},
			["/tmp/project/dir"] = {
				{
					id = "/tmp/project/dir/file.lua",
					path = "/tmp/project/dir/file.lua",
					name = "file.lua",
					type = "file",
				},
			},
		}
		open_etoile()
		current_entry = { path = "/tmp/project/dir", name = "dir", type = "directory" }

		keymaps["<C-]>"].rhs()

		assert.are.equal("/tmp/project/dir", last_render_root)

		keymaps["<C-o>"].rhs()

		assert.are.equal("/tmp/project", last_render_root)

		keymaps["<C-i>"].rhs()

		assert.are.equal("/tmp/project/dir", last_render_root)
	end)

	it("moves back from a parent root to the previous root and focuses it", function()
		rendered_entries_by_root = {
			["/tmp/project"] = {
				{ id = "/tmp/project/file.lua", path = "/tmp/project/file.lua", name = "file.lua", type = "file" },
			},
			["/tmp"] = {
				{ id = "/tmp/project", path = "/tmp/project", name = "project", type = "directory" },
			},
		}
		open_etoile()

		keymaps["-"].rhs()

		assert.are.equal("/tmp", last_render_root)
		assert.are.same({ 1, 0 }, set_cursors[#set_cursors])

		keymaps["<C-o>"].rhs()

		assert.are.equal("/tmp/project", last_render_root)
	end)

	it("does nothing at root history edges", function()
		open_etoile()

		keymaps["<C-o>"].rhs()
		keymaps["<C-i>"].rhs()

		assert.are.equal("/tmp/project", last_render_root)
		assert.are.equal(0, #notifications)
	end)

	it("moves child root without a modified guard warning", function()
		rendered_entries_by_root = {
			["/tmp/project"] = {
				{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
			},
			["/tmp/project/dir"] = {
				{
					id = "/tmp/project/dir/file.lua",
					path = "/tmp/project/dir/file.lua",
					name = "file.lua",
					type = "file",
				},
			},
		}
		open_etoile()
		current_entry = { path = "/tmp/project/dir", name = "dir", type = "directory" }

		keymaps["<C-]>"].rhs()

		assert.are.equal("/tmp/project/dir", last_render_root)
		assert.are.equal(0, #notifications)
	end)

	it("drops forward root history after branching to another child root", function()
		rendered_entries_by_root = {
			["/tmp/project"] = {
				{ id = "/tmp/project/dir", path = "/tmp/project/dir", name = "dir", type = "directory" },
				{ id = "/tmp/project/other", path = "/tmp/project/other", name = "other", type = "directory" },
			},
			["/tmp/project/dir"] = {
				{
					id = "/tmp/project/dir/file.lua",
					path = "/tmp/project/dir/file.lua",
					name = "file.lua",
					type = "file",
				},
			},
			["/tmp/project/other"] = {
				{
					id = "/tmp/project/other/file.lua",
					path = "/tmp/project/other/file.lua",
					name = "file.lua",
					type = "file",
				},
			},
		}
		open_etoile()
		current_entry = { path = "/tmp/project/dir", name = "dir", type = "directory" }
		keymaps["<C-]>"].rhs()
		keymaps["<C-o>"].rhs()
		current_entry = { path = "/tmp/project/other", name = "other", type = "directory" }

		keymaps["<C-]>"].rhs()
		keymaps["<C-i>"].rhs()

		assert.are.equal("/tmp/project/other", last_render_root)
	end)
end)
