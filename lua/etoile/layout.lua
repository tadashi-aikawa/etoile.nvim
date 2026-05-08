local M = {}

function M.clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function ratio_size(total, ratio)
	if ratio == nil then
		return nil
	end
	return math.floor(total * ratio)
end

function M.resolve_height(opts, total_height, viewport_max_height)
	local preferred_height = math.floor(total_height * (opts.height_ratio or 1))
	local min_height = opts.min_height or 1
	local ratio_min_height = ratio_size(total_height, opts.min_height_ratio)
	local effective_min_height = ratio_min_height and math.min(min_height, ratio_min_height) or min_height

	local max_height = opts.max_height or viewport_max_height
	local ratio_max_height = ratio_size(total_height, opts.max_height_ratio)
	local effective_max_height = ratio_max_height and math.max(max_height, ratio_max_height) or max_height
	effective_max_height = math.max(1, math.min(effective_max_height, viewport_max_height))
	effective_min_height = math.max(1, math.min(effective_min_height, effective_max_height))

	return M.clamp(preferred_height, effective_min_height, math.max(1, effective_max_height))
end

function M.resolve_row(height, total_height)
	local max_row = math.max(0, total_height - height)
	return M.clamp(math.floor((total_height - height) / 2), 0, max_row)
end

function M.resolve_col(anchor_col, width, total_width, right_margin)
	right_margin = right_margin or 0
	local max_col = math.max(0, total_width - width - right_margin)
	return M.clamp(anchor_col, 0, max_col)
end

return M
