local config = require("etoile.config")
local git_status = require("etoile.git_status")
local icons = require("etoile.icons")
local scanner = require("etoile.scanner")

local M = {}

M.decor_ns = vim.api.nvim_create_namespace("etoile_decor")

local id_width = 6
local id_prefix_width = id_width + 1

local function split_id_prefix(line)
	local before, id, rest = line:match("^(%s*)(%d%d%d%d%d%d)%s(.*)$")
	if not id then
		return nil, line, nil, 0
	end
	return id, before .. rest, #before, id_prefix_width
end

function M.line_with_id(id, line)
	local indent = line:match("^%s*") or ""
	return indent .. id .. " " .. line:sub(#indent + 1)
end

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

local function conceal_id_prefix(buf, line, prefix_col, prefix_len)
	if not prefix_len or prefix_len <= 0 then
		return
	end
	prefix_col = prefix_col or 0
	vim.api.nvim_buf_set_extmark(buf, M.decor_ns, line, prefix_col, {
		end_col = prefix_col + prefix_len,
		conceal = "",
		priority = 120,
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
	local left_padding = config.options.tree.left_padding or 0
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
	local inline_id, text, prefix_col, prefix_len = split_id_prefix(value)
	local name = trim(text)
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
		id = inline_id,
		name = name,
		depth = math.floor(#leading_spaces(text) / config.options.indent),
		name_col = #leading_spaces(text) + prefix_len,
		display_line = text,
		prefix_col = prefix_col,
		prefix_len = prefix_len,
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
	local _, text, _, prefix_len = split_id_prefix(raw or "")
	if raw == nil or trim(text) ~= "" then
		return nil
	end

	return #leading_spaces(text) + prefix_len
end

local function entry_for_current_line(parsed, entry, fallback_type, fallback_path)
	if entry and parsed.name == entry.name then
		local copy = vim.deepcopy(entry)
		copy.name_col = parsed.name_col
		copy.searchable = true
		return copy
	end

	local copy = entry and vim.deepcopy(entry) or {}
	copy.name = parsed.name
	copy.type = entry and entry.type == "directory" and "directory" or fallback_type or parsed.type
	copy.symlink = false
	copy.path = (entry and entry.path) or fallback_path or parsed.name
	copy.source_path = (entry and entry.path) or fallback_path or nil
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
			entry.id = opts.id_for_path and opts.id_for_path(entry.path) or entry.path
			entry.depth = depth
			entry.display_line = line
			entry.decoration = decoration
			entry.git_decoration = { git_decoration(entry) }
			entry.name_col = depth * config.options.indent + id_prefix_width
			entry.prefix_col = depth * config.options.indent
			entry.prefix_len = id_prefix_width
			entry.line = M.line_with_id(entry.id, line)
			table.insert(lines, entry.line)
			table.insert(entries, entry)
			max_width = math.max(
				max_width,
				virt_text_width(entry.git_decoration) + virt_text_width(decoration) + display_width(entry.display_line)
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
				+ display_width(entry.display_line or entry.line or "")
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

local function highlight_search_name(buf, line, entry, search)
	local hl = search_highlight_for(entry, search)
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
		priority = 50,
	})
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
	return M.reset_decorations(buf, entries, search)
end

function M.reset_decorations(buf, entries, search)
	vim.api.nvim_buf_clear_namespace(buf, M.decor_ns, 0, -1)

	for index, entry in ipairs(entries) do
		local line = index - 1
		conceal_id_prefix(buf, line, entry.prefix_col or 0, entry.prefix_len or 0)

		highlight_search_name(buf, line, entry, search)
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
end

function M.lines_with_ids(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local result = {}
	for index, line in ipairs(lines) do
		local inline_id = split_id_prefix(line)
		table.insert(result, {
			line = line,
			id = inline_id,
		})
	end
	return result
end

function M.entry_at_line(buf, line, entries_by_id, opts)
	opts = opts or {}
	local rows = M.lines_with_ids(buf)
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

	return entry_for_current_line(
		parsed,
		item.id and entries_by_id[item.id] or nil,
		item.id and opts.types_by_id and opts.types_by_id[item.id] or nil,
		item.id and opts.paths_by_id and opts.paths_by_id[item.id] or nil
	)
end

function M.entries_by_id(entries)
	local result = {}
	for _, entry in ipairs(entries) do
		result[entry.id] = entry
	end
	return result
end

function M.sync_decorations(buf, entries_by_id, search, current_line, opts)
	opts = opts or {}
	local parsed = parsed_lines(buf)
	vim.api.nvim_buf_clear_namespace(buf, M.decor_ns, 0, -1)

	for _, item in ipairs(parsed) do
		local entry = entry_for_current_line(
			item,
			item.id and entries_by_id[item.id] or nil,
			item.id and opts.types_by_id and opts.types_by_id[item.id] or nil,
			item.id and opts.paths_by_id and opts.paths_by_id[item.id] or nil
		)
		conceal_id_prefix(buf, item.line - 1, item.prefix_col, item.prefix_len or 0)
		if entry.searchable then
			highlight_search_name(buf, item.line - 1, entry, search)
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
end

return M
