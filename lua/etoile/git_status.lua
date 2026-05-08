local path = require("etoile.path")

local M = {}

local priority = {
	ignored = 0,
	modified = 1,
	added = 2,
	renamed = 4,
	deleted = 5,
	conflicted = 6,
}

local function merge_status(left, right)
	if not left then
		return right
	end
	if not right then
		return left
	end
	return priority[left] >= priority[right] and left or right
end

local function classify(index, worktree)
	local code = (index or " ") .. (worktree or " ")
	if code == "??" then
		return "added"
	end
	if code == "!!" then
		return "ignored"
	end
	if index == "U" or worktree == "U" or code == "AA" or code == "DD" then
		return "conflicted"
	end
	if index == "D" or worktree == "D" then
		return "deleted"
	end
	if index == "R" or worktree == "R" or index == "C" or worktree == "C" then
		return "renamed"
	end
	if index == "A" or worktree == "A" then
		return nil
	end
	if index == "M" or worktree == "M" or index == "T" or worktree == "T" then
		return "modified"
	end
	return nil
end

local function git_status_output(root, opts)
	local cmd = { "git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all" }
	if opts.show_ignored then
		table.insert(cmd, "--ignored=matching")
	end
	if type(vim.system) == "function" then
		local result = vim.system(cmd, { text = true }):wait()
		if result.code ~= 0 then
			return nil
		end
		return result.stdout or ""
	end

	if not vim.fn or type(vim.fn.system) ~= "function" then
		return nil
	end
	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return output
end

local function add_status(result, full_path, status)
	result.by_path[full_path] = merge_status(result.by_path[full_path], status)

	if status == "ignored" then
		return
	end

	local dir = path.dirname(full_path)
	while dir and (dir == result.root or path.is_ancestor(result.root, dir)) do
		result.by_path[dir] = merge_status(result.by_path[dir], status)
		if dir == result.root then
			break
		end
		dir = path.dirname(dir)
	end
end

function M.collect(root, opts)
	opts = opts or {}
	root = path.normalize(root)
	local output = git_status_output(root, opts)
	local result = {
		root = root,
		by_path = {},
	}
	if not output or output == "" then
		return result
	end

	local records = vim.split(output, "\0", { plain = true, trimempty = true })
	local index = 1
	while index <= #records do
		local record = records[index]
		local status = classify(record:sub(1, 1), record:sub(2, 2))
		local rel = record:sub(4)
		if status and rel ~= "" then
			add_status(result, path.join(root, rel), status)
		end
		if record:sub(1, 1) == "R" or record:sub(1, 1) == "C" then
			index = index + 1
			local rel_from = records[index]
			if status and rel_from and rel_from ~= "" then
				add_status(result, path.join(root, rel_from), status)
			end
		end
		index = index + 1
	end

	return result
end

function M.status_for(statuses, full_path)
	if not statuses then
		return nil
	end
	full_path = path.normalize(full_path)
	local status = statuses.by_path[full_path]
	if status then
		return status
	end

	local dir = path.dirname(full_path)
	while dir and (dir == statuses.root or path.is_ancestor(statuses.root, dir)) do
		if statuses.by_path[dir] == "ignored" then
			return "ignored"
		end
		if dir == statuses.root then
			break
		end
		dir = path.dirname(dir)
	end
	return nil
end

return M
