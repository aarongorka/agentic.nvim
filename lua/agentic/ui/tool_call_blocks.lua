--- @class agentic.ui.ToolCallBlocks
local ToolCallBlocks = {}

ToolCallBlocks.NS_TOOL_BLOCKS =
    vim.api.nvim_create_namespace("agentic_tool_blocks")

--- Number of lines between a block's start_row and its body's first line.
--- Layout: row 0 = header line, row 1 = blank separator, row 2 = body start.
--- Kept in sync with `MessageWriter:_prepare_block_lines`.
ToolCallBlocks.HEADER_HEIGHT = 2

--- @class agentic.ui.ToolCallBlocks.Range
--- @field start_row integer
--- @field end_row integer

--- Statuscolumn calls this per visible line per redraw, so index all blocks
--- once per buffer change instead of querying extmarks for every line.
--- @type table<integer, {tick: integer, ranges: agentic.ui.ToolCallBlocks.Range[]}>
local range_cache = {}

--- @param bufnr integer
--- @return agentic.ui.ToolCallBlocks.Range[] ranges sorted by start_row
function ToolCallBlocks._ranges(bufnr)
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local cached = range_cache[bufnr]
    if cached and cached.tick == tick then
        return cached.ranges
    end

    local ranges = {}
    local ok, extmarks = pcall(
        vim.api.nvim_buf_get_extmarks,
        bufnr,
        ToolCallBlocks.NS_TOOL_BLOCKS,
        0,
        -1,
        { details = true }
    )
    if ok then
        for _, extmark in ipairs(extmarks) do
            local end_row = (extmark[4] or {}).end_row
            if end_row then
                ranges[#ranges + 1] =
                    { start_row = extmark[2], end_row = end_row }
            end
        end
    end

    range_cache[bufnr] = { tick = tick, ranges = ranges }
    return ranges
end

--- @param bufnr integer
--- @param row integer
--- @return agentic.ui.ToolCallBlocks.Range|nil range
function ToolCallBlocks.block_range_at_row(bufnr, row)
    if row < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    local ranges = ToolCallBlocks._ranges(bufnr)
    local lo, hi = 1, #ranges
    local found --- @type agentic.ui.ToolCallBlocks.Range|nil
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if ranges[mid].start_row <= row then
            found = ranges[mid]
            lo = mid + 1
        else
            hi = mid - 1
        end
    end

    if not found then
        return nil
    end

    -- Match extmark query order: earliest-starting range covering the row.
    local idx = lo - 1
    local result --- @type agentic.ui.ToolCallBlocks.Range|nil
    while idx >= 1 and ranges[idx].end_row >= row do
        result = ranges[idx]
        idx = idx - 1
    end
    return result
end

--- @param bufnr integer
--- @param direction integer
--- @param count integer
--- @param cursor_row integer
--- @return integer|nil row
function ToolCallBlocks.navigation_target_row(
    bufnr,
    direction,
    count,
    cursor_row
)
    if count < 1 or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    --- @type integer[]|integer
    local start
    --- @type integer[]|integer
    local finish

    if direction > 0 then
        start = { cursor_row + 1, 0 }
        finish = -1
    elseif cursor_row > 0 then
        -- When cursor sits inside a block, jump past its anchor so the
        -- backward search lands on the previous block, not the current one.
        local current = ToolCallBlocks.block_range_at_row(bufnr, cursor_row)
        local search_from = current and current.start_row or cursor_row
        if search_from <= 0 then
            return nil
        end
        start = { search_from - 1, -1 }
        finish = { 0, 0 }
    else
        return nil
    end

    local ok, extmarks = pcall(
        vim.api.nvim_buf_get_extmarks,
        bufnr,
        ToolCallBlocks.NS_TOOL_BLOCKS,
        start,
        finish,
        { limit = count }
    )

    if not ok or not extmarks or not extmarks[count] then
        return nil
    end

    return extmarks[count][2] + ToolCallBlocks.HEADER_HEIGHT
end

return ToolCallBlocks
