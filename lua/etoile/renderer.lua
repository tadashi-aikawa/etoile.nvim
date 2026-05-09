local config = require("etoile.config")
local git_status = require("etoile.git_status")
local icons = require("etoile.icons")
local scanner = require("etoile.scanner")

local M = {}

M.id_ns = vim.api.nvim_create_namespace("etoile_id")
M.decor_ns = vim.api.nvim_create_namespace("etoile_decor")

local function display_width(line)
	if vim and vim.fn and vim.fn.strdisplaywidth then
		return vim.fn.strdisplaywidth(line)
	end
	return #line
end

local function virt_text_width(chunks)
	local width = 0
	for _, chunk in ipairs(chunks) do
		width = width + display_width(chunk[1])
	end
	return width
end

local function set_id_extmark(buf, line)
	return vim.api.nvim_buf_set_extmark(buf, M.id_ns, line, 0, {
		right_gravity = false,
		invalidate = true,
		undo_restore = true,
	})
end

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.setup_highlights()
	vim.api.nvim_set_hl(0, "EtoileDirectoryIcon", { default = true, link = "Directory" })
	vim.api.nvim_set_hl(0, "EtoileSymlinkIcon", { default = true, link = "Identifier" })
	vim.api.nvim_set_hl(0, "EtoileSearchMatch", { default = true, link = "Search" })
	vim.api.nvim_set_hl(0, "EtoileSearchCurrent", { default = true, link = "IncSearch" })
	vim.api.nvim_set_hl(0, "EtoileSearchIndex", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "EtoileGitModified", { default = true, fg = "#61AFEF" })
	vim.api.nvim_set_hl(0, "EtoileGitAdded", { default = true, fg = "#98C379" })
	vim.api.nvim_set_hl(0, "EtoileGitDeleted", { default = true, link = "Removed" })
	vim.api.nvim_set_hl(0, "EtoileGitRenamed", { default = true, link = "Identifier" })
	vim.api.nvim_set_hl(0, "EtoileGitIgnored", { default = true, link = "Comment" })
	vim.api.nvim_set_hl(0, "EtoileGitConflicted", { default = true, link = "Error" })
end

local function git_highlight(status)
	if not status then
		return nil
	end
	return "EtoileGit" .. status:sub(1, 1):upper() .. status:sub(2)
end

local function git_decoration(entry)
	local left_padding = config.options.float.left_padding or 0
	if left_padding <= 0 then
		return nil
	end

	local status = entry.git_status
	if not status then
		return { string.rep(" ", left_padding), "Normal" }
	end

	local icon = (config.options.icons.git_status or {})[status] or "?"
	local suffix_width = math.max(1, left_padding - display_width(icon))
	local hl = git_highlight(status)
	return { icon .. string.rep(" ", suffix_width), hl }
end

local function highlight_git_name(buf, line, entry)
	local hl = git_highlight(entry.git_status)
	if not hl then
		return
	end

	local start_col = entry.name_col or 0
	local end_col = start_col + #(entry.name or "")
	if end_col <= start_col then
		return
	end

	vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, start_col, {
		end_col = end_col,
		hl_group = hl,
		priority = 80,
	})
end

local function line_for(entry, depth)
	local indent = string.rep(" ", depth * config.options.indent)
	local decoration = {}

	if entry.symlink then
		local link_icon, link_hl = icons.link_icon()
		table.insert(decoration, { link_icon .. " ", link_hl })
	end

	local icon, icon_hl = icons.icon_for(entry)
	table.insert(decoration, { icon .. " ", icon_hl })

	return indent .. entry.name, decoration
end

local function leading_spaces(value)
	return value:match("^%s*") or ""
end

