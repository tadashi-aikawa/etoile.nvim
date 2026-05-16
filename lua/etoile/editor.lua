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

local function split_id_prefix(line)
	local before, id, rest = line:match("^(%s*)(%d%d%d%d%d%d)%s(.*)$")
	if not id then
		return nil, line
	end
	return id, before .. rest
end

local function line_id(item)
	if type(item) == "table" then
		return item.id or split_id_prefix(item.line or "")
	end
	return nil
end

local function parse_line(item)
	local inline_id, line = split_id_prefix(line_text(item))
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
		id = line_id(item) or inline_id,
		depth = depth,
		name = rest,
		explicit_directory = explicit_directory,
	}
end

local function has_child(parsed_lines, index)
	local parsed = parsed_lines[index]
	local next_line = parsed_lines[index + 1]
	return parsed and next_line and next_line.depth > parsed.depth
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
		parsed.type = (parsed.explicit_directory or has_child(parsed_lines, index)) and "directory" or "file"
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

function M.diff(root, snapshot, lines, opts)
	opts = opts or {}
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
		if parsed.id and not snapshot.by_id[parsed.id] then
			local source_path = opts.paths_by_id and opts.paths_by_id[parsed.id]
			if source_path then
				table.insert(ops, {
					type = "copy",
					from = source_path,
					to = parsed.path,
					entry_type = (opts.types_by_id and opts.types_by_id[parsed.id]) or parsed.type,
				})
			end
		elseif not parsed.id then
			table.insert(ops, {
				type = "create",
				path = parsed.path,
				entry_type = parsed.type,
			})
		end
	end

	return M.filter_redundant_ops(ops)
end

function M.expanded_paths(root, lines)
	local parsed_lines = normalize_parsed_tree(root, parse_lines(lines))
	local expanded = {}

	for index, parsed in ipairs(parsed_lines) do
		if parsed.type == "directory" and has_child(parsed_lines, index) then
			expanded[parsed.path] = true
		end
	end

	return expanded
end

function M.path_at_line(root, lines, line)
	if not line then
		return nil
	end

	for _, parsed in ipairs(normalize_parsed_tree(root, parse_lines(lines))) do
		if parsed.source_index == line then
			return parsed.path
		end
	end

	return nil
end

function M.filter_redundant_ops(ops)
	local moves = {}
	local copies = {}
	local delete_dirs = {}
	for _, op in ipairs(ops) do
		if op.type == "move" then
			table.insert(moves, op)
		elseif op.type == "copy" then
			table.insert(copies, op)
		elseif op.type == "delete" and op.entry_type == "directory" then
			table.insert(delete_dirs, op)
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
		if op.type == "delete" then
			for _, parent in ipairs(delete_dirs) do
				if parent ~= op and path.is_ancestor(parent.path, op.path) then
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

local function path_covers(parent, child)
	return parent == child or path.is_ancestor(parent, child)
end

local function add_dependency(edges, indegree, before, after)
	if before == after or edges[before][after] then
		return
	end
	edges[before][after] = true
	indegree[after] = indegree[after] + 1
end

local apply_priority = {
	delete = 1,
	move = 2,
	copy = 3,
	create = 4,
}

local function sort_apply_ops(ops)
	local edges = {}
	local indegree = {}
	for index in ipairs(ops) do
		edges[index] = {}
		indegree[index] = 0
	end

	for delete_index, delete_op in ipairs(ops) do
		if delete_op.type == "delete" then
			for target_index, target_op in ipairs(ops) do
				if target_op.type == "move" or target_op.type == "copy" then
					if target_op.from and path_covers(delete_op.path, target_op.from) then
						add_dependency(edges, indegree, target_index, delete_index)
					elseif target_op.to and path_covers(delete_op.path, target_op.to) then
						add_dependency(edges, indegree, delete_index, target_index)
					end
				elseif
					target_op.type == "create"
					and target_op.path
					and path_covers(delete_op.path, target_op.path)
				then
					add_dependency(edges, indegree, delete_index, target_index)
				end
			end
		end
	end

	local pending = {}
	for index, op in ipairs(ops) do
		table.insert(pending, {
			index = index,
			priority = apply_priority[op.type] or 99,
		})
	end

	local sorted = {}
	while #pending > 0 do
		table.sort(pending, function(left, right)
			local left_ready = indegree[left.index] == 0
			local right_ready = indegree[right.index] == 0
			if left_ready ~= right_ready then
				return left_ready
			end
			if left.priority ~= right.priority then
				return left.priority < right.priority
			end
			return left.index < right.index
		end)

		local item = table.remove(pending, 1)
		table.insert(sorted, ops[item.index])
		for to in pairs(edges[item.index]) do
			indegree[to] = indegree[to] - 1
		end
	end

	return sorted
