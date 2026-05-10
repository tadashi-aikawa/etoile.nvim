local buffers
local added_buffers
local loaded_buffers
local scandir_by_dir
local stat_by_path
local win_configs
local set_win_configs
local set_win_bufs
local set_keymaps
local deleted_keymaps
local current_win

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
	buffers = {}
	added_buffers = {}
	loaded_buffers = {}
	scandir_by_dir = {}
	stat_by_path = {}
	win_configs = {
		[1] = {
			row = 1,
			col = 1,
			width = 30,
		},
	}
	set_win_configs = {}
	set_win_bufs = {}
	set_keymaps = {}
	deleted_keymaps = {}
	current_win = 1

	_G.vim = {
		o = {
			columns = 120,
			lines = 40,
		},
		bo = setmetatable({}, {
			__index = function(table, key)
				local value = {}
				rawset(table, key, value)
				return value
			end,
		}),
		fn = {
			bufadd = function(path)
				table.insert(added_buffers, path)
				return 99
			end,
			bufload = function(buf)
				table.insert(loaded_buffers, buf)
			end,
			fnamemodify = function(path)
				return path:match("([^/]+)$") or path
			end,
		},
		pesc = function(value)
			return (value:gsub("([^%w])", "%%%1"))
		end,
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
		filetype = {
			match = function()
				return nil
			end,
		},
		treesitter = {
			start = function() end,
		},
		uv = {
			fs_scandir = function(dir)
				local entries = scandir_by_dir[dir]
				if not entries then
					return nil
				end
				return {
					index = 0,
					entries = entries,
				}
			end,
			fs_scandir_next = function(scan)
				scan.index = scan.index + 1
				local entry = scan.entries[scan.index]
				return entry and entry.name or nil
			end,
			fs_lstat = function(path)
				return stat_by_path[path]
			end,
			fs_stat = function(path)
				return stat_by_path[path]
			end,
		},
		api = {
			nvim_create_namespace = function(name)
				return name
			end,
			nvim_set_hl = function() end,
			nvim_create_buf = function()
				local id = #buffers + 1
				buffers[id] = {
					lines = {},
					extmarks = {},
				}
				return id
			end,
			nvim_create_augroup = function(name)
				return name
			end,
			nvim_set_option_value = function() end,
			nvim_buf_set_lines = function(buf, start, finish, _, replacement)
				local lines = buffers[buf].lines
				local last = finish == -1 and #lines or finish
				for _ = start + 1, last do
					table.remove(lines, start + 1)
				end
				for index, line in ipairs(replacement) do
					table.insert(lines, start + index, line)
				end
			end,
			nvim_buf_set_extmark = function(buf, ns, line, col, opts)
				table.insert(buffers[buf].extmarks, {
					ns = ns,
					line = line,
					col = col,
					opts = deepcopy(opts),
				})
			end,
			nvim_buf_clear_namespace = function() end,
			nvim_buf_add_highlight = function() end,
			nvim_buf_is_valid = function()
				return true
			end,
			nvim_buf_delete = function(buf)
				buffers[buf] = nil
			end,
			nvim_win_get_config = function(win)
				return win_configs[win]
			end,
			nvim_win_set_buf = function(win, buf)
				table.insert(set_win_bufs, { win = win, buf = buf })
			end,
			nvim_win_set_config = function(win, opts)
				win_configs[win] = deepcopy(opts)
				table.insert(set_win_configs, { win = win, opts = deepcopy(opts) })
			end,
			nvim_open_win = function()
				return 1
			end,
			nvim_create_autocmd = function() end,
			nvim_win_is_valid = function()
				return true
			end,
			nvim_get_current_win = function()
				return current_win
			end,
			nvim_set_current_win = function(win)
				current_win = win
			end,
		},
		wo = setmetatable({}, {
			__index = function(table, key)
				local value = {}
				rawset(table, key, value)
				return value
			end,
		}),
		keymap = {
			set = function(mode, lhs, rhs, opts)
				table.insert(set_keymaps, { mode = mode, lhs = lhs, rhs = rhs, opts = deepcopy(opts) })
			end,
			del = function(mode, lhs, opts)
				table.insert(deleted_keymaps, { mode = mode, lhs = lhs, opts = deepcopy(opts) })
			end,
		},
	}

	package.loaded["etoile.preview"] = nil
	package.loaded["etoile.help"] = nil
	package.loaded["etoile.renderer"] = nil
	package.loaded["etoile.icons"] = nil
	package.loaded["etoile.scanner"] = nil
	package.loaded["etoile.path"] = nil
	package.loaded["etoile.config"] = nil
	package.loaded["nvim-web-devicons"] = {
		get_icon = function()
			return "F", "FileIcon"
		end,
	}
end

local function add_entry(parent, name, entry_type)
	scandir_by_dir[parent] = scandir_by_dir[parent] or {}
	table.insert(scandir_by_dir[parent], { name = name })
	stat_by_path[parent .. "/" .. name] = { type = entry_type }
end

local function open_directory_preview(opts)
	local config = require("etoile.config")
	config.setup(opts)
	local preview = require("etoile.preview")
	preview.open({ win = 1, buf = 1 }, "/tmp/project", "directory")
	return buffers[1].lines
end