local function parse_line(value)
	local name = trim(value)
	if name == "" then
		return nil
	end

	local explicit_directory = name:sub(-1) == "/"
	if explicit_directory then
		name = trim(name:sub(1, -2))
	end
	if name == "" then
		return nil
	end

	return {
		name = name,
		depth = math.floor(#leading_spaces(value) / config.options.indent),
		name_col = #leading_spaces(value),
		explicit_directory = explicit_directory,
	}
end

local function parsed_lines(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local parsed = {}
	for index, line in ipairs(lines) do
		local item = parse_line(line)
		if item then
			item.line = index
			item.raw = line
			table.insert(parsed, item)
		end
	end

	for index, item in ipairs(parsed) do
		local next_item = parsed[index + 1]
		item.type = (item.explicit_directory or (next_item and next_item.depth > item.depth)) and "directory" or "file"
	end

	return parsed
end

local function blank_line_indent(buf, line)
	local lines = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)
	local raw = lines[1]
	if raw == nil or trim(raw) ~= "" then
		return nil
	end

	return #leading_spaces(raw)
end

local function entry_for_current_line(parsed, entry)
	if entry and parsed.name == entry.name then
		local copy = vim.deepcopy(entry)
		copy.name_col = parsed.name_col
		copy.searchable = true
		return copy
	end

	local copy = entry and vim.deepcopy(entry) or {}
	copy.name = parsed.name
	copy.type = entry and entry.type == "directory" and "directory" or parsed.type
	copy.symlink = false
	copy.path = (entry and entry.path) or parsed.name
	copy.name_col = parsed.name_col
	copy.searchable = false

	local _, decoration = line_for(copy, parsed.depth)
	copy.decoration = decoration
	return copy
end

local function entry_for_blank_line(name_col)
	local _, decoration = line_for({
		name = "",
		type = "file",
		symlink = false,
	}, math.floor(name_col / config.options.indent))
	return {
		decoration = decoration,
		git_decoration = { git_decoration({}) },
		name_col = name_col,
	}
end

function M.render(root, expanded, opts)
	opts = opts or {}
	local lines = {}
	local entries = {}
	local max_width = 1
	local statuses = opts.git_statuses
		or git_status.collect(root, { show_ignored = config.options.git_status.show_ignored })

	local function add_dir(dir, depth)
		for _, entry in ipairs(scanner.list_dir(dir, { root = root, exclude = opts.exclude })) do
			entry.open = entry.type == "directory" and expanded[entry.path] or false
			entry.git_status = git_status.status_for(statuses, entry.path)
			local line, decoration = line_for(entry, depth)
			entry.id = entry.path
			entry.depth = depth
			entry.line = line
			entry.decoration = decoration
			entry.git_decoration = { git_decoration(entry) }
			entry.name_col = depth * config.options.indent
			table.insert(lines, line)
			table.insert(entries, entry)
			max_width = math.max(
				max_width,
				virt_text_width(entry.git_decoration) + virt_text_width(decoration) + display_width(line)
			)

			if entry.type == "directory" and expanded[entry.path] then
				add_dir(entry.path, depth + 1)
			end
		end
	end

	add_dir(root, 0)
	if #lines == 0 then
		lines = { "" }
	end

	return {
		lines = lines,
		entries = entries,
		max_width = max_width,
	}
end

function M.refresh_git_status(root, rendered)
	local statuses = git_status.collect(root, { show_ignored = config.options.git_status.show_ignored })
	local max_width = 1
	for _, entry in ipairs(rendered.entries or {}) do
		entry.git_status = git_status.status_for(statuses, entry.path)
		entry.git_decoration = { git_decoration(entry) }
		max_width = math.max(
			max_width,
			virt_text_width(entry.git_decoration)
				+ virt_text_width(entry.decoration or {})
				+ display_width(entry.line or "")
		)
	end
	rendered.max_width = max_width
end

local function search_highlight_for(entry, search)
	if not search or not search.matches_by_path then
		return nil
	end
	if search.current_path == entry.path then
		return "EtoileSearchCurrent"
	end
	if search.matches_by_path[entry.path] then
		return "EtoileSearchMatch"
	end
	return nil
end

local function search_index_decoration_for(entry, search)
	if not search or not search.match_index_by_path or not search.total then
		return nil
	end
	local index = search.match_index_by_path[entry.path]
	if not index then
		return nil
	end
	return { { (" [%d/%d]"):format(index, search.total), "EtoileSearchIndex" } }
end

function M.decorate(buf, entries, search)
	M.setup_highlights()
	vim.api.nvim_buf_clear_namespace(buf, M.id_ns, 0, -1)
	return M.reset_decorations(buf, entries, search, true)
end

function M.reset_decorations(buf, entries, search, create_ids)
	vim.api.nvim_buf_clear_namespace(buf, M.decor_ns, 0, -1)
	local mark_ids = {}

	for index, entry in ipairs(entries) do
		local line = index - 1
		if create_ids then
			local mark_id = set_id_extmark(buf, line)
			mark_ids[mark_id] = entry.id
		end

		local search_hl = search_highlight_for(entry, search)
		if search_hl then
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, 0, {
				line_hl_group = search_hl,
				priority = 50,
			})
		end
		local search_index_decoration = search_index_decoration_for(entry, search)
		if search_index_decoration then
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, 0, {
				virt_text = search_index_decoration,
				virt_text_pos = "eol",
				priority = 90,
			})
		end
		highlight_git_name(buf, line, entry)

		if entry.decoration and #entry.decoration > 0 then
			if entry.git_decoration and #entry.git_decoration > 0 then
				vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, 0, {
					virt_text = entry.git_decoration,
					virt_text_pos = "inline",
					priority = 100,
				})
			end
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, entry.name_col or 0, {
				virt_text = entry.decoration,
				virt_text_pos = "inline",
				priority = 101,
			})
		end
	end

	return mark_ids
