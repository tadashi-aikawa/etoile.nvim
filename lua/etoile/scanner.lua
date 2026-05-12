local path = require("etoile.path")

local M = {}

local uv = vim.uv or vim.loop

local function should_exclude(name, rel, exclude)
	for _, item in ipairs(exclude or {}) do
		local regex = vim.fn.glob2regpat(item)
		if vim.fn.match(name, regex) >= 0 or vim.fn.match(rel, regex) >= 0 then
			return true
		end
	end
	return false
end

function M.matches_exclude(name, rel, exclude)
	return should_exclude(name, rel, exclude)
end

local function entry_for(parent, name)
	local full_path = path.join(parent, name)
	local lstat = uv.fs_lstat(full_path)
	if not lstat then
		return nil
	end

	local stat = lstat.type == "link" and uv.fs_stat(full_path) or lstat
	local entry_type = stat and stat.type or lstat.type
	if entry_type ~= "directory" and entry_type ~= "file" then
		entry_type = "other"
	end

	return {
		path = full_path,
		name = name,
		type = entry_type,
		symlink = lstat.type == "link",
	}
end

local function natural_less(left, right)
	left = left:lower()
	right = right:lower()

	local left_index = 1
	local right_index = 1

	while left_index <= #left and right_index <= #right do
		local left_digit_start, left_digit_end = left:find("%d+", left_index)
		local right_digit_start, right_digit_end = right:find("%d+", right_index)

		if left_digit_start ~= left_index or right_digit_start ~= right_index then
			local left_chunk_end = (left_digit_start or (#left + 1)) - 1
			local right_chunk_end = (right_digit_start or (#right + 1)) - 1
			local left_chunk = left:sub(left_index, left_chunk_end)
			local right_chunk = right:sub(right_index, right_chunk_end)

			if left_chunk ~= right_chunk then
				return left_chunk < right_chunk
			end

			left_index = left_chunk_end + 1
			right_index = right_chunk_end + 1
		else
			local left_number = left:sub(left_digit_start, left_digit_end):gsub("^0+", "")
			local right_number = right:sub(right_digit_start, right_digit_end):gsub("^0+", "")
			if left_number == "" then
				left_number = "0"
			end
			if right_number == "" then
				right_number = "0"
			end

			if #left_number ~= #right_number then
				return #left_number < #right_number
			end
			if left_number ~= right_number then
				return left_number < right_number
			end

			local left_digits = left_digit_end - left_digit_start + 1
			local right_digits = right_digit_end - right_digit_start + 1
			if left_digits ~= right_digits then
				return left_digits < right_digits
			end

			left_index = left_digit_end + 1
			right_index = right_digit_end + 1
		end
	end

	return #left < #right
end

local function sort_entries(entries)
	table.sort(entries, function(a, b)
		if a.type == "directory" and b.type ~= "directory" then
			return true
		end
		if a.type ~= "directory" and b.type == "directory" then
			return false
		end
		return natural_less(a.name, b.name)
	end)
	return entries
end

function M.list_dir(dir, opts)
	opts = opts or {}
	local scan = uv.fs_scandir(dir)
	if not scan then
		return {}
	end

	local entries = {}
	while true do
		local name = uv.fs_scandir_next(scan)
		if not name then
			break
		end
		local full_path = path.join(dir, name)
		local rel = path.relative(full_path, opts.root or dir)
		if opts.include_excluded or not should_exclude(name, rel, opts.exclude) then
			local entry = entry_for(dir, name)
			if entry then
				if opts.include_excluded and should_exclude(name, rel, opts.exclude) then
					entry.excluded = true
				end
				table.insert(entries, entry)
			end
		end
	end

	return sort_entries(entries)
end

function M.scan_all(root, opts)
	opts = opts or {}
	local results = {}

	local function visit(dir)
		for _, entry in ipairs(M.list_dir(dir, { root = root, exclude = opts.exclude })) do
			table.insert(results, entry)
			if entry.type == "directory" and not entry.symlink then
				visit(entry.path)
			end
		end
	end

	visit(root)
	return results
end

return M
