local config = require("etoile.config")
local editor = require("etoile.editor")
local help = require("etoile.help")
local layout = require("etoile.layout")
local pending = require("etoile.pending")
local path = require("etoile.path")
local preview = require("etoile.preview")
local renderer = require("etoile.renderer")
local scanner = require("etoile.scanner")

local M = {}

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function resolve_root(input)
	if input and input ~= "" then
		return path.normalize(vim.fn.fnamemodify(input, ":p"))
	end

	local current = vim.api.nvim_buf_get_name(0)
	local start = current ~= "" and current or vim.fn.getcwd()
	local root = vim.fs.root(start, { ".git" })
	return path.normalize(root or vim.fn.getcwd())
end

local function expand_to_current(state)
	local current = vim.api.nvim_buf_get_name(0)
	if current == "" then
		return
	end

	current = path.normalize(current)
	if current ~= state.root and not path.is_ancestor(state.root, current) then
		return
	end

	local dir = path.dirname(current)
	while dir and dir ~= state.root and path.is_ancestor(state.root, dir) do
		state.expanded[dir] = true
		dir = path.dirname(dir)
	end
	state.expanded[state.root] = true
	state.focus_path = current
end

local function source_win_col(state)
	local opts = config.options.tree
	if opts.position ~= "source_window" or not valid_win(state.source_win) then
		return opts.col
	end

	local ok, position = pcall(vim.api.nvim_win_get_position, state.source_win)
	if not ok or not position then
		return opts.col
	end

	return (position[2] or 0) + opts.col
end

local function preview_reserved_width()
	local tree_opts = config.options.tree
	if not tree_opts.reserve_preview_width then
		return 0
	end

	local preview_opts = config.options.preview
	return 2 + (preview_opts.max_width or 0)
end

local function tree_config(state)
	local opts = config.options.tree
	local width = layout.clamp(
		state.rendered.max_width + opts.width_padding + (opts.icon_width_padding or 0) + (opts.right_padding or 0),
		opts.min_width,
		math.min(opts.max_width, vim.o.columns - 4)
	)
	local height = layout.resolve_height(opts, vim.o.lines, math.max(1, vim.o.lines - 4))
	local row = opts.row or layout.resolve_row(height, vim.o.lines)
	local col = layout.resolve_col(source_win_col(state), width, vim.o.columns, 2 + preview_reserved_width())
	return {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		border = opts.border,
		title = " Etoile - " .. path.basename(state.root) .. " ",
		title_pos = "left",
	}
end

local function entry_at_cursor(state)
	local line = vim.api.nvim_win_get_cursor(state.win)[1]
	return renderer.entry_at_line(state.buf, line, state.entries_by_id or {}, {
		paths_by_id = state.paths_by_id,
		types_by_id = state.types_by_id,
	})
end

local function set_cursor_to_path(state, target)
	if not target then
		return
	end
	local fallback = nil
	for index, entry in ipairs(state.rendered.entries) do
		if path.normalize(entry.path) == path.normalize(target) then
			vim.api.nvim_win_set_cursor(state.win, { index, 0 })
			return
		end
		if path.is_ancestor(entry.path, target) and (not fallback or #entry.path > #fallback.path) then
			fallback = {
				index = index,
				path = entry.path,
			}
		end
	end
	if fallback then
		vim.api.nvim_win_set_cursor(state.win, { fallback.index, 0 })
	end
end

local function expand_ancestors(state, target)
	if not target then
		return
	end

	local dir = path.dirname(target)
	while dir and dir ~= state.root and path.is_ancestor(state.root, dir) do
		state.expanded[dir] = true
		dir = path.dirname(dir)
	end
end

local function id_for_path(state, entry_path)
	local existing = state.ids_by_path[entry_path]
	if existing then
		return existing
	end
	if state.next_id > 999999 then
		error("Etoile entry id limit exceeded")
	end
	local id = ("%06d"):format(state.next_id)
	state.next_id = state.next_id + 1
	state.ids_by_path[entry_path] = id
	state.paths_by_id[id] = entry_path
	return id
end

local collect_pending_edits

local function refresh(state, opts)
	opts = opts or {}
	if opts.collect_pending ~= false and collect_pending_edits then
		collect_pending_edits(state)
	end
	state.rendered = renderer.render(state.root, state.expanded, {
		exclude = config.options.tree.exclude,
		show_excluded = state.show_excluded,
		search_exclude = config.options.search.exclude,
		id_for_path = function(entry_path)
			return id_for_path(state, entry_path)
		end,
		pending_ops = state.pending_ops,
	})
	for _, entry in ipairs(state.rendered.entries) do
		state.types_by_id[entry.id] = entry.type
	end
	state.snapshot = editor.snapshot(state.rendered.entries)
	state.entries_by_id = renderer.entries_by_id(state.rendered.entries)
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	state.sync_suspended = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.rendered.lines)
	renderer.decorate(state.buf, state.rendered.entries, state.search)
	state.sync_suspended = false
	vim.api.nvim_set_option_value("modified", false, { buf = state.buf })

	if valid_win(state.win) then
		vim.api.nvim_win_set_config(state.win, tree_config(state))
		vim.wo[state.win].conceallevel = 2
		vim.wo[state.win].concealcursor = "nvic"
		local focus_path = state.focus_path
		state.focus_path = nil
		set_cursor_to_path(state, focus_path)
	end
