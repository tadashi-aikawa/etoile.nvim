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
		fn = {
			glob2regpat = function(pattern)
				local result = "^"
				local i = 1
				local n = #pattern
				while i <= n do
					local c = pattern:sub(i, i)
					if c == "*" then
						if i < n and pattern:sub(i + 1, i + 1) == "*" then
							result = result .. ".*"
							i = i + 2
							if i <= n and pattern:sub(i, i) == "/" then
								i = i + 1
							end
						else
							result = result .. "[^/]*"
							i = i + 1
						end
					elseif c == "?" then
						result = result .. "[^/]"
						i = i + 1
					else
						result = result .. (c:gsub("([^%w])", "%%%1"))
						i = i + 1
					end
				end
				return result .. "$"
			end,
			match = function(str, pattern)
				local ok, pos = pcall(string.find, str, pattern)
				if ok and pos then
					return pos - 1
				end
				return -1
			end,
		},
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

	it("excludes entries matching exact names", function()
		reset_vim({
			{ name = ".git", type = "directory" },
			{ name = "node_modules", type = "directory" },
			{ name = "src", type = "directory" },
			{ name = "README.md", type = "file" },
		})

		local scanner = require("etoile.scanner")
		local names = {}
		for _, entry in ipairs(scanner.list_dir("/tmp/project", { exclude = { ".git", "node_modules" } })) do
			table.insert(names, entry.name)
		end

		assert.are.same({ "src", "README.md" }, names)
	end)

	it("excludes entries matching glob patterns", function()
		reset_vim({
			{ name = "dist", type = "directory" },
			{ name = "src", type = "directory" },
			{ name = "error.log", type = "file" },
			{ name = "access.log", type = "file" },
			{ name = "README.md", type = "file" },
		})

		local scanner = require("etoile.scanner")
		local names = {}
		for _, entry in ipairs(scanner.list_dir("/tmp/project", { exclude = { "*.log" } })) do
			table.insert(names, entry.name)
		end

		assert.are.same({ "dist", "src", "README.md" }, names)
	end)

	it("includes excluded entries with excluded=true flag when include_excluded is true", function()
		reset_vim({
			{ name = ".git", type = "directory" },
			{ name = "node_modules", type = "directory" },
			{ name = "src", type = "directory" },
			{ name = "README.md", type = "file" },
		})

		local scanner = require("etoile.scanner")
		local all_entries =
			scanner.list_dir("/tmp/project", { exclude = { ".git", "node_modules" }, include_excluded = true })
		local names = {}
		local excluded_flags = {}
		for _, entry in ipairs(all_entries) do
			table.insert(names, entry.name)
			excluded_flags[entry.name] = entry.excluded
		end

		assert.are.same({ ".git", "node_modules", "src", "README.md" }, names)
		assert.is_true(excluded_flags[".git"])
		assert.is_true(excluded_flags["node_modules"])
		assert.is_nil(excluded_flags["src"])
		assert.is_nil(excluded_flags["README.md"])
	end)
end)
