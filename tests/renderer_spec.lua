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

local function conceals_at(line)
	local result = {}
	for _, mark in ipairs(buffers[1].extmarks) do
		if mark.ns == "etoile_decor" and mark.line == line - 1 and mark.opts.conceal then
			table.insert(result, {
				col = mark.col,
				end_col = mark.opts.end_col,
				conceal = mark.opts.conceal,
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

	it("embeds concealed numeric id prefixes and keeps display width stable", function()
		local scanner = require("etoile.scanner")
		scanner.list_dir = function(dir)
			if dir == "/tmp/project" then
				return {
					{ path = "/tmp/project/dir", name = "dir", type = "directory" },
				}
			end
			if dir == "/tmp/project/dir" then
				return {
					{ path = "/tmp/project/dir/child.md", name = "child.md", type = "file" },
				}
			end
			return {}
		end

		local renderer = require("etoile.renderer")
		local next_id = 0
		local rendered = renderer.render("/tmp/project", { ["/tmp/project/dir"] = true }, {
			id_for_path = function()
				next_id = next_id + 1
				return ("%06d"):format(next_id)
			end,
		})

		assert.are.equal("000001 dir", rendered.lines[1])
		assert.are.equal("  000002 child.md", rendered.lines[2])
		assert.are.equal(7, rendered.entries[1].name_col)
		assert.are.equal(9, rendered.entries[2].name_col)
		assert.are.equal(0, rendered.entries[1].prefix_col)
		assert.are.equal(2, rendered.entries[2].prefix_col)
		assert.are.equal(15, rendered.max_width)

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000099 copy.md" })

		assert.are.same({
			{
				line = "000099 copy.md",
				id = "000099",
				mark_id = nil,
			},
		}, renderer.lines_with_ids(1))

		renderer.sync_decorations(1, renderer.entries_by_id(rendered.entries), nil, nil)

		assert.are.same({
			{
				line = "000099 copy.md",
				id = "000099",
			},
		}, renderer.lines_with_ids(1))
		assert.are.same({ "000099 copy.md" }, buffers[1].lines)
		assert.are.same({
			{ col = 0, end_col = 7, conceal = "" },
		}, conceals_at(1))

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "  000099 copy.md" })
		renderer.sync_decorations(1, renderer.entries_by_id(rendered.entries), nil, nil)

		assert.are.same({
			{
				line = "  000099 copy.md",
				id = "000099",
			},
		}, renderer.lines_with_ids(1))
		assert.are.same({
			{ col = 2, end_col = 9, conceal = "" },
		}, conceals_at(1))
	end)

	it("reads entry ids from buffer text without id extmarks", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/fyler.lua",
				name = "fyler.lua",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 fyler.lua" })
		renderer.decorate(1, entries)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000001", lines[1].id)
		for _, mark in ipairs(buffers[1].extmarks) do
			assert.are_not.same("etoile_id", mark.ns)
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

	it("uses inline ids for copied lines and recomputes the icon from the current name", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/base.md",
				name = "base.md",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
			{
				id = "000002",
				path = "/tmp/project/other.txt",
				name = "other.txt",
				type = "file",
				decoration = { { "T ", "TxtIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 base.md", "000002 other.txt" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 base.md", "000001 copy.txt", "000002 other.txt" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000001", lines[2].id)
		assert.are.same("000002", lines[3].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(2)[1])
		assert.are.same({ { "T ", "TxtIcon" } }, decorations_at(2)[2])
	end)

	it("keeps the source type icon for a collapsed copied directory outside the current snapshot", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000025",
				path = "/tmp/project/dir8",
				name = "dir8",
				type = "directory",
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000025 dir8", "000030 dir9" })
		renderer.decorate(1, entries)

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil, {
			types_by_id = {
				["000030"] = "directory",
			},
		})

		assert.are.equal("EtoileDirectoryIcon", decorations_at(2)[2][1][2])
	end)

	it("uses source metadata for entries outside the current snapshot", function()
		local renderer = require("etoile.renderer")

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000030 dir9" })

		local entry = renderer.entry_at_line(1, 1, {}, {
			paths_by_id = {
				["000030"] = "/tmp/project/dir8/dir9",
			},
			types_by_id = {
				["000030"] = "directory",
			},
		})

		assert.are.same("dir9", entry.name)
		assert.are.same("directory", entry.type)
		assert.are.same("/tmp/project/dir8/dir9", entry.path)
		assert.are.same("/tmp/project/dir8/dir9", entry.source_path)
	end)

	it("keeps repeated inline ids after native put", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/index.ts",
				name = "index.ts",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
			{
				id = "000002",
				path = "/tmp/project/package.json",
				name = "package.json",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 index.ts", "000002 package.json" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 index.ts", "000001 index.ts", "000002 package.json" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		local entry = renderer.entry_at_line(1, 2, renderer.entries_by_id(entries))
		assert.are.same("/tmp/project/index.ts", entry.path)
		assert.are.same("index.ts", entry.name)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000001", lines[1].id)
		assert.are.same("000001", lines[2].id)
		assert.are.same("000002", lines[3].id)
	end)

	it("keeps the source path for renamed entries with an existing id", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/base.md",
				name = "base.md",
				type = "file",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 base.md" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 renamed.md" })

		local entry = renderer.entry_at_line(1, 1, renderer.entries_by_id(entries))

		assert.are.same("renamed.md", entry.name)
		assert.are.same("/tmp/project/base.md", entry.path)
		assert.are.same("/tmp/project/base.md", entry.source_path)
		assert.is_false(entry.searchable)
	end)

	it("keeps copied child inline ids when an expanded directory is pasted above the source and renamed", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/dir1",
				name = "dir1",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
			{
				id = "000002",
				path = "/tmp/project/images2",
				name = "images2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
			{
				id = "000003",
				path = "/tmp/project/images2/macky.png",
				name = "macky.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 9,
			},
			{
				id = "000004",
				path = "/tmp/project/images2/minerva.png",
				name = "minerva.png",
				type = "file",
				depth = 1,
				decoration = { { "F ", "FileIcon" } },
				name_col = 9,
			},
			{
				id = "000005",
				path = "/tmp/project/.gitignore",
				name = ".gitignore",
				type = "file",
				depth = 0,
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"000001 dir1",
			"000002 images2",
			"  000003 macky.png",
			"  000004 minerva.png",
			"000005 .gitignore",
		})
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, {
			"000001 dir1",
			"000002 images1",
			"  000003 macky.png",
			"  000004 minerva.png",
			"000002 images2",
			"  000003 macky.png",
			"  000004 minerva.png",
			"000005 .gitignore",
		})
		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000002", lines[2].id)
		assert.are.same("000003", lines[3].id)
		assert.are.same("000004", lines[4].id)
		assert.are.same("000002", lines[5].id)
		assert.are.same("000003", lines[6].id)
		assert.are.same("000004", lines[7].id)
	end)

	it("keeps inline ids after opening a line above a directory", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/dir",
				name = "dir",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
			{
				id = "000002",
				path = "/tmp/project/dir2",
				name = "dir2",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
			{
				id = "000003",
				path = "/tmp/project/dir3",
				name = "dir3",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 dir", "000002 dir2", "000003 dir3" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 dir", "", "000002 dir2", "000003 dir3" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000001", lines[1].id)
		assert.are.same(nil, lines[2].id)
		assert.are.same("000002", lines[3].id)
		assert.are.same("000003", lines[4].id)
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

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 dir", "", "000002 dir2" })
		renderer.decorate(1, entries)

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, 2)

		local lines = renderer.lines_with_ids(1)
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
				id = "000001",
				path = "/tmp/project/dir",
				name = "dir",
				type = "directory",
				depth = 0,
				decoration = { { "D ", "EtoileDirectoryIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 dir" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 dirr" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		local lines = renderer.lines_with_ids(1)
		assert.are.same("000001", lines[1].id)
		assert.are.same({ { "   ", "Normal" } }, decorations_at(1)[1])
		assert.are.same({ { "D ", "EtoileDirectoryIcon" } }, decorations_at(1)[2])
	end)

	it("keeps git name highlight within the current line while renaming", function()
		local renderer = require("etoile.renderer")
		local entries = {
			{
				id = "000001",
				path = "/tmp/project/Makefile2",
				name = "Makefile2",
				type = "file",
				git_status = "added",
				line = "000001 Makefile2",
				decoration = { { "F ", "FileIcon" } },
				name_col = 7,
			},
		}

		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 Makefile2" })
		renderer.decorate(1, entries)
		vim.api.nvim_buf_set_lines(1, 0, -1, false, { "000001 akefile2" })

		renderer.sync_decorations(1, renderer.entries_by_id(entries), nil, nil)

		assert.are.same({ { col = 7, end_col = 7 + #"akefile2", hl_group = "EtoileGitAdded" } }, highlights_at(1))
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
		assert.are.same({
			{
				col = rendered.entries[1].name_col,
				end_col = rendered.entries[1].name_col + #"changed.txt",
				hl_group = "EtoileGitModified",
			},
		}, highlights_at(1))
		assert.are.same({
			{
				col = rendered.entries[2].name_col,
				end_col = rendered.entries[2].name_col + #"new.txt",
				hl_group = "EtoileGitAdded",
			},
		}, highlights_at(2))
		assert.are.same({}, highlights_at(3))
		assert.are.same({
			{
				col = rendered.entries[4].name_col,
				end_col = rendered.entries[4].name_col + #"ignored.txt",
				hl_group = "EtoileGitIgnored",
			},
		}, highlights_at(4))
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
