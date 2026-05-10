local next_extmark_id
local buffers
local highlights

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
	next_extmark_id = 1
	buffers = {
		[1] = {
			lines = {},
			extmarks = {},
		},
	}
	highlights = {}

	_G.vim = {
		deepcopy = deepcopy,
		fn = {
			strdisplaywidth = function(value)
				return #value
			end,
		},
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
		api = {
			nvim_create_namespace = function(name)
				return name
			end,
			nvim_set_hl = function(_, name, opts)
				highlights[name] = opts
			end,
			nvim_buf_get_lines = function(buf, start, finish)
				local lines = buffers[buf].lines
				local last = finish == -1 and #lines or finish
				local result = {}
				for index = start + 1, last do
					table.insert(result, lines[index])
				end
				return result
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
			nvim_buf_line_count = function(buf)
				return #buffers[buf].lines
			end,
			nvim_buf_set_extmark = function(buf, ns, line, col, opts)
				for _, chunk in ipairs(opts.virt_text or {}) do
					if type(chunk[2]) == "string" and #chunk[2] > 200 then
						error("E1249: Highlight group name too long")
					end
				end
				local id = next_extmark_id
				next_extmark_id = next_extmark_id + 1
				table.insert(buffers[buf].extmarks, {
					id = id,
					ns = ns,
					line = line,
					col = col,
					opts = deepcopy(opts),
				})
				return id
			end,
			nvim_buf_get_extmarks = function(buf, ns)
				local result = {}
				for _, mark in ipairs(buffers[buf].extmarks) do
					if mark.ns == ns then
						table.insert(result, { mark.id, mark.line, mark.col, deepcopy(mark.opts) })
					end
				end
				table.sort(result, function(a, b)
					if a[2] == b[2] then
						return a[1] < b[1]
					end
					return a[2] < b[2]
				end)
				return result
			end,
			nvim_buf_clear_namespace = function(buf, ns)
				local kept = {}
				for _, mark in ipairs(buffers[buf].extmarks) do
					if mark.ns ~= ns then
						table.insert(kept, mark)
					end
				end
				buffers[buf].extmarks = kept
			end,
		},
	}

	package.loaded["etoile.renderer"] = nil
	package.loaded["etoile.icons"] = nil
	package.loaded["etoile.scanner"] = nil
	package.loaded["etoile.git_status"] = nil
	package.loaded["etoile.config"] = nil
	package.loaded["nvim-web-devicons"] = {
		get_icon = function(name)
			if name:match("%.txt$") then
				return "T", "TxtIcon"
			end
			return "F", "FileIcon"
		end,
	}
end

local function decoration_at(line)
	for _, mark in ipairs(buffers[1].extmarks) do
		if mark.ns == "etoile_decor" and mark.line == line - 1 and mark.opts.virt_text then
			return mark.opts.virt_text
		end
	end
	return nil
end

local function decorations_at(line)
	local result = {}
	for _, mark in ipairs(buffers[1].extmarks) do
		if mark.ns == "etoile_decor" and mark.line == line - 1 and mark.opts.virt_text then
			table.insert(result, mark.opts.virt_text)
		end
	end
	return result
end

local function highlights_at(line)
	local result = {}
	for _, mark in ipairs(buffers[1].extmarks) do
		if mark.ns == "etoile_decor" and mark.line == line - 1 and mark.opts.hl_group then
			table.insert(result, {
				col = mark.col,
				end_col = mark.opts.end_col,
				hl_group = mark.opts.hl_group,
			})
		end
	end
	return result
end