describe("etoile.preview", function()
	before_each(reset_vim)

	it("limits directory preview depth to 2 by default", function()
		add_entry("/tmp/project", "src", "directory")
		add_entry("/tmp/project/src", "app", "directory")
		add_entry("/tmp/project/src/app", "models", "directory")
		add_entry("/tmp/project/src/app/models", "user.lua", "file")

		local lines = open_directory_preview()

		assert.are.same({
			" src",
			"   app",
			"     models",
		}, lines)
	end)

	it("uses configured directory preview depth", function()
		add_entry("/tmp/project", "src", "directory")
		add_entry("/tmp/project/src", "app", "directory")
		add_entry("/tmp/project/src/app", "models", "directory")

		local lines = open_directory_preview({
			preview = {
				directory = {
					max_depth = 1,
				},
			},
		})

		assert.are.same({
			" src",
			"   app",
		}, lines)
	end)

	it("can disable directory preview", function()
		add_entry("/tmp/project", "src", "directory")

		local lines = open_directory_preview({
			preview = {
				directory = {
					enabled = false,
				},
			},
		})

		assert.are.same({ "Directory preview is disabled" }, lines)
	end)

	it("resizes the preview when syncing the same target", function()
		add_entry("/tmp/project", "src", "directory")
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")
		local state = { win = 1, buf = 1 }

		preview.open(state, "/tmp/project", "directory")
		win_configs[1].width = 50
		preview.sync(state, "/tmp/project", "directory")

		assert.are.equal(1, #set_win_configs)
		assert.are.equal(53, set_win_configs[1].opts.col)
		assert.are.equal(52, set_win_configs[1].opts.width)
	end)

	it("does not create a normal file buffer for a missing file preview", function()
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")

		preview.open({ win = 1, buf = 1 }, "/tmp/project/new.lua", "file")

		assert.are.same({}, added_buffers)
		assert.are.same({}, loaded_buffers)
		assert.are.equal("nofile", vim.bo[1].buftype)
	end)

	it("maps preview focus controls with default keys", function()
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")

		preview.open({ win = 1, buf = 1 }, "/tmp/project/new.lua", "file")

		assert.are.equal("<C-w>w", set_keymaps[1].lhs)
		assert.are.equal("Toggle etoile focus", set_keymaps[1].opts.desc)
		assert.are.equal("<C-w>h", set_keymaps[2].lhs)
		assert.are.equal("Focus etoile main", set_keymaps[2].opts.desc)
		assert.are.equal("<leader>?", set_keymaps[3].lhs)
		assert.are.equal("Show etoile keymaps", set_keymaps[3].opts.desc)
	end)

	it("shows preview keymap help by default", function()
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")

		preview.open({ win = 1, buf = 1 }, "/tmp/project/new.lua", "file")

		set_keymaps[3].rhs()

		assert.is_truthy(buffers[2].lines[1]:find("Tree  Preview", 1, true))
		assert.is_truthy(buffers[2].lines[3]:find("<C-w>w", 1, true))
		assert.is_truthy(buffers[2].lines[4]:find("<C-w>h", 1, true))
		assert.is_truthy(buffers[2].lines[5]:find("<leader>?", 1, true))

		for _, keymap in ipairs(set_keymaps) do
			if keymap.lhs == "<Tab>" then
				keymap.rhs()
				break
			end
		end

		assert.is_truthy(buffers[2].lines[1]:find("Tree  Preview", 1, true))
		assert.is_truthy(buffers[2].lines[3]:find("<CR>", 1, true))
	end)

	it("focuses preview and tree explicitly", function()
		local preview = require("etoile.preview")
		local state = { win = 1, preview_win = 2 }

		preview.focus_preview(state)
		assert.are.equal(2, current_win)

		preview.focus_tree(state)
		assert.are.equal(1, current_win)
	end)

	it("toggles focus between preview and tree", function()
		local preview = require("etoile.preview")
		local state = { win = 1, preview_win = 2 }

		current_win = 1
		preview.focus_toggle(state)
		assert.are.equal(2, current_win)

		preview.focus_toggle(state)
		assert.are.equal(1, current_win)
	end)

	it("reloads a missing file scratch preview after the file appears", function()
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")
		local state = { win = 1, buf = 1 }

		preview.open(state, "/tmp/project/new.lua", "file")
		stat_by_path["/tmp/project/new.lua"] = { type = "file" }
		preview.sync(state, "/tmp/project/new.lua", "file")

		assert.are.same({ "/tmp/project/new.lua" }, added_buffers)
		assert.are.same({ 99 }, loaded_buffers)
		assert.are.equal(99, state.preview_buf)
		assert.is_false(state.preview_buf_is_scratch)
	end)

	it("clears an existing preview for a new unsaved entry", function()
		add_entry("/tmp/project", "src", "directory")
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")
		local state = { win = 1, buf = 1 }

		preview.open(state, "/tmp/project", "directory")
		local previous_buf = state.preview_buf
		preview.clear(state, "new.lua")

		assert.are.same({}, buffers[state.preview_buf].lines)
		assert.are.same({ { win = 1, buf = state.preview_buf } }, set_win_bufs)
		assert.are.equal(" new.lua ", win_configs[1].title)
		assert.is_nil(buffers[previous_buf])
	end)

	it("clears an existing preview without keeping the previous title", function()
		add_entry("/tmp/project", "src", "directory")
		local config = require("etoile.config")
		config.setup()
		local preview = require("etoile.preview")
		local state = { win = 1, buf = 1 }

		preview.open(state, "/tmp/project", "directory")
		preview.clear(state, "")

		assert.are.same({}, buffers[state.preview_buf].lines)
		assert.are.equal("  ", win_configs[1].title)
	end)
end)