end

local function display_width(line)
	if vim and vim.fn and vim.fn.strdisplaywidth then
		return vim.fn.strdisplaywidth(line)
	end
	return #line
end

local confirm_palettes = {
	delete = {
		normal = { fg = "#ffd7d7", bg = "#2a171a" },
		border = { fg = "#ff5f5f", bg = "#2a171a" },
		title = { fg = "#ffffff", bg = "#8b1a1a", bold = true },
		path = { fg = "#ffaf5f", bg = "#2a171a" },
		button = { fg = "#ffffff", bg = "#8b1a1a", bold = true },
	},
	move = {
		normal = { fg = "#fff2cc", bg = "#2b2411" },
		border = { fg = "#d7af00", bg = "#2b2411" },
		title = { fg = "#1c1600", bg = "#ffdf5f", bold = true },
		path = { fg = "#ffd75f", bg = "#2b2411" },
		button = { fg = "#1c1600", bg = "#ffdf5f", bold = true },
	},
	copy = {
		normal = { fg = "#d7ffdf", bg = "#102418" },
		border = { fg = "#5fd787", bg = "#102418" },
		title = { fg = "#ffffff", bg = "#23804a", bold = true },
		path = { fg = "#87d7af", bg = "#102418" },
		button = { fg = "#ffffff", bg = "#23804a", bold = true },
	},
	create = {
		normal = { fg = "#d7ffdf", bg = "#102418" },
		border = { fg = "#5fd787", bg = "#102418" },
		title = { fg = "#ffffff", bg = "#23804a", bold = true },
		path = { fg = "#87d7af", bg = "#102418" },
		button = { fg = "#ffffff", bg = "#23804a", bold = true },
	},
}

local function confirm_severity(by_type)
	if #by_type.delete > 0 then
		return "delete"
	end
	if #by_type.move > 0 then
		return "move"
	end
	return "create"
end

local function setup_confirm_highlights(severity)
	local palette = confirm_palettes[severity] or confirm_palettes.delete
	vim.api.nvim_set_hl(0, "EtoileConfirm", palette.normal)
	vim.api.nvim_set_hl(0, "EtoileConfirmBorder", palette.border)
	vim.api.nvim_set_hl(0, "EtoileConfirmTitle", palette.title)
	vim.api.nvim_set_hl(0, "EtoileConfirmPath", palette.path)
	vim.api.nvim_set_hl(0, "EtoileConfirmButton", palette.button)
end

local function pluralize(count, singular, plural)
	return count .. " " .. (count == 1 and singular or plural)
end

local function count_directory_entries(dir)
	if not (vim and vim.fn and vim.fn.readdir and vim.fn.isdirectory) then
		return nil
	end

	local files = 0
	local dirs = 0

	local function visit(current)
		local ok, items = pcall(vim.fn.readdir, current)
		if not ok then
			return false
		end

		for _, item in ipairs(items) do
			local child = path.join(current, item)
			if vim.fn.isdirectory(child) == 1 then
				dirs = dirs + 1
				if not visit(child) then
					return false
				end
			else
				files = files + 1
			end
		end

		return true
	end

	if not visit(dir) then
		return nil
	end

	return files, dirs
end

local function delete_display_path(op, root)
	local display_path = root and path.relative(op.path, root) or op.path
	if op.entry_type == "directory" and display_path:sub(-1) ~= "/" then
		display_path = display_path .. "/"
	end

	local files, dirs = nil, nil
	if op.entry_type == "directory" then
		files, dirs = count_directory_entries(op.path)
	end
	if files and dirs then
		return display_path
			.. " ("
			.. pluralize(files, "file", "files")
			.. ", "
			.. pluralize(dirs, "dir", "dirs")
			.. ")"
	end

	return display_path
end

local function display_path(value, root, entry_type)
	local result = root and path.relative(value, root) or value
	if entry_type == "directory" and result:sub(-1) ~= "/" then
		result = result .. "/"
	end
	return result
end

local function operation_display_path(op, root)
	if op.type == "delete" then
		return delete_display_path(op, root)
	end
	if op.type == "move" or op.type == "copy" then
		return display_path(op.from, root, op.entry_type) .. " -> " .. display_path(op.to, root, op.entry_type)
	end
	return display_path(op.path, root, op.entry_type)
end

local confirm_labels = {
	delete = "Delete",
	move = "Move",
	copy = "Copy",
	create = "Create",
}

