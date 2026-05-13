local config = require("etoile.config")
local help = require("etoile.help")
local icons = require("etoile.icons")
local layout = require("etoile.layout")
local path = require("etoile.path")
local renderer = require("etoile.renderer")
local scanner = require("etoile.scanner")

local M = {}
local preview_ns = vim.api.nvim_create_namespace("etoile_preview")

local function preview_config(main_win, file_path)
	local opts = config.options.preview
	local columns = vim.o.columns
	local lines = vim.o.lines
	local main = vim.api.nvim_win_get_config(main_win)
	local main_col = math.floor(main.col or 0)
	local main_width = main.width or 1
	local available_width = math.max(1, columns - main_col - main_width - 4)
	local width = layout.clamp(
		math.floor(available_width * opts.width_ratio),
		opts.min_width,
		math.min(opts.max_width, available_width)
	)
	local height = layout.resolve_height(opts, lines, math.max(1, lines - 4))

	return {
		relative = "editor",
		row = main.row or 1,
		col = main_col + main_width + 2,
		width = width,
		height = height,
		border = opts.border,
		title = " " .. path.basename(file_path) .. " ",
		title_pos = "left",
	}
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function snacks_image()
	local ok, image = pcall(require, "snacks.image")
	if ok and image.config.enabled ~= false then
		return image
	end
	return nil
end

local function is_image_path(file_path)
	local image = snacks_image()
	return image and image.supports_file(file_path)
end

local function file_exists(file_path)
	local stat = vim.uv.fs_stat(file_path)
	return stat and stat.type ~= "directory"
end

local function prepare_empty_preview_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buflisted = false
	vim.bo[buf].modifiable = false
	return buf
end

local function cleanup_preview_buffer(state)
	if state.preview_buf_is_scratch and state.preview_buf and vim.api.nvim_buf_is_valid(state.preview_buf) then
		pcall(vim.api.nvim_buf_delete, state.preview_buf, { force = true })
	end
	state.preview_buf = nil
	state.preview_buf_is_scratch = nil
end

local function tree_line_for(entry, depth)
	local line = string.rep(" ", depth * config.options.indent)
	local highlights = {}

	local function append_icon(icon, hl)
		local start_col = #line
		line = line .. icon .. " "
		table.insert(highlights, {
			start_col = start_col,
			end_col = #line,
			hl_group = hl,
		})
	end

	if entry.symlink then
		local link_icon, link_hl = icons.link_icon()
		append_icon(link_icon, link_hl)
	end

	entry.open = entry.type == "directory"
	local icon, icon_hl = icons.icon_for(entry)
	append_icon(icon, icon_hl)

	return line .. entry.name, highlights
end

local function prepare_directory_preview_buffer(dir_path, show_excluded)
	renderer.setup_highlights()
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}
	local highlights_by_line = {}
	local directory_opts = config.options.preview.directory or {}
	local max_depth = directory_opts.max_depth

	if directory_opts.enabled == false then
		lines = { "Directory preview is disabled" }
	else
		local function add_dir(dir, depth)
			for _, entry in
				ipairs(scanner.list_dir(dir, {
					root = dir_path,
					exclude = config.options.tree.exclude,
					include_excluded = show_excluded,
				}))
			do
				local line, highlights = tree_line_for(entry, depth)
				table.insert(lines, line)
				highlights_by_line[#lines] = highlights

				if entry.type == "directory" and not entry.symlink and (not max_depth or depth < max_depth) then
					add_dir(entry.path, depth + 1)
				end
			end
		end

		add_dir(dir_path, 0)
	end

	if #lines == 0 then
		lines = { "" }
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	for line, highlights in pairs(highlights_by_line) do
		for _, highlight in ipairs(highlights) do
			vim.api.nvim_buf_set_extmark(buf, preview_ns, line - 1, highlight.start_col, {
				end_col = highlight.end_col,
				hl_group = highlight.hl_group,
			})
		end
	end
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buflisted = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "etoile-tree"
	return buf, true
end

local function prepare_preview_buffer(file_path, entry_type, show_excluded)
	if entry_type == "directory" then
		return prepare_directory_preview_buffer(file_path, show_excluded)
	end

	if not file_exists(file_path) then
		return prepare_empty_preview_buffer(), true
	end

	local image = snacks_image()
	if image and image.supports_file(file_path) then
		local buf = vim.api.nvim_create_buf(false, true)
		image.buf.attach(buf, { src = file_path })
		return buf, true
	end

	local buf = vim.fn.bufadd(file_path)
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = false

	if vim.bo[buf].filetype == "" then
		local filetype = vim.filetype.match({ filename = file_path, buf = buf })
		if filetype then
			vim.bo[buf].filetype = filetype
		end
	end

	if vim.bo[buf].syntax == "" and vim.bo[buf].filetype ~= "" then
		vim.bo[buf].syntax = vim.bo[buf].filetype
	end

	pcall(vim.treesitter.start, buf)

	return buf, false
end

local function unmap_preview_keys(state)
	if not state.preview_mapped_buf or not vim.api.nvim_buf_is_valid(state.preview_mapped_buf) then
		state.preview_mapped_buf = nil
		return
	end

	local keys = config.options.keymaps
	if keys.focus_toggle and keys.focus_toggle ~= "" then
		pcall(vim.keymap.del, "n", keys.focus_toggle, { buffer = state.preview_mapped_buf })
	end
	if keys.focus_tree and keys.focus_tree ~= "" then
		pcall(vim.keymap.del, "n", keys.focus_tree, { buffer = state.preview_mapped_buf })
	end
	if keys.help and keys.help ~= "" then
		pcall(vim.keymap.del, "n", keys.help, { buffer = state.preview_mapped_buf })
	end
	pcall(vim.keymap.del, "n", "<C-o>", { buffer = state.preview_mapped_buf })
	pcall(vim.keymap.del, "n", "<C-i>", { buffer = state.preview_mapped_buf })
	state.preview_mapped_buf = nil
end

local function jump_avoiding_main(state, lhs)
	local win = vim.api.nvim_get_current_win()
	local previous_buf = vim.api.nvim_win_get_buf(win)
	local cursor = vim.api.nvim_win_get_cursor(win)
	local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
	vim.api.nvim_feedkeys(keys, "nx", false)

	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= state.buf then
			return
		end
		if not vim.api.nvim_buf_is_valid(previous_buf) then
			return
		end

		vim.api.nvim_win_set_buf(win, previous_buf)
		pcall(vim.api.nvim_win_set_cursor, win, cursor)
	end)
