local config = require("etoile.config")

local M = {}
local help_ns = vim.api.nvim_create_namespace("etoile_help")

local tabs = { "tree", "preview" }
local labels = {
	tree = "Tree",
	preview = "Preview",
}

local function configured_key(name)
	return config.options.keymaps[name]
end

local function display_key(key)
	return key and key ~= "" and key or "<disabled>"
end

local function entries_for(scope)
	if scope == "preview" then
		return {
			{ configured_key("focus_toggle"), "Toggle etoile focus" },
			{ configured_key("focus_tree"), "Focus etoile main" },
			{ configured_key("help"), "Show etoile keymaps" },
			{ "<C-o>", "Jump back without entering etoile main" },
			{ "<C-i>", "Jump forward without entering etoile main" },
		}
	end

	return {
		{ configured_key("open"), "Open etoile entry" },
		{ configured_key("open_split"), "Open etoile entry in horizontal split" },
		{ configured_key("open_vsplit"), "Open etoile entry in vertical split" },
		{ configured_key("open_tab"), "Open etoile entry in new tab" },
		{ configured_key("parent"), "Move etoile root to parent" },
		{ configured_key("child"), "Move etoile root to child" },
		{ configured_key("preview"), "Toggle etoile preview" },
		{ configured_key("focus_toggle"), "Toggle etoile focus" },
		{ configured_key("focus_preview"), "Focus etoile preview" },
		{ configured_key("search"), "Search etoile tree" },
		{ configured_key("search_next"), "Next etoile search result" },
		{ configured_key("search_prev"), "Previous etoile search result" },
		{ configured_key("search_clear"), "Clear etoile search highlights" },
		{ configured_key("help"), "Show etoile keymaps" },
		{ configured_key("close"), "Close etoile" },
		{ "<C-o>", "Jump back within etoile" },
		{ "<C-i>", "Jump forward within etoile" },
	}
end

local function tab_line(active, width)
	local parts = {}
	local col = 0
	local active_start = 0
	local active_end = 0
	for _, tab in ipairs(tabs) do
		if #parts > 0 then
			table.insert(parts, "  ")
			col = col + 2
		end
		local label = labels[tab]
		if tab == active then
			active_start = col
			active_end = col + #label
		end
		table.insert(parts, label)
		col = col + #label
	end
	local padding = math.max(0, math.floor(((width or col) - col) / 2))
	return string.rep(" ", padding) .. table.concat(parts, ""), padding + active_start, padding + active_end
end

local function lines_for(active, width)
	local entries = entries_for(active)
	local key_width = 1
	for _, entry in ipairs(entries) do
		key_width = math.max(key_width, #display_key(entry[1]))
	end

	local line = tab_line(active, width)
	local lines = { line, "" }
	for _, entry in ipairs(entries) do
		local key = display_key(entry[1])
		table.insert(lines, string.format("%-" .. key_width .. "s  %s", key, entry[2]))
	end
	return lines
end

local function highlight_tab(buf, active, width)
	local _, start_col, end_col = tab_line(active, width)
	vim.api.nvim_buf_clear_namespace(buf, help_ns, 0, 1)
	vim.api.nvim_buf_add_highlight(buf, help_ns, "TabLineSel", 0, start_col, end_col)
end

local function help_config(line_sets)
	local width = 1
	local height = 1
	for _, lines in ipairs(line_sets) do
		height = math.max(height, #lines)
		for _, line in ipairs(lines) do
			width = math.max(width, #line)
		end
	end
	width = math.max(36, width + 4)
	width = math.min(width, math.max(1, vim.o.columns - 4))

	return {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Etoile Keymaps ",
		title_pos = "center",
	}
end

local function next_tab(active, step)
	local index = active == "preview" and 2 or 1
	index = ((index - 1 + step) % #tabs) + 1
	return tabs[index]
end

function M.open(active)
	active = active == "preview" and "preview" or "tree"
	local window_config = help_config({ lines_for("tree"), lines_for("preview") })

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local win
	local function render()
		local lines = lines_for(active, window_config.width)
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		highlight_tab(buf, active, window_config.width)
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_config(win, window_config)
		end
	end

	local function close()
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function switch(step)
		active = next_tab(active, step)
		render()
	end

	render()
	win = vim.api.nvim_open_win(buf, true, window_config)
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })

	vim.keymap.set("n", "q", close, { buffer = buf, silent = true, desc = "Close etoile keymap help" })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true, desc = "Close etoile keymap help" })
	vim.keymap.set("n", "<CR>", close, { buffer = buf, silent = true, desc = "Close etoile keymap help" })
	vim.keymap.set("n", "<Tab>", function()
		switch(1)
	end, { buffer = buf, silent = true, desc = "Next etoile keymap help tab" })
	vim.keymap.set("n", "<S-Tab>", function()
		switch(-1)
	end, { buffer = buf, silent = true, desc = "Previous etoile keymap help tab" })
end

return M