end

function M.lines_with_ids(buf, mark_ids)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, M.id_ns, 0, -1, { details = true })
	local marks_by_line = {}

	for _, mark in ipairs(extmarks) do
		local details = mark[4] or {}
		local id = mark_ids and mark_ids[mark[1]]
		local line = mark[2] + 1
		if id and not details.invalid and not marks_by_line[line] then
			marks_by_line[line] = {
				id = id,
				mark_id = mark[1],
			}
		end
	end

	local result = {}
	for index, line in ipairs(lines) do
		local mark = marks_by_line[index] or {}
		table.insert(result, {
			line = line,
			id = mark.id,
			mark_id = mark.mark_id,
		})
	end
	return result
end

function M.entry_at_line(buf, line, entries_by_id, mark_ids)
	local rows = M.lines_with_ids(buf, mark_ids)
	local item = rows[line]
	if not item then
		return nil
	end

	local parsed = parse_line(item.line)
	if not parsed then
		return nil
	end
	parsed.raw = item.line
	local next_item = rows[line + 1] and parse_line(rows[line + 1].line) or nil
	parsed.type = (parsed.explicit_directory or (next_item and next_item.depth > parsed.depth)) and "directory"
		or "file"

	return entry_for_current_line(parsed, item.id and entries_by_id[item.id] or nil)
end

function M.ids_by_line(buf, mark_ids)
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, M.id_ns, 0, -1, { details = true })
	local result = {}

	for _, mark in ipairs(extmarks) do
		local details = mark[4] or {}
		local id = mark_ids and mark_ids[mark[1]]
		local line = mark[2] + 1
		if id and not details.invalid and not result[line] then
			result[line] = id
		end
	end

	return result
end

function M.entries_by_id(entries)
	local result = {}
	for _, entry in ipairs(entries) do
		result[entry.id] = entry
	end
	return result
end

local function matching_entry_id(parsed, entries_by_id, used_ids, released_ids)
	for id, entry in pairs(entries_by_id) do
		if
			released_ids[id]
			and not used_ids[id]
			and entry.name == parsed.name
			and (entry.depth == nil or entry.depth == parsed.depth)
		then
			return id
		end
	end
	return nil
end

local function collect_invalid_line_ids(buf, entries_by_id, mark_ids, parsed)
	local valid_lines = {}
	for _, item in ipairs(parsed) do
		valid_lines[item.line] = true
	end

	local released_ids = {}
	for line, entry_id in pairs(M.ids_by_line(buf, mark_ids)) do
		if not valid_lines[line] and entries_by_id[entry_id] then
			released_ids[entry_id] = true
		end
	end
	return released_ids
end