end

local function map_preview_keys(state, buf)
	if state.preview_mapped_buf ~= buf then
		unmap_preview_keys(state)
	end

	local keys = config.options.keymaps
	if keys.focus_toggle and keys.focus_toggle ~= "" then
		vim.keymap.set("n", keys.focus_toggle, function()
			M.focus_toggle(state)
		end, { buffer = buf, silent = true, desc = "Toggle etoile focus" })
	end
	if keys.focus_tree and keys.focus_tree ~= "" then
		vim.keymap.set("n", keys.focus_tree, function()
			M.focus_tree(state)
		end, { buffer = buf, silent = true, desc = "Focus etoile main" })
	end
	if keys.help and keys.help ~= "" then
		vim.keymap.set("n", keys.help, function()
			help.open("preview")
		end, { buffer = buf, silent = true, desc = "Show etoile keymaps" })
	end
	vim.keymap.set("n", "<C-o>", function()
		jump_avoiding_main(state, "<C-o>")
	end, { buffer = buf, silent = true, desc = "Jump back without entering etoile main" })
	vim.keymap.set("n", "<C-i>", function()
		jump_avoiding_main(state, "<C-i>")
	end, { buffer = buf, silent = true, desc = "Jump forward without entering etoile main" })
	state.preview_mapped_buf = buf
end

local function sync_preview_keys_for_current_window(state)
	if not valid_win(state.preview_win) or vim.api.nvim_get_current_win() ~= state.preview_win then
		return
	end

	local buf = vim.api.nvim_win_get_buf(state.preview_win)
	map_preview_keys(state, buf)
end

local function clear_preview_window_key_sync(state)
	if state.preview_key_sync_group then
		pcall(vim.api.nvim_clear_autocmds, {
			group = state.preview_key_sync_group,
		})
	end
	state.preview_key_sync_group = nil
end

local function setup_preview_window_key_sync(state)
	clear_preview_window_key_sync(state)

	state.preview_key_sync_group = vim.api.nvim_create_augroup("etoile_preview_keys_" .. state.buf, { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = state.preview_key_sync_group,
		callback = function()
			sync_preview_keys_for_current_window(state)
		end,
	})
end

local function clear_preview_write_sync(state)
	if state.preview_write_sync_buf and vim.api.nvim_buf_is_valid(state.preview_write_sync_buf) then
		pcall(vim.api.nvim_clear_autocmds, {
			group = state.preview_write_sync_group,
			buffer = state.preview_write_sync_buf,
		})
	end
	state.preview_write_sync_buf = nil
end

local function setup_preview_write_sync(state, buf, buf_is_scratch)
	clear_preview_write_sync(state)

	if buf_is_scratch then
		return
	end

	state.preview_write_sync_group = state.preview_write_sync_group
		or vim.api.nvim_create_augroup("etoile_preview_git_status_" .. state.buf, { clear = true })
	state.preview_write_sync_buf = buf
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = state.preview_write_sync_group,
		buffer = buf,
		callback = function()
			if state.refresh_git_status then
				state.refresh_git_status()
			end
		end,
	})
end

local function set_preview_options(win)
	vim.wo[win].wrap = false
	vim.wo[win].conceallevel = 0
end

local function apply_preview_options(state, file_path, entry_type)
	if entry_type == "directory" or is_image_path(file_path) then
		vim.wo[state.preview_win].wrap = false
		vim.wo[state.preview_win].conceallevel = 0
	else
		set_preview_options(state.preview_win)
	end
end

