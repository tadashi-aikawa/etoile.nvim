local function reset_vim(entries)
	local scandir_entries = {}
	for _, entry in ipairs(entries) do
		table.insert(scandir_entries, entry.name)
	end

	local entry_by_path = {}
	for _, entry in ipairs(entries) do
		entry_by_path["/tmp/project/" .. entry.name] = {
			type = entry.type,
		}
	end

	_G.vim = {
		pesc = function(value)
			return (value:gsub("([^%w])", "%%%1"))
		end,
		uv = {
			fs_scandir = function()
				return {
					index = 0,
					entries = scandir_entries,
				}
			end,
			fs_scandir_next = function(scan)
				scan.index = scan.index + 1
				return scan.entries[scan.index]
			end,
			fs_lstat = function(full_path)
				return entry_by_path[full_path]
			end,
			fs_stat = function(full_path)
				return entry_by_path[full_path]
			end,
		},
	}

	package.loaded["etoile.scanner"] = nil
	package.loaded["etoile.path"] = nil
end

describe("etoile.scanner", function()
	it("sorts directories first using natural name order", function()
		reset_vim({
			{ name = "dir10000", type = "directory" },
			{ name = "dir3", type = "directory" },
			{ name = "dir3-2", type = "directory" },
			{ name = "dir3-3", type = "directory" },
			{ name = "dir4", type = "directory" },
			{ name = "dir5", type = "directory" },
			{ name = "dir6", type = "directory" },
			{ name = "images", type = "directory" },
			{ name = "fuga.ts", type = "file" },
			{ name = "macky.ts", type = "file" },
			{ name = "minerva.png", type = "file" },
			{ name = "obsidia.png", type = "file" },
			{ name = "package.json", type = "file" },
			{ name = "README.md", type = "file" },
		})

		local scanner = require("etoile.scanner")
		local names = {}
		for _, entry in ipairs(scanner.list_dir("/tmp/project")) do
			table.insert(names, entry.name)
		end

		assert.are.same({
			"dir3",
			"dir3-2",
			"dir3-3",
			"dir4",
			"dir5",
			"dir6",
			"dir10000",
			"images",
			"fuga.ts",
			"macky.ts",
			"minerva.png",
			"obsidia.png",
			"package.json",
			"README.md",
		}, names)
	end)
end)
