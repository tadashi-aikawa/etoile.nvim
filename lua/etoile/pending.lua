local path = require("etoile.path")
local scanner = require("etoile.scanner")

local M = {}

local function clone_op(op)
	local copy = {}
	for key, value in pairs(op) do
		copy[key] = value
	end
	return copy
end

local function replace_prefix(value, from, to)
	if value == from then
		return to
	end
	if path.is_ancestor(from, value) then
		return path.join(to, value:sub(#from + 2))
	end
	return value
end

local function op_target(op)
	return op.to or op.path
end

local function rewrite_targets(ops, from, to, except)
	for _, op in ipairs(ops) do
		if op ~= except then
			if op.path then
				op.path = replace_prefix(op.path, from, to)
			end
			if op.to then
				op.to = replace_prefix(op.to, from, to)
			end
		end
	end
end

local function target_matches(op, target)
	local current = op_target(op)
	return current == target or path.is_ancestor(current, target)
end

local function remove_descendant_targets(ops, target)
	local kept = {}
	for _, op in ipairs(ops) do
		local current = op_target(op)
		if not path.is_ancestor(target, current) then
			table.insert(kept, op)
		end
	end
	return kept
end

local function append_delete(ops, incoming)
	local next_ops = {}
	local consumed = false

	for _, op in ipairs(ops) do
		if target_matches(op, incoming.path) then
			if op.type == "create" or op.type == "copy" then
				consumed = true
			elseif op.type == "move" then
				table.insert(next_ops, {
					type = "delete",
					path = op.from,
					entry_type = op.entry_type,
				})
				consumed = true
			else
				table.insert(next_ops, op)
				consumed = true
			end
		else
			table.insert(next_ops, op)
		end
	end

	next_ops = remove_descendant_targets(next_ops, incoming.path)
	if not consumed then
		table.insert(next_ops, clone_op(incoming))
	end
	return next_ops
end

local function append_move(ops, incoming)
	for _, op in ipairs(ops) do
		if target_matches(op, incoming.from) then
			local old_target = op_target(op)
			local new_target = replace_prefix(incoming.from, incoming.from, incoming.to)
			if op.type == "create" then
				op.path = replace_prefix(op.path, incoming.from, incoming.to)
			elseif op.type == "copy" or op.type == "move" then
				op.to = replace_prefix(op.to, incoming.from, incoming.to)
			end
			rewrite_targets(ops, old_target, new_target, op)
			return ops
		end
	end

	table.insert(ops, clone_op(incoming))
	rewrite_targets(ops, incoming.from, incoming.to, ops[#ops])
	return ops
end

local function append_plain(ops, incoming)
	table.insert(ops, clone_op(incoming))
	return ops
end

local function append_copy(ops, incoming)
	for index, op in ipairs(ops) do
		if op.type == "delete" and op.path == incoming.from then
			ops[index] = {
				type = "move",
				from = incoming.from,
				to = incoming.to,
				entry_type = incoming.entry_type,
			}
			return ops
		end
	end

	return append_plain(ops, incoming)
end

function M.normalize(ops)
	local result = {}
	for _, op in ipairs(ops or {}) do
		if op.type == "delete" then
			result = append_delete(result, op)
		elseif op.type == "move" then
			result = append_move(result, op)
		elseif op.type == "copy" then
			result = append_copy(result, op)
		else
			result = append_plain(result, op)
		end
	end
	local editor = require("etoile.editor")
	if editor.filter_redundant_ops then
		result = editor.filter_redundant_ops(result)
	end
	local deduped = {}
	local seen = {}
	for _, op in ipairs(result) do
		local key = table.concat({
			op.type or "",
			op.path or "",
			op.from or "",
			op.to or "",
			op.entry_type or "",
		}, "\0")
		if not seen[key] then
			seen[key] = true
			table.insert(deduped, op)
		end
	end
	return deduped
end

function M.merge(existing, incoming)
	local merged = {}
	for _, op in ipairs(existing or {}) do
		table.insert(merged, clone_op(op))
	end
	for _, op in ipairs(incoming or {}) do
		table.insert(merged, clone_op(op))
	end
	return M.normalize(merged)
end

local function hidden_by_ops(entry_path, ops)
	for _, op in ipairs(ops or {}) do
		local hidden = op.type == "delete" and op.path or op.type == "move" and op.from or nil
		if hidden and (entry_path == hidden or path.is_ancestor(hidden, entry_path)) then
			return true
		end
	end
	return false
end

local function mapping_for(dir, ops)
	local best
	for _, op in ipairs(ops or {}) do
		if (op.type == "move" or op.type == "copy") and op.entry_type == "directory" then
			if dir == op.to or path.is_ancestor(op.to, dir) then
				if not best or #op.to > #best.to then
					best = op
				end
			end
		end
	end
	return best
end

local function transformed_source_dir(dir, ops)
	local mapping = mapping_for(dir, ops)
	if not mapping then
		return dir, nil
	end
	if dir == mapping.to then
		return mapping.from, mapping
	end
	return path.join(mapping.from, dir:sub(#mapping.to + 2)), mapping
end

local function entry_for_path(entry_path, entry_type, source_path)
	return {
		path = entry_path,
		name = path.basename(entry_path),
		type = entry_type,
		symlink = false,
		source_path = source_path,
	}
end

local function created_child_entries(dir, ops)
	local by_path = {}
	for _, op in ipairs(ops or {}) do
		local target = op_target(op)
		if
			target
			and path.dirname(target) == dir
			and (op.type == "create" or op.type == "move" or op.type == "copy")
		then
			by_path[target] = entry_for_path(target, op.entry_type, op.from)
		end
	end
	local entries = {}
	for _, entry in pairs(by_path) do
		table.insert(entries, entry)
	end
	return entries
end

function M.list_dir(dir, opts)
	opts = opts or {}
	local ops = opts.pending_ops or {}
	local source_dir, mapping = transformed_source_dir(dir, ops)
	local entries = scanner.list_dir(source_dir, opts)
	local result = {}
	local seen = {}

	for _, entry in ipairs(entries) do
		local item = vim.deepcopy(entry)
		if mapping then
			item.path = path.join(dir, path.relative(entry.path, source_dir))
			item.name = path.basename(item.path)
			item.source_path = entry.path
		end
		if not hidden_by_ops(item.path, ops) then
			seen[item.path] = true
			table.insert(result, item)
		end
	end

	for _, entry in ipairs(created_child_entries(dir, ops)) do
		if not seen[entry.path] and not hidden_by_ops(entry.path, ops) then
			table.insert(result, entry)
		end
	end

	if scanner.sort_entries then
		return scanner.sort_entries(result)
	end
	table.sort(result, function(a, b)
		return a.path < b.path
	end)
	return result
end

return M
