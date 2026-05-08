local config = require("etoile.config")
local path = require("etoile.path")

local M = {}

function M.snapshot(entries)
	local by_id = {}
	local ordered = {}
	for _, entry in ipairs(entries) do
		local item = {
			id = entry.id or entry.path,
			path = entry.path,
			name = entry.name,
			type = entry.type,
			depth = entry.depth,
		}
		by_id[item.id] = item
		table.insert(ordered, item)
	end
	return {
		by_id = by_id,
		ordered = ordered,
	}
end

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function line_text(item)
	if type(item) == "table" then
		return item.line or ""
	end
	return item or ""
end

local function line_id(item)
	if type(item) == "table" then
		return item.id
	end
	return nil
end

local function line_mark_id(item)
	if type(item) == "table" then
		return item.mark_id
	end
	return nil
end

local function parse_line(item)
	local line = line_text(item)
	if trim(line) == "" then
		return nil
	end

	local spaces = line:match("^%s*") or ""
	local depth = math.floor(#spaces / config.options.indent)
	local rest = line:sub(#spaces + 1)
	rest = trim(rest)
	local explicit_directory = rest:sub(-1) == "/"
	if explicit_directory then
		rest = trim(rest:sub(1, -2))
	end

	if rest == "" then
		return nil
	end

	return {
		id = line_id(item),
		mark_id = line_mark_id(item),
		depth = depth,
		name = rest,
		explicit_directory = explicit_directory,
	}
end

local function parse_lines(lines)
	local parsed_lines = {}
	local source_indexes = {}

	for index, line in ipairs(lines) do
		local parsed = parse_line(line)
		if parsed then
			table.insert(parsed_lines, parsed)
			table.insert(source_indexes, index)
		end
	end

	for index, parsed in ipairs(parsed_lines) do
		local next_line = parsed_lines[index + 1]
		parsed.type = (parsed.explicit_directory or (next_line and next_line.depth > parsed.depth)) and "directory"
			or "file"
		parsed.source_index = source_indexes[index]
	end

	return parsed_lines
end

local function new_path_for(root, stack, parsed)
	local parts = { root }
	for i = 0, parsed.depth - 1 do
		if stack[i] then
			table.insert(parts, stack[i].name)
		end
	end
	table.insert(parts, parsed.name)
	return path.join(unpack(parts))
end

local function normalize_snapshot(snapshot)
	if snapshot.by_id then
		return snapshot
	end
	return M.snapshot(snapshot)
end

local function normalize_parsed_tree(root, parsed_lines)
	local stack = {}
	for _, parsed in ipairs(parsed_lines) do
		parsed.path = new_path_for(root, stack, parsed)
		if parsed.type == "directory" then
			stack[parsed.depth] = parsed
		end
		for depth = parsed.depth + 1, 100 do
			stack[depth] = nil
		end
	end
	return parsed_lines
end

local function entry_type_for(entry, parsed)
	if entry and entry.type == "directory" then
		return "directory"
	end
	return parsed.type
end

function M.diff(root, snapshot, lines)
	snapshot = normalize_snapshot(snapshot or {})
	local parsed_lines = normalize_parsed_tree(root, parse_lines(lines))
	local refs = {}
	for _, parsed in ipairs(parsed_lines) do
		if parsed.id then
			refs[parsed.id] = refs[parsed.id] or {}
			table.insert(refs[parsed.id], parsed)
		end
	end

	local used = {}
	local ops = {}

	for _, entry in ipairs(snapshot.ordered) do
		local destinations = refs[entry.id]
		if destinations and #destinations > 0 then
			used[entry.id] = true
			local exact_destination = nil
			for _, destination in ipairs(destinations) do
				if path.normalize(destination.path) == path.normalize(entry.path) then
					exact_destination = destination
					break
				end
			end

			if #destinations == 1 then
				local destination = destinations[1]
				if path.normalize(destination.path) ~= path.normalize(entry.path) then
					table.insert(ops, {
						type = "move",
						from = entry.path,
						to = destination.path,
						entry_type = entry_type_for(entry, destination),
					})
				end
			elseif exact_destination then
				for _, destination in ipairs(destinations) do
					if destination ~= exact_destination then
						table.insert(ops, {
							type = "copy",
							from = entry.path,
							to = destination.path,
							entry_type = entry_type_for(entry, destination),
						})
					end
				end
			else
				table.insert(ops, {
					type = "move",
					from = entry.path,
					to = destinations[1].path,
					entry_type = entry_type_for(entry, destinations[1]),
				})
				for index = 2, #destinations do
					table.insert(ops, {
						type = "copy",
						from = destinations[1].path,
						to = destinations[index].path,
						entry_type = entry_type_for(entry, destinations[index]),
					})
				end
			end
		end
	end

	for _, entry in ipairs(snapshot.ordered) do
		if not used[entry.id] then
			table.insert(ops, {
				type = "delete",
				path = entry.path,
				entry_type = entry.type,
			})
		end
	end

	for _, parsed in ipairs(parsed_lines) do
		if not parsed.id or not snapshot.by_id[parsed.id] then
			table.insert(ops, {
				type = "create",
				path = parsed.path,
				entry_type = parsed.type,
			})
		end
	end

	return M.filter_redundant_ops(ops)
end

function M.filter_redundant_ops(ops)
	local moves = {}
	local copies = {}
	for _, op in ipairs(ops) do
		if op.type == "move" then
			table.insert(moves, op)
		elseif op.type == "copy" then
			table.insert(copies, op)
		end
	end

	local expanded_directory_copies = {}
	for _, op in ipairs(copies) do
		if op.entry_type == "directory" then
			for _, child in ipairs(ops) do
				local child_path = child.to or child.path
				if child ~= op and child_path and path.is_ancestor(op.to, child_path) then
					expanded_directory_copies[op] = true
					break
				end
			end
		end
	end

	local filtered = {}
	for _, op in ipairs(ops) do
		local redundant = false
		if op.type == "move" then
			for _, parent in ipairs(moves) do
				if parent ~= op and path.is_ancestor(parent.from, op.from) then
					redundant = true
					break
				end
			end
		end
		if op.type == "copy" then
			if expanded_directory_copies[op] then
				table.insert(filtered, {
					type = "create",
					path = op.to,
					entry_type = "directory",
				})
				redundant = true
			end
			for _, parent in ipairs(copies) do
				if
					not expanded_directory_copies[parent]
					and parent ~= op
					and path.is_ancestor(parent.from, op.from)
					and path.is_ancestor(parent.to, op.to)
				then
					redundant = true
					break
				end
			end
		end
		if not redundant then
			table.insert(filtered, op)
		end
	end

	return filtered
end

local function copy_file(from, to)
	if vim.fn.isdirectory(to) == 1 or vim.fn.filereadable(to) == 1 then
		return false, "Destination already exists: " .. to
	end

	vim.fn.mkdir(path.dirname(to), "p")
	local input, input_err = io.open(from, "rb")
	if not input then
		return false, input_err
	end
	local output, output_err = io.open(to, "wb")
	if not output then
		input:close()
		return false, output_err
	end

	output:write(input:read("*a"))
	input:close()
	output:close()
	return true
end

local function copy_directory(from, to)
	if vim.fn.isdirectory(to) == 1 or vim.fn.filereadable(to) == 1 then
		return false, "Destination already exists: " .. to
	end

	vim.fn.mkdir(to, "p")
	for _, item in ipairs(vim.fn.readdir(from)) do
		local child_from = path.join(from, item)
		local child_to = path.join(to, item)
		if vim.fn.isdirectory(child_from) == 1 then
			local ok, err = copy_directory(child_from, child_to)
			if not ok then
				return ok, err
			end
		else
			local ok, err = copy_file(child_from, child_to)
			if not ok then
				return ok, err
			end
		end
	end
	return true
end

local function display_width(line)
	if vim and vim.fn and vim.fn.strdisplaywidth then
		return vim.fn.strdisplaywidth(line)
	end
	return #line
end

local function setup_delete_confirm_highlights()
	vim.api.nvim_set_hl(0, "EtoileDeleteConfirm", { fg = "#ffd7d7", bg = "#2a171a" })
	vim.api.nvim_set_hl(0, "EtoileDeleteConfirmBorder", { fg = "#ff5f5f", bg = "#2a171a" })
	vim.api.nvim_set_hl(0, "EtoileDeleteConfirmTitle", { fg = "#ffffff", bg = "#8b1a1a", bold = true })
	vim.api.nvim_set_hl(0, "EtoileDeleteConfirmPath", { fg = "#ffaf5f", bg = "#2a171a" })
	vim.api.nvim_set_hl(0, "EtoileDeleteConfirmButton", { fg = "#ffffff", bg = "#8b1a1a", bold = true })
end

local function delete_confirm_lines(deletes, root)
	local lines = { "Delete " .. #deletes .. " item(s)?", "" }
	for _, delete_path in ipairs(deletes) do
		local display_path = root and path.relative(delete_path, root) or delete_path
		table.insert(lines, "- " .. display_path)
	end
	table.insert(lines, "")
	table.insert(lines, "[y] Delete    [Enter/n] Cancel")
	return lines
end

local function delete_confirm_config(lines)
	local width = 1
	for _, line in ipairs(lines) do
		width = math.max(width, display_width(line))
	end
	width = math.max(34, width + 4)
	width = math.min(width, math.max(1, vim.o.columns - 4))

	return {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		title = " Destructive Delete ",
		title_pos = "center",
	}
end

local function confirm_delete(deletes, opts)
	if opts.confirm_delete_fn then
		return opts.confirm_delete_fn(delete_confirm_lines(deletes, opts.root))
	end

	local lines = delete_confirm_lines(deletes, opts.root)
	setup_delete_confirm_highlights()

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local win = vim.api.nvim_open_win(buf, true, delete_confirm_config(lines))
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })
	vim.api.nvim_set_option_value(
		"winhighlight",
		"NormalFloat:EtoileDeleteConfirm,FloatBorder:EtoileDeleteConfirmBorder,FloatTitle:EtoileDeleteConfirmTitle",
		{ win = win }
	)

	for line = 3, #lines - 2 do
		vim.api.nvim_buf_add_highlight(buf, 0, "EtoileDeleteConfirmPath", line - 1, 0, -1)
	end
	vim.api.nvim_buf_add_highlight(buf, 0, "EtoileDeleteConfirmButton", #lines - 1, 0, -1)

	local ok = false
	while true do
		local key = vim.fn.getcharstr()
		if key == "y" or key == "Y" then
			ok = true
			break
		end
		if key == "n" or key == "N" or key == "\r" or key == "\27" or key == "q" then
			break
		end
	end

	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	return ok
end

function M.apply(ops, opts)
	opts = opts or {}
	local deletes = {}
	for _, op in ipairs(ops) do
		if op.type == "delete" then
			table.insert(deletes, op.path)
		end
	end

	if #deletes > 0 and opts.confirm_delete then
		if not confirm_delete(deletes, opts) then
			return false, "Delete canceled"
		end
	end

	for _, op in ipairs(ops) do
		if op.type == "delete" then
			local flag = op.entry_type == "directory" and "rf" or ""
			vim.fn.delete(op.path, flag)
		end
	end

	for _, op in ipairs(ops) do
		if op.type == "move" then
			vim.fn.mkdir(path.dirname(op.to), "p")
			local result = vim.fn.rename(op.from, op.to)
			if result ~= 0 then
				return false, "Failed to move: " .. op.from .. " -> " .. op.to
			end
		end
	end

	for _, op in ipairs(ops) do
		if op.type == "copy" then
			local ok, err
			if op.entry_type == "directory" then
				ok, err = copy_directory(op.from, op.to)
			else
				ok, err = copy_file(op.from, op.to)
			end
			if not ok then
				return false, err or ("Failed to copy: " .. op.from .. " -> " .. op.to)
			end
		end
	end

	for _, op in ipairs(ops) do
		if op.type == "create" then
			if op.entry_type == "directory" then
				vim.fn.mkdir(op.path, "p")
			else
				vim.fn.mkdir(path.dirname(op.path), "p")
				local file, err = io.open(op.path, "a")
				if not file then
					return false, err
				end
				file:close()
			end
		end
	end

	return true
end

return M
