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
vim.fn = vim.fn or {
	glob2regpat = function(value)
		return value
	end,
	match = function()
		return -1
	end,
}
vim.uv = vim.uv or {
	fs_scandir = function()
		return nil
	end,
}

local pending = require("etoile.pending")

describe("etoile.pending", function()
	it("folds chained moves into a single move from the original source", function()
		local ops = pending.merge({
			{ type = "move", from = "/tmp/project/a.md", to = "/tmp/project/b.md", entry_type = "file" },
		}, {
			{ type = "move", from = "/tmp/project/b.md", to = "/tmp/project/c.md", entry_type = "file" },
		})

		assert.are.same({
			{ type = "move", from = "/tmp/project/a.md", to = "/tmp/project/c.md", entry_type = "file" },
		}, ops)
	end)

	it("drops a created entry when it is deleted before saving", function()
		local ops = pending.merge({
			{ type = "create", path = "/tmp/project/new.md", entry_type = "file" },
		}, {
			{ type = "delete", path = "/tmp/project/new.md", entry_type = "file" },
		})

		assert.are.same({}, ops)
	end)

	it("keeps an existing pending delete when the same delete is merged again", function()
		local ops = pending.merge({
			{ type = "delete", path = "/tmp/project/old.md", entry_type = "file" },
		}, {
			{ type = "delete", path = "/tmp/project/old.md", entry_type = "file" },
		})

		assert.are.same({
			{ type = "delete", path = "/tmp/project/old.md", entry_type = "file" },
		}, ops)
	end)

	it("renames a pending create instead of moving a missing source", function()
		local ops = pending.merge({
			{ type = "create", path = "/tmp/project/new.md", entry_type = "file" },
		}, {
			{ type = "move", from = "/tmp/project/new.md", to = "/tmp/project/renamed.md", entry_type = "file" },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/renamed.md", entry_type = "file" },
		}, ops)
	end)

	it("drops a copied entry when the copy destination is deleted before saving", function()
		local ops = pending.merge({
			{ type = "copy", from = "/tmp/project/base.md", to = "/tmp/project/copy.md", entry_type = "file" },
		}, {
			{ type = "delete", path = "/tmp/project/copy.md", entry_type = "file" },
		})

		assert.are.same({}, ops)
	end)

	it("treats a pasted deleted source as a move instead of delete plus copy", function()
		local ops = pending.merge({
			{ type = "delete", path = "/tmp/project/a/A", entry_type = "file" },
		}, {
			{ type = "copy", from = "/tmp/project/a/A", to = "/tmp/project/b/A", entry_type = "file" },
		})

		assert.are.same({
			{ type = "move", from = "/tmp/project/a/A", to = "/tmp/project/b/A", entry_type = "file" },
		}, ops)
	end)

	it("rewrites child operations when their pending parent directory moves", function()
		local ops = pending.merge({
			{ type = "create", path = "/tmp/project/dir/child.md", entry_type = "file" },
		}, {
			{ type = "move", from = "/tmp/project/dir", to = "/tmp/project/renamed", entry_type = "directory" },
		})

		assert.are.same({
			{ type = "create", path = "/tmp/project/renamed/child.md", entry_type = "file" },
			{ type = "move", from = "/tmp/project/dir", to = "/tmp/project/renamed", entry_type = "directory" },
		}, ops)
	end)
end)
