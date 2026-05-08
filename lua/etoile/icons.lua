local config = require("etoile.config")

local M = {}

local devicons

local function get_devicons()
	if devicons then
		return devicons
	end
	local ok, mod = pcall(require, "nvim-web-devicons")
	if not ok then
		error("etoile.nvim requires nvim-web-devicons")
	end
	devicons = mod
	return devicons
end

function M.icon_for(entry)
	if entry.type == "directory" then
		local icon = entry.open and (config.options.icons.directory_open or config.options.icons.directory)
			or config.options.icons.directory
		return icon, "EtoileDirectoryIcon"
	end

	local name = entry.name or vim.fn.fnamemodify(entry.path, ":t")
	local ext = name:match("%.([^%.]+)$")
	local icon, hl = get_devicons().get_icon(name, ext, { default = true })
	return icon or "", hl or "Normal"
end

function M.link_icon()
	return config.options.icons.link, "EtoileSymlinkIcon"
end

return M