local function confirm_lines(by_type, root)
	local total = 0
	for _, op_type in ipairs({ "delete", "move", "copy", "create" }) do
		total = total + #by_type[op_type]
	end

	local lines = { "Apply " .. total .. " change(s)?", "" }
	for _, op_type in ipairs({ "delete", "move", "copy", "create" }) do
		local ops = by_type[op_type]
		if #ops > 0 then
			table.insert(lines, (confirm_labels[op_type] or op_type) .. " (" .. #ops .. ")")
			for _, op in ipairs(ops) do
				table.insert(lines, "- " .. operation_display_path(op, root))
			end
			table.insert(lines, "")
		end
	end
	table.insert(lines, "[y] Apply    [Enter/n] Cancel    [r] Revert")
	return lines
end

local function confirm_config(lines, severity)
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
		title = severity == "delete" and " Confirm Destructive Changes " or " Confirm Changes ",
		title_pos = "center",
	}
end

local function adjust_confirm_height(win, config, line_count)
	if not (vim.api and vim.api.nvim_win_text_height and vim.api.nvim_win_set_config) then
		return
	end

	local ok, text_height = pcall(vim.api.nvim_win_text_height, win, {
		start_row = 0,
		end_row = line_count - 1,
	})
	if not ok or not text_height or not text_height.all then
		return
	end

	local height = math.min(text_height.all, math.max(1, vim.o.lines - 4))
	if height == config.height then
		return
	end

	config.height = height
	config.row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	vim.api.nvim_win_set_config(win, config)
end

local function confirm_operations(by_type, opts)
	local severity = confirm_severity(by_type)
	local lines = confirm_lines(by_type, opts.root)
	local confirm_fn = opts.confirm_fn
	if confirm_fn then
		return confirm_fn(lines)
	end

	setup_confirm_highlights(severity)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local win_config = confirm_config(lines, severity)
	local win = vim.api.nvim_open_win(buf, true, win_config)
	vim.api.nvim_set_option_value("wrap", true, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })
	adjust_confirm_height(win, win_config, #lines)
	vim.api.nvim_set_option_value(
		"winhighlight",
		"NormalFloat:EtoileConfirm,FloatBorder:EtoileConfirmBorder,FloatTitle:EtoileConfirmTitle",
		{ win = win }
	)

	for line = 3, #lines - 2 do
		vim.api.nvim_buf_add_highlight(buf, 0, "EtoileConfirmPath", line - 1, 0, -1)
	end
	vim.api.nvim_buf_add_highlight(buf, 0, "EtoileConfirmButton", #lines - 1, 0, -1)

	local action = "cancel"
	while true do
		local key = vim.fn.getcharstr()
		if key == "y" or key == "Y" then
			action = "apply"
			break
		end
		if key == "r" or key == "R" then
			action = "revert"
			break
		end
		if key == "n" or key == "N" or key == "\r" or key == "\27" or key == "q" then
			break
		end
	end

	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	return action
end

function M.apply(ops, opts)
	opts = opts or {}
	local by_type = {
		delete = {},
		move = {},
		copy = {},
		create = {},
	}
	local confirmable = {
		delete = {},
		move = {},
		copy = {},
		create = {},
	}
	for _, op in ipairs(ops) do
		if by_type[op.type] then
			table.insert(by_type[op.type], op)
			if opts["confirm_" .. op.type] then
				table.insert(confirmable[op.type], op)
			end
		end
	end

	local confirm_count = #confirmable.delete + #confirmable.move + #confirmable.copy + #confirmable.create
	if confirm_count > 0 then
		local action = confirm_operations(by_type, opts)
		if action == false or action == nil or action == "cancel" then
			return false, "Apply canceled"
		end
		if action == "revert" then
			return false, "Apply reverted"
		end
	end

	for _, op in ipairs(sort_apply_ops(ops)) do
		if op.type == "delete" then
			local flag = op.entry_type == "directory" and "rf" or ""
			vim.fn.delete(op.path, flag)
		elseif op.type == "move" then
			vim.fn.mkdir(path.dirname(op.to), "p")
			local result = vim.fn.rename(op.from, op.to)
			if result ~= 0 then
				return false, "Failed to move: " .. op.from .. " -> " .. op.to
			end
		elseif op.type == "copy" then
			local ok, err
			if op.entry_type == "directory" then
				ok, err = copy_directory(op.from, op.to)
			else
				ok, err = copy_file(op.from, op.to)
			end
			if not ok then
				return false, err or ("Failed to copy: " .. op.from .. " -> " .. op.to)
			end
		elseif op.type == "create" then
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