end

local function refresh_without_undo(state, opts)
	local undolevels = vim.api.nvim_get_option_value("undolevels", { scope = "global" })
	vim.api.nvim_set_option_value("undolevels", -1, { buf = state.buf })
	local ok, err = pcall(refresh, state, opts)
	vim.api.nvim_set_option_value("undolevels", undolevels, { buf = state.buf })
	if not ok then
		error(err)
	end
end

local function refresh_git_status(state)
	if not state.rendered then
		return
	end
	renderer.refresh_git_status(state.root, state.rendered)
	renderer.reset_decorations(state.buf, state.rendered.entries, state.search)
	if valid_win(state.win) then
		vim.api.nvim_win_set_config(state.win, tree_config(state))
	end
end

local sync_open_preview

collect_pending_edits = function(state)
	if not state.buf or not state.snapshot then
		return {}
	end
	local lines = renderer.lines_with_ids(state.buf)
	local ops = editor.diff(state.root, state.snapshot, lines, {
		paths_by_id = state.paths_by_id,
		types_by_id = state.types_by_id,
	})
	state.pending_ops = pending.merge(state.pending_ops, ops)
	return ops
end

local function root_history_entry(state)
	return {
		root = state.root,
		expanded = vim.deepcopy(state.expanded or {}),
		focus_path = state.focus_path,
		cursor = valid_win(state.win) and vim.api.nvim_win_get_cursor(state.win) or nil,
	}
end

local function save_current_root_history_entry(state)
	if not state.root_history or not state.root_history_index then
		return
	end
	state.root_history[state.root_history_index] = root_history_entry(state)
end

local function push_root_history(state, root, opts)
	save_current_root_history_entry(state)
	while #state.root_history > state.root_history_index do
		table.remove(state.root_history)
	end
	table.insert(state.root_history, {
		root = root,
		expanded = vim.deepcopy(opts.expanded or {}),
		focus_path = opts.focus_path,
		cursor = opts.cursor,
	})
	state.root_history_index = #state.root_history
end

local function restore_root_history(state, index)
	local entry = state.root_history and state.root_history[index]
	if not entry then
		return false
	end
	collect_pending_edits(state)
	save_current_root_history_entry(state)
	state.root_history_index = index
	state.root = entry.root
	state.expanded = vim.deepcopy(entry.expanded or {})
	state.focus_path = entry.focus_path
	refresh_without_undo(state, { collect_pending = false })
	if entry.cursor and valid_win(state.win) then
		pcall(vim.api.nvim_win_set_cursor, state.win, entry.cursor)
	end
	sync_open_preview(state)
	return true
end

local function root_history_target(state, lhs)
	if not state.root_history or not state.root_history_index then
		return nil
	end
	if lhs == "<C-o>" and state.root_history_index > 1 then
		return state.root_history_index - 1
	end
	if lhs == "<C-i>" and state.root_history_index < #state.root_history then
		return state.root_history_index + 1
	end
	return nil
end

local function jump_root_history(state, lhs)
	local target = root_history_target(state, lhs)
	if not target then
		return false
	end
	return restore_root_history(state, target)
end

local function reveal_path(state, target)
	expand_ancestors(state, target)
	state.focus_path = target
	refresh(state)
end

local function expand_search_matches(state)
	for _, target in ipairs(state.search_matches or {}) do
		local dir = path.dirname(target)
		while dir and dir ~= state.root and path.is_ancestor(state.root, dir) do
			state.expanded[dir] = true
			dir = path.dirname(dir)
		end
	end
end

local function search_terms(query)
	local terms = {}
	for term in query:lower():gmatch("%S+") do
		term = term:gsub("/+$", "")
		if term ~= "" then
			table.insert(terms, term)
		end
	end
	return terms
end

local function last_path_component(value)
	return value:match("([^/]+)$") or value
end

