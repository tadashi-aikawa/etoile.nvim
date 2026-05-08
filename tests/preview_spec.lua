local buffers
local scandir_by_dir
local stat_by_path
local win_configs
local set_win_configs

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
			bufadd = function()
				return 99
			end,
			bufload = function() end,
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
			nvim_win_get_config = function(win)
				return win_configs[win]
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
		},
		wo = setmetatable({}, {
			__index = function(table, key)
				local value = {}
				rawset(table, key, value)
				return value
			end,
		}),
		keymap = {
			set = function() end,
			del = function() end,
		},
	}

	package.loaded["etoile.preview"] = nil
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
end)