function M.sync_decorations(buf, entries_by_id, mark_ids, search, yanked, current_line)
	local marks_by_line = M.ids_by_line(buf, mark_ids)
	local parsed = parsed_lines(buf)
	local yank_index = 1
	local used_ids = {}
	local released_ids = collect_invalid_line_ids(buf, entries_by_id, mark_ids, parsed)
	local resolved_ids = {}
	vim.api.nvim_buf_clear_namespace(buf, M.decor_ns, 0, -1)

	for _, item in ipairs(parsed) do
		local entry_id = marks_by_line[item.line]
		local original_entry_id = entry_id
		local entry = entry_id and entries_by_id[entry_id] or nil
		local matches_current_line = entry
			and entry.name == item.name
			and (entry.depth == nil or entry.depth == item.depth)
		local used_yank = false
		local yanked_entry_id = nil

		if yanked and yanked[yank_index] and yanked[yank_index].line == item.raw and not matches_current_line then
			entry_id = yanked[yank_index].id
			entry = entries_by_id[entry_id]
			matches_current_line = entry
				and entry.name == item.name
				and (entry.depth == nil or entry.depth == item.depth)
			yank_index = yank_index + 1
			used_yank = true
			yanked_entry_id = entry_id
			if original_entry_id and original_entry_id ~= entry_id then
				released_ids[original_entry_id] = true
			end
		end

		if not matches_current_line and (not entry or used_yank) then
			entry_id = matching_entry_id(item, entries_by_id, used_ids, released_ids)
			entry = entry_id and entries_by_id[entry_id] or nil
			matches_current_line = entry ~= nil
			if not matches_current_line and yanked_entry_id then
				entry_id = yanked_entry_id
				entry = entries_by_id[entry_id]
				matches_current_line = entry ~= nil
			end
		elseif entry then
			matches_current_line = true
		end

		if entry_id and matches_current_line then
			resolved_ids[item.line] = entry_id
			used_ids[entry_id] = true
		end

		entry = entry_for_current_line(item, entry_id and entries_by_id[entry_id] or nil)
		local search_hl = entry.searchable and search_highlight_for(entry, search) or nil
		if search_hl then
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, item.line - 1, 0, {
				line_hl_group = search_hl,
				priority = 50,
			})
		end
		local search_index_decoration = entry.searchable and search_index_decoration_for(entry, search) or nil
		if search_index_decoration then
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, item.line - 1, 0, {
				virt_text = search_index_decoration,
				virt_text_pos = "eol",
				priority = 90,
			})
		end
		highlight_git_name(buf, item.line - 1, entry)
		if entry.decoration and #entry.decoration > 0 then
			entry.git_decoration = { git_decoration(entry) }
			if entry.git_decoration and #entry.git_decoration > 0 then
				vim.api.nvim_buf_set_extmark(buf, M.decor_ns, item.line - 1, 0, {
					virt_text = entry.git_decoration,
					virt_text_pos = "inline",
					priority = 100,
				})
			end
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, item.line - 1, entry.name_col or 0, {
				virt_text = entry.decoration,
				virt_text_pos = "inline",
				priority = 101,
			})
		end
	end

	if current_line then
		local name_col = blank_line_indent(buf, current_line)
		if name_col then
			local entry = entry_for_blank_line(name_col)
			if entry.git_decoration and #entry.git_decoration > 0 then
				vim.api.nvim_buf_set_extmark(buf, M.decor_ns, current_line - 1, 0, {
					virt_text = entry.git_decoration,
					virt_text_pos = "inline",
					priority = 100,
				})
			end
			vim.api.nvim_buf_set_extmark(buf, M.decor_ns, current_line - 1, entry.name_col or 0, {
				virt_text = entry.decoration,
				virt_text_pos = "inline",
				priority = 101,
			})
		end
	end

	vim.api.nvim_buf_clear_namespace(buf, M.id_ns, 0, -1)
	if mark_ids then
		for mark_id in pairs(mark_ids) do
			mark_ids[mark_id] = nil
		end
	end
	for line, entry_id in pairs(resolved_ids) do
		local mark_id = set_id_extmark(buf, line - 1)
		if mark_ids then
			mark_ids[mark_id] = entry_id
		end
	end
end

return M