local function rel_matches_terms(rel, terms)
	for _, term in ipairs(terms) do
		if not rel:find(term, 1, true) then
			return false
		end
	end
	return true
end

local function entry_matches_search(entry, root, terms)
	local rel = path.relative(entry.path, root):lower()
	if not rel_matches_terms(rel, terms) then
		return false
	end

	local last_term = last_path_component(terms[#terms])
	return entry.name:lower():find(last_term, 1, true) ~= nil
end

local function collect_search_matches(root, terms, opts)
	opts = opts or {}
	local matches = {}

	local exclude = config.options.search.exclude
	if opts.tree_exclude and #opts.tree_exclude > 0 then
		local merged = {}
		for _, v in ipairs(exclude) do
			merged[#merged + 1] = v
		end
		for _, v in ipairs(opts.tree_exclude) do
			merged[#merged + 1] = v
		end
		exclude = merged
	end

	local function visit(dir)
		for _, entry in ipairs(scanner.list_dir(dir, { root = root, exclude = exclude })) do
			if entry_matches_search(entry, root, terms) then
				table.insert(matches, entry.path)
			end
			if entry.type == "directory" and not entry.symlink then
				visit(entry.path)
			end
		end
	end

	visit(root)
	return matches
end

local function update_search_state(state)
	local matches_by_path = {}
	local match_index_by_path = {}
	for index, match in ipairs(state.search_matches or {}) do
		matches_by_path[match] = true
		match_index_by_path[match] = index
	end
	state.search = {
		matches_by_path = matches_by_path,
		match_index_by_path = match_index_by_path,
		total = #(state.search_matches or {}),
		current_path = state.search_matches and state.search_matches[state.search_index],
	}
end

local function open_entry(state, command)
	local entry = entry_at_cursor(state)
	if not entry then
		return
	end

	if entry.type == "directory" then
		state.expanded[entry.path] = not state.expanded[entry.path]
		state.focus_path = entry.path
		refresh(state)
		return
	end

	local source = state.source_win
	if valid_win(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	preview.close(state)
	if valid_win(source) then
		vim.api.nvim_set_current_win(source)
	end
	vim.cmd((command or "edit") .. " " .. vim.fn.fnameescape(entry.path))
end

sync_open_preview = function(state)
	if not preview.is_open(state) then
		return
	end

	local entry = entry_at_cursor(state)
	if entry and (entry.type == "file" or entry.type == "directory") then
		preview.sync(state, entry.path, entry.type)
	else
		preview.sync(state, state.root, "directory")
	end
end

local function parent_root(state)
	collect_pending_edits(state)
	local previous_root = state.root
	local next_root = path.dirname(state.root)
	push_root_history(state, next_root, {
		expanded = {},
		focus_path = previous_root,
	})
	state.root = next_root
	state.expanded = {}
	state.focus_path = previous_root
	refresh(state, { collect_pending = false })
	sync_open_preview(state)
end

local function child_root(state)
	local entry = entry_at_cursor(state)
	if not entry or entry.type ~= "directory" then
		return
	end
	collect_pending_edits(state)
	push_root_history(state, entry.path, {
		expanded = {},
		focus_path = nil,
	})
	state.root = entry.path
	state.expanded = {}
	state.focus_path = nil
	refresh(state, { collect_pending = false })
	sync_open_preview(state)
end

local function save_changes(state)
	local lines = renderer.lines_with_ids(state.buf)
	local cursor_line = valid_win(state.win) and vim.api.nvim_win_get_cursor(state.win)[1] or nil
	local cursor_target_path = editor.path_at_line(state.root, lines, cursor_line)
	local edited_expanded = editor.expanded_paths(state.root, lines)
	collect_pending_edits(state)
	local ops = state.pending_ops or {}
	local ok, err = editor.apply(ops, {
		confirm_delete = config.options.confirm.delete,
		confirm_move = config.options.confirm.move,
		confirm_copy = config.options.confirm.copy,
		confirm_create = config.options.confirm.create,
		root = state.root,
	})
	if not ok then
		vim.notify(err or "Failed to apply etoile changes", vim.log.levels.WARN)
	end
	if err == "Apply canceled" then
		return
	end
	if err == "Apply reverted" then
		state.pending_ops = {}
		refresh(state, { collect_pending = false })
		sync_open_preview(state)
		return
	end
	for expanded_path in pairs(edited_expanded) do
		state.expanded[expanded_path] = true
	end
	expand_ancestors(state, cursor_target_path)
	state.focus_path = ok and cursor_target_path or nil
	if #ops > 0 then
		if ok then
			state.pending_ops = {}
		end
		refresh_without_undo(state, { collect_pending = false })
	else
		refresh(state, { collect_pending = false })
	end
end

local function search(state)
	local query = vim.fn.input("Etoile search: ")
	if query == "" then
		return
	end

	local terms = search_terms(query)
	if #terms == 0 then
		return
	end

	state.search_matches = {}
	state.search_index = 0
	state.search = nil
	state.search_matches = collect_search_matches(state.root, terms, {
		tree_exclude = not state.show_excluded and config.options.tree.exclude or nil,
	})

	if #state.search_matches == 0 then
		vim.notify("No etoile search results: " .. query, vim.log.levels.INFO)
		renderer.reset_decorations(state.buf, state.rendered.entries, state.search)
		return
	end

	state.search_index = 1
	update_search_state(state)
	if config.options.search.expand_matches then
		expand_search_matches(state)
	end
	reveal_path(state, state.search_matches[state.search_index])
end

local function search_clear(state)
	if not state.search or not state.search_matches or #state.search_matches == 0 then
		return
	end

	state.search_matches = {}
	state.search_index = 0
	state.search = nil
	renderer.reset_decorations(state.buf, state.rendered.entries, state.search)
end

local function search_move(state, delta)
	if not state.search_matches or #state.search_matches == 0 then
		return
	end
	state.search_index = ((state.search_index - 1 + delta) % #state.search_matches) + 1
	update_search_state(state)
	reveal_path(state, state.search_matches[state.search_index])
end

local function open_preview(state)
	local entry = entry_at_cursor(state)
	if not entry or (entry.type ~= "file" and entry.type ~= "directory") then
		return
	end
	if entry.searchable == false then
		if entry.source_path then
			preview.open(state, entry.source_path, entry.type)
		else
			preview.clear(state, entry.name)
		end
		return
	end
	preview.open(state, entry.path, entry.type)
end

local function toggle_preview(state)
	if preview.is_open(state) then
		preview.close(state)
	else
		open_preview(state)
	end
end

local function sync_preview(state)
	if not preview.is_open(state) then
		return
	end

	local entry = entry_at_cursor(state)
	if not entry then
		preview.clear(state, "")
		return
	end
	if entry.type ~= "file" and entry.type ~= "directory" then
		return
	end
	if entry.searchable == false then
		if entry.source_path then
			preview.sync(state, entry.source_path, entry.type)
		else
			preview.clear(state, entry.name)
		end
		return
	end
	preview.sync(state, entry.path, entry.type)
end

local function schedule_sync_preview(state)
	local delay = config.options.preview.debounce_ms or 0
	if delay <= 0 then
		sync_preview(state)
		return
	end

	state.preview_sync_token = (state.preview_sync_token or 0) + 1
	local token = state.preview_sync_token
	vim.defer_fn(function()
		if token ~= state.preview_sync_token then
			return
		end
		if not valid_win(state.win) then
			return
		end
		sync_preview(state)
	end, delay)
end

local function map(buf, lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
end

local function move_root_history(state, lhs)
	jump_root_history(state, lhs)
end

local function sync_decorations(state)
	if state.sync_suspended then
		return
	end
	local current_line = valid_win(state.win) and vim.api.nvim_win_get_cursor(state.win)[1] or nil
	state.sync_suspended = true
	local ok, err = pcall(renderer.sync_decorations, state.buf, state.entries_by_id or {}, state.search, current_line, {
		paths_by_id = state.paths_by_id,
		types_by_id = state.types_by_id,
	})
	state.sync_suspended = false
	if not ok then
		error(err)
	end
	sync_preview(state)
end

local function editable_col(state, line)
	local rows = renderer.lines_with_ids(state.buf)
	local item = rows[line]
	if not item or type(item.line) ~= "string" then
		return nil
	end
	local before, id = item.line:match("^(%s*)(%d%d%d%d%d%d)%s")
	if not id then
		return nil
	end
	return #before + 7
end

local function keep_cursor_in_name(state)
	if not valid_win(state.win) then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local min_col = editable_col(state, cursor[1])
	if min_col and cursor[2] < min_col then
		pcall(vim.api.nvim_win_set_cursor, state.win, { cursor[1], min_col })
	end
end

local function toggle_exclude_visibility(state)
	local entry = entry_at_cursor(state)
	if entry then
		state.focus_path = entry.path
	end
	state.show_excluded = not state.show_excluded
	refresh_without_undo(state)
end

local function setup_buffer(state)
	vim.api.nvim_set_option_value("buftype", "acwrite", { buf = state.buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
	pcall(vim.api.nvim_buf_set_name, state.buf, "etoile://" .. state.root)

	local keys = config.options.keymaps
	map(state.buf, keys.root_history_back, function()
		move_root_history(state, "<C-o>")
	end, "Move backward through etoile root history")
	map(state.buf, keys.root_history_forward, function()
		move_root_history(state, "<C-i>")
	end, "Move forward through etoile root history")
	map(state.buf, keys.open, function()
		open_entry(state)
	end, "Open etoile entry")
	map(state.buf, keys.open_split, function()
		open_entry(state, "split")
	end, "Open etoile entry in horizontal split")
	map(state.buf, keys.open_vsplit, function()
		open_entry(state, "vsplit")
	end, "Open etoile entry in vertical split")
	map(state.buf, keys.open_tab, function()
		open_entry(state, "tabedit")
	end, "Open etoile entry in new tab")
	map(state.buf, keys.parent, function()
		parent_root(state)
	end, "Move etoile root to parent")
	map(state.buf, keys.child, function()
		child_root(state)
	end, "Move etoile root to child")
	map(state.buf, keys.preview, function()
		toggle_preview(state)
	end, "Toggle etoile preview")
	map(state.buf, keys.focus_toggle, function()
		preview.focus_toggle(state)
	end, "Toggle etoile focus")
	map(state.buf, keys.focus_preview, function()
		preview.focus_preview(state)
	end, "Focus etoile preview")
	map(state.buf, keys.search, function()
		search(state)
	end, "Search etoile tree")
	map(state.buf, keys.search_next, function()
		search_move(state, 1)
	end, "Next etoile search result")
	map(state.buf, keys.search_prev, function()
		search_move(state, -1)
	end, "Previous etoile search result")
	map(state.buf, keys.search_clear, function()
		search_clear(state)
	end, "Clear etoile search highlights")
	map(state.buf, keys.help, function()
		help.open("tree")
	end, "Show etoile keymaps")
	map(state.buf, keys.close, function()
		preview.close(state)
		if valid_win(state.win) then
			vim.api.nvim_win_close(state.win, true)
		end
	end, "Close etoile")
	map(state.buf, keys.toggle_exclude, function()
		toggle_exclude_visibility(state)
	end, "Toggle etoile excluded entries")

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = state.buf,
		callback = function()
			save_changes(state)
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.buf,
		callback = function()
			sync_decorations(state)
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = state.buf,
		callback = function()
			keep_cursor_in_name(state)
			schedule_sync_preview(state)
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
		buffer = state.buf,
		callback = function()
			keep_cursor_in_name(state)
		end,
	})
end

function M.setup(opts)
	config.setup(opts)
end

function M.open(opts)
	opts = opts or {}
	local state = {
		root = resolve_root(opts.path),
		expanded = {},
		next_id = 1,
		ids_by_path = {},
		paths_by_id = {},
		types_by_id = {},
		pending_ops = {},
		source_win = vim.api.nvim_get_current_win(),
		search_matches = {},
		search_index = 0,
		search = nil,
		show_excluded = false,
	}
	state.root_history = {
		{
			root = state.root,
			expanded = vim.deepcopy(state.expanded),
			focus_path = state.focus_path,
			cursor = nil,
		},
	}
	state.root_history_index = 1
	state.resize_main = function()
		if valid_win(state.win) then
			vim.api.nvim_win_set_config(state.win, tree_config(state))
		end
	end
	state.refresh_git_status = function()
		if config.options.git_status.sync_on_preview_write then
			refresh_git_status(state)
		end
	end

	expand_to_current(state)
	state.rendered = renderer.render(state.root, state.expanded, {
		exclude = config.options.tree.exclude,
		show_excluded = state.show_excluded,
		search_exclude = config.options.search.exclude,
		id_for_path = function(entry_path)
			return id_for_path(state, entry_path)
		end,
	})
	for _, entry in ipairs(state.rendered.entries) do
		state.types_by_id[entry.id] = entry.type
	end
	state.snapshot = editor.snapshot(state.rendered.entries)
	state.entries_by_id = renderer.entries_by_id(state.rendered.entries)
	state.buf = vim.api.nvim_create_buf(false, true)
	setup_buffer(state)
	state.sync_suspended = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.rendered.lines)
	renderer.decorate(state.buf, state.rendered.entries, state.search)
	state.sync_suspended = false
	vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
	state.win = vim.api.nvim_open_win(state.buf, true, tree_config(state))
	vim.wo[state.win].conceallevel = 2
	vim.wo[state.win].concealcursor = "nvic"
	set_cursor_to_path(state, state.focus_path)
	if config.options.preview.enabled then
		open_preview(state)
	end
end

return M
