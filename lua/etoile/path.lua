local M = {}

local sep = package.config:sub(1, 1)

function M.normalize(path)
	if vim and vim.fs and vim.fs.normalize then
		return vim.fs.normalize(path)
	end

	path = path:gsub(sep .. "+", sep)
	if #path > 1 then
		path = path:gsub(sep .. "$", "")
	end
	return path
end

function M.join(...)
	local parts = { ... }
	local result = table.concat(parts, sep)
	return M.normalize(result)
end

function M.basename(path)
	path = M.normalize(path)
	return path:match("([^" .. sep .. "]+)$") or path
end

function M.dirname(path)
	path = M.normalize(path)
	local dir = path:match("^(.*)" .. sep .. "[^" .. sep .. "]+$")
	if not dir or dir == "" then
		return sep
	end
	return dir
end

function M.relative(path, root)
	path = M.normalize(path)
	root = M.normalize(root)
	if path == root then
		return "."
	end
	if path:sub(1, #root + 1) == root .. sep then
		return path:sub(#root + 2)
	end
	return path
end

function M.is_ancestor(parent, child)
	parent = M.normalize(parent)
	child = M.normalize(child)
	return child:sub(1, #parent + 1) == parent .. sep
end

return M