local function apply_empty_preview_options(state)
	vim.wo[state.preview_win].wrap = false
	vim.wo[state.preview_win].conceallevel = 0
end

local function apply_preview_buffer(state, file_path, entry_type)
	local previous_buf = state.preview_buf
	local previous_buf_is_scratch = state.preview_buf_is_scratch
	local buf, buf_is_scratch = prepare_preview_buffer(file_path, entry_type, state.show_excluded)
	vim.api.nvim_win_set_buf(state.preview_win, buf)
	vim.api.nvim_win_set_config(state.preview_win, preview_config(state.win, file_path))
	apply_preview_options(state, file_path, entry_type)
	state.preview_buf = buf
	state.preview_buf_is_scratch = buf_is_scratch
	state.preview_path = file_path
	state.preview_type = entry_type
	map_preview_keys(state, buf)
	setup_preview_write_sync(state, buf, buf_is_scratch)

	if previous_buf_is_scratch and previous_buf and vim.api.nvim_buf_is_valid(previous_buf) then
		pcall(vim.api.nvim_buf_delete, previous_buf, { force = true })
	end

	return true
end

local function apply_empty_preview_buffer(state, title)
	local previous_buf = state.preview_buf
	local previous_buf_is_scratch = state.preview_buf_is_scratch
	local buf = prepare_empty_preview_buffer()
	vim.api.nvim_win_set_buf(state.preview_win, buf)
	vim.api.nvim_win_set_config(state.preview_win, preview_config(state.win, title or ""))
	apply_empty_preview_options(state)
	state.preview_buf = buf
	state.preview_buf_is_scratch = true
	state.preview_path = nil
	state.preview_type = nil
	unmap_preview_keys(state)
	clear_preview_write_sync(state)
	map_preview_keys(state, buf)

	if previous_buf_is_scratch and previous_buf and vim.api.nvim_buf_is_valid(previous_buf) then
		pcall(vim.api.nvim_buf_delete, previous_buf, { force = true })
	end
end

local function resize_preview(state, file_path)
	if valid_win(state.preview_win) and valid_win(state.win) then
		vim.api.nvim_win_set_config(state.preview_win, preview_config(state.win, file_path or state.preview_path or ""))
	end
end

function M.open(state, file_path, entry_type)
	if not file_path or file_path == "" then
		vim.notify("No file to preview", vim.log.levels.WARN)
		return
	end
	entry_type = entry_type or "file"

	if valid_win(state.preview_win) then
		apply_preview_buffer(state, file_path, entry_type)
		return
	end

	local buf, buf_is_scratch = prepare_preview_buffer(file_path, entry_type, state.show_excluded)
	local win = vim.api.nvim_open_win(buf, false, preview_config(state.win, file_path))
	state.preview_win = win
	state.preview_buf = buf
	state.preview_buf_is_scratch = buf_is_scratch
	state.preview_path = file_path
	state.preview_type = entry_type
	apply_preview_options(state, file_path, entry_type)
	map_preview_keys(state, buf)
	setup_preview_window_key_sync(state)
	setup_preview_write_sync(state, buf, buf_is_scratch)

	vim.api.nvim_create_autocmd("WinClosed", {
		once = true,
		pattern = tostring(win),
		callback = function()
			unmap_preview_keys(state)
			clear_preview_window_key_sync(state)
			clear_preview_write_sync(state)
			cleanup_preview_buffer(state)
			state.preview_win = nil
			state.preview_path = nil
			state.preview_type = nil
			if state.resize_main then
				state.resize_main()
			end
		end,
	})
end

function M.is_open(state)
	return valid_win(state.preview_win)
end

function M.sync(state, file_path, entry_type)
	entry_type = entry_type or "file"
	if not M.is_open(state) then
		return
	end
	if state.preview_path == file_path and state.preview_type == entry_type then
		if
			entry_type == "file"
			and state.preview_buf_is_scratch
			and file_exists(file_path)
			and not is_image_path(file_path)
		then
			M.open(state, file_path, entry_type)
			return
		end
		resize_preview(state, file_path)
		return
	end
	M.open(state, file_path, entry_type)
end

function M.clear(state, title)
	if M.is_open(state) then
		apply_empty_preview_buffer(state, title)
	end
end

function M.focus_toggle(state)
	if not M.is_open(state) or not valid_win(state.win) then
		return
	end

	if vim.api.nvim_get_current_win() == state.preview_win then
		M.focus_tree(state)
	else
		M.focus_preview(state)
	end
end

function M.focus_preview(state)
	if not M.is_open(state) then
		return
	end

	vim.api.nvim_set_current_win(state.preview_win)
end

function M.focus_tree(state)
	if not valid_win(state.win) then
		return
	end

	vim.api.nvim_set_current_win(state.win)
end

function M.close(state)
	if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
		vim.api.nvim_win_close(state.preview_win, true)
	end
	unmap_preview_keys(state)
	clear_preview_window_key_sync(state)
	clear_preview_write_sync(state)
	cleanup_preview_buffer(state)
	state.preview_win = nil
	state.preview_path = nil
	state.preview_type = nil
end

return M
