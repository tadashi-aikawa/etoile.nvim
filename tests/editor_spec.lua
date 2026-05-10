_G.vim = _G.vim or {}
vim.deepcopy = vim.deepcopy
	or function(value)
		if type(value) ~= "table" then
			return value
		end
		local result = {}
		for key, item in pairs(value) do
			result[key] = vim.deepcopy(item)
		end
		return result
	end
vim.tbl_deep_extend = vim.tbl_deep_extend
	or function(_, base, opts)
		for key, value in pairs(opts or {}) do
			if type(value) == "table" and type(base[key]) == "table" then
				vim.tbl_deep_extend("force", base[key], value)
			else
				base[key] = value
			end
		end
		return base
	end

local editor = require("etoile.editor")

local function snapshot(entries)
	for _, entry in ipairs(entries) do
		entry.id = entry.id or entry.path
	end
	return editor.snapshot(entries)
end

describe("etoile.editor", function()
	it("creates files and directories from new tree lines", function()
		local ops = editor.diff("/tmp/project", {}, {
			"src",
			"  init.lua",
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/src", entry_type = "directory" },
			{ type = "create", path = "/tmp/project/src/init.lua", entry_type = "file" },
		}, ops)
	end)

	it("creates a file from a single new tree line", function()
		local ops = editor.diff("/tmp/project", {}, {
			"memo.md",
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/memo.md", entry_type = "file" },
		}, ops)
	end)

	it("creates a directory from a trailing slash", function()
		local ops = editor.diff("/tmp/project", {}, {
			"hoge/",
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/hoge", entry_type = "directory" },
		}, ops)
	end)

	it("normalizes a trailing slash when creating a directory with children", function()
		local ops = editor.diff("/tmp/project", {}, {
			"hoge/",
			"  fuga.md",
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/hoge", entry_type = "directory" },
			{ type = "create", path = "/tmp/project/hoge/fuga.md", entry_type = "file" },
		}, ops)
	end)

	it("detects renamed files", function()
		local entries = {
			{ path = "/tmp/project/old.lua", name = "old.lua", type = "file" },
		}

		local ops =
			editor.diff("/tmp/project", snapshot(entries), { { line = "new.lua", id = "/tmp/project/old.lua" } })

		assert.are.same({
			{ type = "move", from = "/tmp/project/old.lua", to = "/tmp/project/new.lua", entry_type = "file" },
		}, ops)
	end)

	it("detects moves by indentation under a directory", function()
		local entries = {
			{ path = "/tmp/project/src", name = "src", type = "directory" },
			{ path = "/tmp/project/main.lua", name = "main.lua", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "src", id = "/tmp/project/src" },
			{ line = "  main.lua", id = "/tmp/project/main.lua" },
		})

		assert.are.same({
			{ type = "move", from = "/tmp/project/main.lua", to = "/tmp/project/src/main.lua", entry_type = "file" },
		}, ops)
	end)

	it("deletes missing entries", function()
		local entries = {
			{ path = "/tmp/project/remove.lua", name = "remove.lua", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {})

		assert.are.same({
			{ type = "delete", path = "/tmp/project/remove.lua", entry_type = "file" },
		}, ops)
	end)

	it("shows deleted files and directories as root-relative paths in the confirmation", function()
		local confirmed_lines

		local ok, err = editor.apply({
			{ type = "delete", path = "/tmp/project/remove.lua", entry_type = "file" },
			{ type = "delete", path = "/tmp/project/src/old", entry_type = "directory" },
		}, {
			confirm_delete = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				confirmed_lines = lines
				return false
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same({
			"Apply 2 change(s)?",
			"",
			"Delete (2)",
			"- remove.lua",
			"- src/old/",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("shows moved files and directories as root-relative paths in the confirmation", function()
		local confirmed_lines

		local ok, err = editor.apply({
			{ type = "move", from = "/tmp/project/old.lua", to = "/tmp/project/src/new.lua", entry_type = "file" },
			{ type = "move", from = "/tmp/project/docs", to = "/tmp/project/archive/docs", entry_type = "directory" },
		}, {
			confirm_move = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				confirmed_lines = lines
				return false
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same({
			"Apply 2 change(s)?",
			"",
			"Move (2)",
			"- old.lua -> src/new.lua",
			"- docs/ -> archive/docs/",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("combines confirmed operation types into a single confirmation", function()
		local calls = 0
		local confirmed_lines

		local ok, err = editor.apply({
			{ type = "delete", path = "/tmp/project/remove.lua", entry_type = "file" },
			{ type = "move", from = "/tmp/project/old.lua", to = "/tmp/project/new.lua", entry_type = "file" },
			{ type = "copy", from = "/tmp/project/base.md", to = "/tmp/project/docs/base.md", entry_type = "file" },
			{ type = "create", path = "/tmp/project/new-dir", entry_type = "directory" },
		}, {
			confirm_delete = true,
			confirm_move = true,
			confirm_copy = true,
			confirm_create = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				calls = calls + 1
				confirmed_lines = lines
				return false
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same(1, calls)
		assert.are.same({
			"Apply 4 change(s)?",
			"",
			"Delete (1)",
			"- remove.lua",
			"",
			"Move (1)",
			"- old.lua -> new.lua",
			"",
			"Copy (1)",
			"- base.md -> docs/base.md",
			"",
			"Create (1)",
			"- new-dir/",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("returns a reverted result when the confirmation asks to revert", function()
		local ok, err = editor.apply({
			{ type = "move", from = "/tmp/project/old.lua", to = "/tmp/project/new.lua", entry_type = "file" },
		}, {
			confirm_move = true,
			root = "/tmp/project",
			confirm_fn = function()
				return "revert"
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply reverted", err)
	end)

	it("does not confirm copies by default when copy confirmation is disabled", function()
		local original_fn = vim.fn
		vim.fn = {
			isdirectory = function()
				return 0
			end,
			filereadable = function()
				return 0
			end,
			mkdir = function() end,
			readdir = function()
				return {}
			end,
		}

		local called = false
		local ok, err = editor.apply({
			{ type = "copy", from = "/tmp/project/src", to = "/tmp/project/src-copy", entry_type = "directory" },
		}, {
			confirm_copy = false,
			root = "/tmp/project",
			confirm_fn = function()
				called = true
				return false
			end,
		})
		vim.fn = original_fn

		assert.is_true(ok)
		assert.is_nil(err)
		assert.is_false(called)
	end)

	it("shows copied files as root-relative paths in the confirmation when enabled", function()
		local confirmed_lines

		local ok, err = editor.apply({
			{ type = "copy", from = "/tmp/project/base.md", to = "/tmp/project/docs/base.md", entry_type = "file" },
		}, {
			confirm_copy = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				confirmed_lines = lines
				return false
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same({
			"Apply 1 change(s)?",
			"",
			"Copy (1)",
			"- base.md -> docs/base.md",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("does not confirm creates by default when create confirmation is disabled", function()
		local original_fn = vim.fn
		vim.fn = {
			mkdir = function() end,
		}

		local called = false
		local ok, err = editor.apply({
			{ type = "create", path = "/tmp/project/new-dir", entry_type = "directory" },
		}, {
			confirm_create = false,
			root = "/tmp/project",
			confirm_fn = function()
				called = true
				return false
			end,
		})
		vim.fn = original_fn

		assert.is_true(ok)
		assert.is_nil(err)
		assert.is_false(called)
	end)

	it("shows created files and directories as root-relative paths in the confirmation when enabled", function()
		local confirmed_lines

		local ok, err = editor.apply({
			{ type = "create", path = "/tmp/project/new.lua", entry_type = "file" },
			{ type = "create", path = "/tmp/project/src", entry_type = "directory" },
		}, {
			confirm_create = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				confirmed_lines = lines
				return false
			end,
		})

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same({
			"Apply 2 change(s)?",
			"",
			"Create (2)",
			"- new.lua",
			"- src/",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("omits child deletes when a deleted directory already covers them", function()
		local ops = editor.diff(
			"/tmp/project",
			snapshot({
				{ path = "/tmp/project/images2-copy", name = "images2-copy", type = "directory" },
				{ path = "/tmp/project/images2-copy/minerva.png", name = "minerva.png", type = "file" },
				{ path = "/tmp/project/images2-copy/obsidia.png", name = "obsidia.png", type = "file" },
			}),
			{}
		)

		assert.are.same({
			{ type = "delete", path = "/tmp/project/images2-copy", entry_type = "directory" },
		}, ops)
	end)

	it("shows recursive file and directory counts for deleted directories in the confirmation", function()
		local original_fn = vim.fn
		vim.fn = {
			isdirectory = function(target)
				return ({
					["/tmp/project/images2-copy/minerva.png"] = 0,
					["/tmp/project/images2-copy/nested"] = 1,
					["/tmp/project/images2-copy/nested/obsidia.png"] = 0,
				})[target] or 0
			end,
			readdir = function(target)
				return ({
					["/tmp/project/images2-copy"] = { "minerva.png", "nested" },
					["/tmp/project/images2-copy/nested"] = { "obsidia.png" },
				})[target] or {}
			end,
		}

		local confirmed_lines
		local ok, err = editor.apply({
			{ type = "delete", path = "/tmp/project/images2-copy", entry_type = "directory" },
		}, {
			confirm_delete = true,
			root = "/tmp/project",
			confirm_fn = function(lines)
				confirmed_lines = lines
				return false
			end,
		})
		vim.fn = original_fn

		assert.is_false(ok)
		assert.are.same("Apply canceled", err)
		assert.are.same({
			"Apply 1 change(s)?",
			"",
			"Delete (1)",
			"- images2-copy/ (2 files, 1 dir)",
			"",
			"[y] Apply    [Enter/n] Cancel    [r] Revert",
		}, confirmed_lines)
	end)

	it("treats duplicated ids after copy as new entries without deleting shifted rows", function()
		local entries = {
			{ path = "/tmp/project/LICENSE", name = "LICENSE", type = "file" },
			{ path = "/tmp/project/README.md", name = "README.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "LICENSE", id = "/tmp/project/LICENSE" },
			{ line = "LICENSEaaaaaaaa.md", id = "/tmp/project/LICENSE" },
			{ line = "README.md", id = "/tmp/project/README.md" },
		})

		assert.are.same({
			{
				type = "copy",
				from = "/tmp/project/LICENSE",
				to = "/tmp/project/LICENSEaaaaaaaa.md",
				entry_type = "file",
			},
		}, ops)
	end)

	it("keeps a single renamed id as a move", function()
		local entries = {
			{ path = "/tmp/project/old.md", name = "old.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "new.md", id = "/tmp/project/old.md", mark_id = 1 },
		})

		assert.are.same({
			{ type = "move", from = "/tmp/project/old.md", to = "/tmp/project/new.md", entry_type = "file" },
		}, ops)
	end)

	it("treats a duplicated renamed id as copy", function()
		local entries = {
			{ path = "/tmp/project/base.md", name = "base.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "base.md", id = "/tmp/project/base.md", mark_id = 1 },
			{ line = "copy.md", id = "/tmp/project/base.md", mark_id = 2 },
		})

		assert.are.same({
			{ type = "copy", from = "/tmp/project/base.md", to = "/tmp/project/copy.md", entry_type = "file" },
		}, ops)
	end)

	it("copies a collapsed directory when the original line remains", function()
		local entries = {
			{ path = "/tmp/project/hoge", name = "hoge", type = "directory" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "hoge", id = "/tmp/project/hoge", mark_id = 1 },
			{ line = "hoge2", id = "/tmp/project/hoge", mark_id = 2 },
		})

		assert.are.same({
			{ type = "copy", from = "/tmp/project/hoge", to = "/tmp/project/hoge2", entry_type = "directory" },
		}, ops)
	end)

	it("treats copied expanded directory children as editable entries", function()
		local entries = {
			{ path = "/tmp/project/hoge", name = "hoge", type = "directory" },
			{ path = "/tmp/project/hoge/child", name = "child", type = "directory" },
			{ path = "/tmp/project/hoge/huga.md", name = "huga.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "hoge", id = "/tmp/project/hoge", mark_id = 1 },
			{ line = "  child", id = "/tmp/project/hoge/child", mark_id = 2 },
			{ line = "  huga.md", id = "/tmp/project/hoge/huga.md", mark_id = 3 },
			{ line = "hoge2", id = "/tmp/project/hoge", mark_id = 4 },
			{ line = "  child", id = "/tmp/project/hoge/child", mark_id = 5 },
			{ line = "  huga.md", id = "/tmp/project/hoge/huga.md", mark_id = 6 },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/hoge2", entry_type = "directory" },
			{
				type = "copy",
				from = "/tmp/project/hoge/child",
				to = "/tmp/project/hoge2/child",
				entry_type = "directory",
			},
			{
				type = "copy",
				from = "/tmp/project/hoge/huga.md",
				to = "/tmp/project/hoge2/huga.md",
				entry_type = "file",
			},
		}, ops)
	end)

	it("keeps renamed children when an expanded directory tree is copied", function()
		local entries = {
			{ path = "/tmp/project/dir3", name = "dir3", type = "directory" },
			{ path = "/tmp/project/dir3/fff23.ts", name = "fff23.ts", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "dir3", id = "/tmp/project/dir3", mark_id = 1 },
			{ line = "  fff23.ts", id = "/tmp/project/dir3/fff23.ts", mark_id = 2 },
			{ line = "dir4", id = "/tmp/project/dir3", mark_id = 3 },
			{ line = "  ggg23.ts", id = "/tmp/project/dir3/fff23.ts", mark_id = 4 },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/dir4", entry_type = "directory" },
			{
				type = "copy",
				from = "/tmp/project/dir3/fff23.ts",
				to = "/tmp/project/dir4/ggg23.ts",
				entry_type = "file",
			},
		}, ops)
	end)

	it("creates added children under an expanded copied directory", function()
		local entries = {
			{ path = "/tmp/project/dir3-2", name = "dir3-2", type = "directory" },
			{ path = "/tmp/project/dir3-2/fff233.ts", name = "fff233.ts", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "dir3-2", id = "/tmp/project/dir3-2", mark_id = 1 },
			{ line = "  fff233.ts", id = "/tmp/project/dir3-2/fff233.ts", mark_id = 2 },
			{ line = "dir4-2", id = "/tmp/project/dir3-2", mark_id = 3 },
			{ line = "  fff233.ts", id = "/tmp/project/dir3-2/fff233.ts", mark_id = 4 },
			{ line = "  ggg233.ts", id = nil },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/dir4-2", entry_type = "directory" },
			{
				type = "copy",
				from = "/tmp/project/dir3-2/fff233.ts",
				to = "/tmp/project/dir4-2/fff233.ts",
				entry_type = "file",
			},
			{ type = "create", path = "/tmp/project/dir4-2/ggg233.ts", entry_type = "file" },
		}, ops)
	end)

	it("creates a renamed pasted expanded directory without moving the source directory", function()
		local entries = {
			{ path = "/tmp/project/images2", name = "images2", type = "directory" },
			{ path = "/tmp/project/images2/macky.png", name = "macky.png", type = "file" },
			{ path = "/tmp/project/images2/minerva.png", name = "minerva.png", type = "file" },
			{ path = "/tmp/project/images2/obsidia.png", name = "obsidia.png", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "images1", id = nil },
			{ line = "  macky.png", id = "/tmp/project/images2/macky.png", mark_id = 1 },
			{ line = "  minerva.png", id = "/tmp/project/images2/minerva.png", mark_id = 2 },
			{ line = "images2", id = "/tmp/project/images2", mark_id = 3 },
			{ line = "  macky.png", id = "/tmp/project/images2/macky.png", mark_id = 4 },
			{ line = "  minerva.png", id = "/tmp/project/images2/minerva.png", mark_id = 5 },
			{ line = "  obsidia.png", id = "/tmp/project/images2/obsidia.png", mark_id = 6 },
		})

		assert.are.same({
			{
				type = "copy",
				from = "/tmp/project/images2/macky.png",
				to = "/tmp/project/images1/macky.png",
				entry_type = "file",
			},
			{
				type = "copy",
				from = "/tmp/project/images2/minerva.png",
				to = "/tmp/project/images1/minerva.png",
				entry_type = "file",
			},
			{ type = "create", path = "/tmp/project/images1", entry_type = "directory" },
		}, ops)
	end)

	it("detects expanded paths from a copied expanded directory", function()
		local expanded = editor.expanded_paths("/tmp/project", {
			{ line = "dir5", id = "/tmp/project/dir5", mark_id = 1 },
			{ line = "  hoge6.md", id = "/tmp/project/dir5/hoge6.md", mark_id = 2 },
			{ line = "dir6", id = "/tmp/project/dir5", mark_id = 3 },
			{ line = "  hoge6.md", id = "/tmp/project/dir5/hoge6.md", mark_id = 4 },
		})

		assert.are.same({
			["/tmp/project/dir5"] = true,
			["/tmp/project/dir6"] = true,
		}, expanded)
	end)

	it("moves the source when only a copied renamed line remains", function()
		local entries = {
			{ path = "/tmp/project/base.md", name = "base.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "copy.md", id = "/tmp/project/base.md", mark_id = 2 },
		})

		assert.are.same({
			{ type = "move", from = "/tmp/project/base.md", to = "/tmp/project/copy.md", entry_type = "file" },
		}, ops)
	end)

	it("does not use names alone to treat a copied-looking line as an existing entry", function()
		local entries = {
			{ path = "/tmp/project/src/README.md", name = "README.md", type = "file" },
			{ path = "/tmp/project/docs/README.md", name = "README.md", type = "file" },
		}

		local ops = editor.diff("/tmp/project", snapshot(entries), {
			{ line = "src", id = nil },
			{ line = "  README.md", id = "/tmp/project/src/README.md" },
			{ line = "README.md", id = nil },
			{ line = "docs", id = nil },
			{ line = "  README.md", id = "/tmp/project/docs/README.md" },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/src", entry_type = "directory" },
			{ type = "create", path = "/tmp/project/README.md", entry_type = "file" },
			{ type = "create", path = "/tmp/project/docs", entry_type = "directory" },
		}, ops)
	end)
end)