describe("etoile.renderer", function()
	before_each(reset_vim)

	it("sets distinct git highlight colors for modified and new entries", function()
		local renderer = require("etoile.renderer")

		renderer.setup_highlights()

		assert.are.same({ default = true, fg = "#61AFEF" }, highlights.EtoileGitModified)
		assert.are.same({ default = true, fg = "#98C379" }, highlights.EtoileGitAdded)
	end)

	it("sets visible search highlight styles", function()
		local renderer = require("etoile.renderer")

		renderer.setup_highlights()

		assert.are.same({ default = true, link = "Search" }, highlights.EtoileSearchMatch)
		assert.are.same({ default = true, link = "IncSearch" }, highlights.EtoileSearchCurrent)
		assert.are.same({ default = true, link = "Comment" }, highlights.EtoileSearchIndex)
	end)

	it("keeps long entry ids out of virtual text highlight groups", function()
		local renderer = require("etoile.renderer")
		local long_path = "/tmp/project/" .. string.rep("nested-directory/", 20) .. "fyler.lua"
		local entries = {
			{
				id = long_path,
				path = long_path,
				name = "fyler.lua",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "fyler.lua" })
		local mark_ids = renderer.decorate(1, entries)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same(long_path, lines[1].id)
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" then
				assert.are.same(nil, mark.opts.virt_text)
			end
		end
	end)

	it("renders the search result index after matched names", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/alpha.lua",
				path = "/tmp/project/alpha.lua",
				name = "alpha.lua",
				type = "file",
				name_col = 0,
			},
			{
				id = "/tmp/project/beta.lua",
				path = "/tmp/project/beta.lua",
				name = "beta.lua",
				type = "file",
				name_col = 0,
			},
			{
				id = "/tmp/project/gamma.lua",
				path = "/tmp/project/gamma.lua",
				name = "gamma.lua",
				type = "file",
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "alpha.lua", "beta.lua", "gamma.lua" })
		renderer.decorate(1, entries, {
			matches_by_path = {
				["/tmp/project/alpha.lua"] = true,
				["/tmp/project/beta.lua"] = true,
				["/tmp/project/gamma.lua"] = true,
			},
			match_index_by_path = {
				["/tmp/project/alpha.lua"] = 1,
				["/tmp/project/beta.lua"] = 2,
				["/tmp/project/gamma.lua"] = 3,
			},
			total = 3,
			current_path = "/tmp/project/beta.lua",
		})

		assert.are.same({ { { " [2/3]", "EtoileSearchIndex" } } }, decorations_at(2))
		assert.are.same({ { col = 0, end_col = #"alpha.lua", hl_group = "EtoileSearchMatch" } }, highlights_at(1))
		assert.are.same({ { col = 0, end_col = #"beta.lua", hl_group = "EtoileSearchCurrent" } }, highlights_at(2))
	end)

	it("attaches a copied line id by yank order and recomputes the icon from the current name", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/base.md",
				path = "/tmp/project/base.md",
				name = "base.md",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/other.txt",
				path = "/tmp/project/other.txt",
				name = "other.txt",
				type = "file",
				decoration = { { "T ", "TxtIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "base.md", "other.txt" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "base.md", "copy.txt", "other.txt" })
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark.line == 1 then
				mark.line = 2
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/base.md", line = "copy.txt" },
		})

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/base.md", lines[2].id)
		assert.are.same("/tmp/project/other.txt", lines[3].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(2)[1])
		assert.are.same({ { "T ", "TxtIcon" } }, decorations_at(2)[2])
	end)

	it("repairs ids after yyp leaves the next line id on the inserted line", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/index.ts",
				path = "/tmp/project/index.ts",
				name = "index.ts",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/package.json",
				path = "/tmp/project/package.json",
				name = "package.json",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "index.ts", "package.json" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "index.ts", "index.ts", "package.json" })
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark.line == 1 then
				mark.line = 2
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/index.ts", line = "index.ts" },
		})

		local entry = renderer.entry_at_line(1, 2, renderer.entries_by_id(entries), mark_ids)
		assert.are.same("/tmp/project/index.ts", entry.path)
		assert.are.same("index.ts", entry.name)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/index.ts", lines[1].id)
		assert.are.same("/tmp/project/index.ts", lines[2].id)
		assert.are.same("/tmp/project/package.json", lines[3].id)
	end)

	it("keeps the source path for renamed entries with an existing id", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/base.md",
				path = "/tmp/project/base.md",
				name = "base.md",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "base.md" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "renamed.md" })

		local entry = renderer.entry_at_line(1, 1, renderer.entries_by_id(entries), mark_ids)

		assert.are.same("renamed.md", entry.name)
		assert.are.same("/tmp/project/base.md", entry.path)
		assert.are.same("/tmp/project/base.md", entry.source_path)
		assert.is_false(entry.searchable)
	end)

	it("repairs ids after undo restores a deleted directory line with the next line id", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/d1",
				path = "/tmp/project/d1",
				name = "d1",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/d2",
				path = "/tmp/project/d2",
				name = "d2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/d3",
				path = "/tmp/project/d3",
				name = "d3",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "d1", "d2", "d3" })
		local mark_ids = renderer.decorate(1, entries)

		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark_ids[mark.id] == "/tmp/project/d2" then
				mark.opts.invalid = true
			elseif mark.ns == "etoile_id" and mark_ids[mark.id] == "/tmp/project/d3" then
				mark.line = 1
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/d1", lines[1].id)
		assert.are.same("/tmp/project/d2", lines[2].id)
		assert.are.same("/tmp/project/d3", lines[3].id)
	end)

	it("repairs ids after undo restores a deleted directory line when the deleted line id is missing", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/d1",
				path = "/tmp/project/d1",
				name = "d1",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/d2",
				path = "/tmp/project/d2",
				name = "d2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/d3",
				path = "/tmp/project/d3",
				name = "d3",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "d1", "d2", "d3" })
		local mark_ids = renderer.decorate(1, entries)
		local kept = {}
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark_ids[mark.id] == "/tmp/project/d2" then
				-- Simulate Neovim undo restoring the text but dropping the deleted line id.
			else
				if mark.ns == "etoile_id" and mark_ids[mark.id] == "/tmp/project/d3" then
					mark.line = 1
				end
				table.insert(kept, mark)
			end
		end
		buffers[1].extmarks = kept

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/d1", lines[1].id)
		assert.are.same("/tmp/project/d2", lines[2].id)
		assert.are.same("/tmp/project/d3", lines[3].id)
	end)

	it("keeps yanked child ids when an expanded directory is pasted above the source and renamed", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/dir1",
				path = "/tmp/project/dir1",
				name = "dir1",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/images2",
				path = "/tmp/project/images2",
				name = "images2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/images2/macky.png",
				path = "/tmp/project/images2/macky.png",
				name = "macky.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
			{
				id = "/tmp/project/images2/minerva.png",
				path = "/tmp/project/images2/minerva.png",
				name = "minerva.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
			{
				id = "/tmp/project/.gitignore",
				path = "/tmp/project/.gitignore",
				name = ".gitignore",
				type = "file",
				depth = 0,
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"dir1",
			"images2",
			"  macky.png",
			"  minerva.png",
			".gitignore",
		})
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"dir1",
			"images1",
			"  macky.png",
			"  minerva.png",
			"images2",
			"  macky.png",
			"  minerva.png",
			".gitignore",
		})
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark.line == 2 then
				mark.line = 5
			elseif mark.ns == "etoile_id" and mark.line == 3 then
				mark.line = 6
			elseif mark.ns == "etoile_id" and mark.line == 4 then
				mark.line = 7
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/images2", line = "images2" },
			{ id = "/tmp/project/images2/macky.png", line = "  macky.png" },
			{ id = "/tmp/project/images2/minerva.png", line = "  minerva.png" },
		})

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same(nil, lines[2].id)
		assert.are.same("/tmp/project/images2/macky.png", lines[3].id)
		assert.are.same("/tmp/project/images2/minerva.png", lines[4].id)
		assert.are.same("/tmp/project/images2", lines[5].id)
		assert.are.same("/tmp/project/images2/macky.png", lines[6].id)
		assert.are.same("/tmp/project/images2/minerva.png", lines[7].id)
	end)

	it("releases a copied expanded directory id after the pasted parent is renamed", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/images2",
				path = "/tmp/project/images2",
				name = "images2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/images2/macky.png",
				path = "/tmp/project/images2/macky.png",
				name = "macky.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
			{
				id = "/tmp/project/images2/minerva.png",
				path = "/tmp/project/images2/minerva.png",
				name = "minerva.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"images2",
			"  macky.png",
			"  minerva.png",
		})
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"images2",
			"  macky.png",
			"  minerva.png",
			"images2",
			"  macky.png",
			"  minerva.png",
		})
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" then
				mark.line = mark.line + 3
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/images2", line = "images2" },
			{ id = "/tmp/project/images2/macky.png", line = "  macky.png" },
			{ id = "/tmp/project/images2/minerva.png", line = "  minerva.png" },
		})
		vim.api.nvim_buf_set_lines(1, 0, 1, false, { "images1" })
		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same(nil, lines[1].id)
		assert.are.same("/tmp/project/images2/macky.png", lines[2].id)
		assert.are.same("/tmp/project/images2/minerva.png", lines[3].id)
		assert.are.same("/tmp/project/images2", lines[4].id)
	end)

	it("keeps a copied collapsed directory id after the pasted line is renamed", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/images2",
				path = "/tmp/project/images2",
				name = "images2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "images2" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"images2",
			"images2",
		})
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" then
				mark.line = mark.line + 1
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/images2", line = "images2" },
		})
		vim.api.nvim_buf_set_lines(1, 0, 1, false, { "images1" })
		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/images2", lines[1].id)
		assert.are.same("/tmp/project/images2", lines[2].id)
	end)

	it("matches pasted child lines after a renamed copied directory line is skipped", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/images2",
				path = "/tmp/project/images2",
				name = "images2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/images2/macky.png",
				path = "/tmp/project/images2/macky.png",
				name = "macky.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
			{
				id = "/tmp/project/images2/minerva.png",
				path = "/tmp/project/images2/minerva.png",
				name = "minerva.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 2,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"images1",
			"  macky.png",
			"  minerva.png",
			"images2",
			"  macky.png",
			"  minerva.png",
		})

		local mark_ids = {}
		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, {
			{ id = "/tmp/project/images2", line = "images2" },
			{ id = "/tmp/project/images2/macky.png", line = "  macky.png" },
			{ id = "/tmp/project/images2/minerva.png", line = "  minerva.png" },
		})

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same(nil, lines[1].id)
		assert.are.same("/tmp/project/images2/macky.png", lines[2].id)
		assert.are.same("/tmp/project/images2/minerva.png", lines[3].id)
	end)

	it("repairs ids after opening a line above a directory shifts the directory id to an empty line", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/dir",
				path = "/tmp/project/dir",
				name = "dir",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/dir2",
				path = "/tmp/project/dir2",
				name = "dir2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/dir3",
				path = "/tmp/project/dir3",
				name = "dir3",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "dir", "dir2", "dir3" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "dir", "", "dir2", "dir3" })
		for _, mark in ipairs(buffers[1].extmarks) do
			if mark.ns == "etoile_id" and mark.line == 1 then
				mark.line = 1
			elseif mark.ns == "etoile_id" and mark.line == 2 then
				mark.line = 3
			end
		end

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/dir", lines[1].id)
		assert.are.same(nil, lines[2].id)
		assert.are.same("/tmp/project/dir2", lines[3].id)
		assert.are.same("/tmp/project/dir3", lines[4].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(3)[1])
		assert.are.same({ { "D ", "EtoileDirectoryIcon" } }, decorations_at(3)[2])
	end)

	it("shows a placeholder icon on the current blank line before text is inserted", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/dir",
				path = "/tmp/project/dir",
				name = "dir",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
			{
				id = "/tmp/project/dir2",
				path = "/tmp/project/dir2",
				name = "dir2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "dir", "", "dir2" })
		local mark_ids = renderer.decorate(1, entries)

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil, 2)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same(nil, lines[2].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(2)[1])
		assert.are.same({ { "F ", "FileIcon" } }, decorations_at(2)[2])
	end)

	it("keeps a directory icon while renaming a collapsed directory", function()
		local config = require("etoile.config")
		config.setup({
			icons = {
				directory = "D",
			},
		})
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/dir",
				path = "/tmp/project/dir",
				name = "dir",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "dir" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "dirr" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		local lines = renderer.lines_with_ids(1, mark_ids)
		assert.are.same("/tmp/project/dir", lines[1].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(1)[1])
		assert.are.same({ { "D ", "EtoileDirectoryIcon" } }, decorations_at(1)[2])
	end)

	it("keeps git name highlight within the current line while renaming", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "/tmp/project/Makefile2",
				path = "/tmp/project/Makefile2",
				name = "Makefile2",
				type = "file",
				git_status = "added",
				line = "Makefile2",
				decoration = { { "F ", "FileIcon" } },
				name_col = 0,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "Makefile2" })
		local mark_ids = renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "akefile2" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), mark_ids, nil, nil)

		assert.are.same({ { col = 0, end_col = #"akefile2", hl_group = "EtoileGitAdded" } }, highlights_at(1))
	end)

	it("renders a left git status gutter for changed, new, and unchanged entries", function()
		package.loaded["etoile.git_status"] = {
			collect = function()
				return {
					by_path = {
						["/tmp/project/changed.txt"] = "modified",
						["/tmp/project/new.txt"] = "added",
						["/tmp/project/ignored.txt"] = "ignored",
					},
				}
			end,
			status_for = function(statuses, full_path)
				return statuses.by_path[full_path]
			end,
		}
		local scanner = require("etoile.scanner")
		scanner.list_dir = function(dir)
			if dir == "/tmp/project" then
				return {
					{ path = "/tmp/project/changed.txt", name = "changed.txt", type = "file" },
					{ path = "/tmp/project/new.txt", name = "new.txt", type = "file" },
					{ path = "/tmp/project/clean.txt", name = "clean.txt", type = "file" },
					{ path = "/tmp/project/ignored.txt", name = "ignored.txt", type = "file" },
				}
			end
			return {}
		end

		local renderer = require("etoile.renderer")
		local rendered = renderer.render("/tmp/project", {})

		assert.are.same({ { " ", "EtoileGitModified" } }, rendered.entries[1].git_decoration)
		assert.are.same({ { "T ", "TxtIcon" } }, rendered.entries[1].decoration)
		assert.are.same({ { " ", "EtoileGitAdded" } }, rendered.entries[2].git_decoration)
		assert.are.same({ { "T ", "TxtIcon" } }, rendered.entries[2].decoration)
		assert.are.same({ { "   ", "Normal" } }, rendered.entries[3].git_decoration)
		assert.are.same({ { "T ", "TxtIcon" } }, rendered.entries[3].decoration)
		assert.are.same({ { " ", "EtoileGitIgnored" } }, rendered.entries[4].git_decoration)
		assert.are.same({ { "T ", "TxtIcon" } }, rendered.entries[4].decoration)

		vim.api.nvim_buf_set_lines(1, 0, -1, false, rendered.lines)
		renderer.decorate(1, rendered.entries)
		assert.are.same({ { col = 0, end_col = #"changed.txt", hl_group = "EtoileGitModified" } }, highlights_at(1))
		assert.are.same({ { col = 0, end_col = #"new.txt", hl_group = "EtoileGitAdded" } }, highlights_at(2))
		assert.are.same({}, highlights_at(3))
		assert.are.same({ { col = 0, end_col = #"ignored.txt", hl_group = "EtoileGitIgnored" } }, highlights_at(4))
	end)

	it("renders aggregated git status on directories", function()
		package.loaded["etoile.git_status"] = {
			collect = function()
				return { by_path = { ["/tmp/project/src"] = "deleted", ["/tmp/project/src/main.lua"] = "deleted" } }
			end,
			status_for = function(statuses, full_path)
				return statuses.by_path[full_path]
			end,
		}
		local scanner = require("etoile.scanner")
		scanner.list_dir = function(dir)
			if dir == "/tmp/project" then
				return {
					{ path = "/tmp/project/src", name = "src", type = "directory" },
				}
			end
			return {}
		end

		local renderer = require("etoile.renderer")
		local rendered = renderer.render("/tmp/project", {})

		assert.are.same({ { " ", "EtoileGitDeleted" } }, rendered.entries[1].git_decoration)
		assert.are.same({ { " ", "EtoileDirectoryIcon" } }, rendered.entries[1].decoration)
	end)

	it("uses different icons for closed and open directories", function()
		local config = require("etoile.config")
		config.setup({
			icons = {
				directory = "C",
				directory_open = "O",
			},
		})
		local scanner = require("etoile.scanner")
		scanner.list_dir = function(dir)
			if dir == "/tmp/project" then
				return {
					{ path = "/tmp/project/closed", name = "closed", type = "directory" },
					{ path = "/tmp/project/open", name = "open", type = "directory" },
				}
			end
			return {}
		end

		local renderer = require("etoile.renderer")
		local rendered = renderer.render("/tmp/project", { ["/tmp/project/open"] = true })

		assert.are.same({ { "   ", "Normal" } }, rendered.entries[1].git_decoration)
		assert.are.same({ { "C ", "EtoileDirectoryIcon" } }, rendered.entries[1].decoration)
		assert.are.same({ { "   ", "Normal" } }, rendered.entries[2].git_decoration)
		assert.are.same({ { "O ", "EtoileDirectoryIcon" } }, rendered.entries[2].decoration)
	end)
end)
