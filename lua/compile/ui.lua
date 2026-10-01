local constants = require("compile.constants")
local kit = require("compile.kit")
local fmt = string.format

-- is 0 an invalid namespace id?
local ns_id = 0

-- only be used by NORM_RW for now
local ns_ln_id = 0
local ns_dir_id = 0

--- @param tasks table
local register_ns_provider = function(tasks)
    local provider_on_range_cb = function(_, _, buf, row_b, _, row_e, col_e)
        local task = tasks[buf]

        if not task or task.type == constants.CompileType.NORMRW
            or task.hl_table == nil then
            return false
        end

        if col_e == 0 then
            row_e = row_e - 1
        end

        for lnum = row_b, row_e do
            local hl = task.hl_table[lnum]
            if hl == nil then goto continue end

            for _, v in ipairs(hl) do
                vim.api.nvim_buf_set_extmark(buf, ns_id, v.spos[1], v.spos[2], {
                    hl_group = v.group,
                    end_line = v.epos[1],
                    end_col = v.epos[2],

                    undo_restore = false,
                    strict = true,  -- default
                    ephemeral = true,
                })
            end

            ::continue::
        end

        return true
    end

    vim.api.nvim_set_decoration_provider(ns_id, {
        on_win = function(_, _, buf, _, _)
            local task = tasks[buf]
            if not task or task.type == constants.CompileType.NORMRW then
                return false
            end
            return true
        end,
        on_range = provider_on_range_cb,
    })
end

local _M = {}

--- @param tasks table
--- @param typ CompileType
_M.init_namespaces = function(tasks, typ)
    if ns_id == 0 then
        ns_id = vim.api.nvim_create_namespace("compile_lua_general_ns")
        register_ns_provider(tasks)
    end

    if typ == constants.CompileType.NORMRW then
        if ns_ln_id == 0 then
            ns_ln_id = vim.api.nvim_create_namespace("compile_lua_link_ns")
        end
        if ns_dir_id == 0 then
            ns_dir_id = vim.api.nvim_create_namespace("compile_lua_dir_stack_ns")
        end
    end
end

_M.attention = function(timeout, bufnr, spos, epos)
    if type(timeout) ~= "number" or timeout <= 0 then
        return
    end

    vim.hl.range(bufnr, ns_id, "CompileLuaAttention", spos, epos, {
        inclusive = false,
        timeout = timeout,
    })
end

--- @return integer winid
local create_com_win = function(bufnr, one_window)
    local split = "below"
    if one_window and vim.o.columns >= 160 then
        split = "right"
    end

    return vim.api.nvim_open_win(bufnr, true, {
        win = -1,
        split = split,
        noautocmd = true,
    })
end

--- @return integer
_M.display_com_win = function(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
        return 0
    end

    -- 0. if the buffer has already been displayed in a window in the tabpage,
    -- simply go to it.
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
        vim.fn.win_gotoid(winid)
        return winid
    end

    -- 1. if there is only one window in this tabpage, create a new window for
    -- displaying the compilation buffer
    local wins = vim.api.nvim_tabpage_list_wins(0)
    if #wins == 1 then
        return create_com_win(bufnr, true)
    end

    -- 2. if there are more than one windows, chose the first valid one window.
    -- valid means can replace the buffer that displays in it and it is not the
    -- window when executing this command
    local cur_winid = vim.api.nvim_get_current_win()
    for _, win in ipairs(wins) do
        if win ~= cur_winid and kit.is_valid_target_winid2(win) then
            vim.api.nvim_win_set_buf(win, bufnr)
            vim.fn.win_gotoid(win)
            return win
        end
    end

    -- 3. if can not find any create a new one.
    return create_com_win(bufnr, false)
end


--- @param task CompileCtx
_M.flush_cache = function(task)
    if not task.bufnr or not vim.api.nvim_buf_is_loaded(task.bufnr) then
        return
    end

    if not task.cache_lines or #task.cache_lines == 0
        or not task.cache_lnum then
        return
    end

    kit.modify_buf(task.bufnr, function()
        vim.api.nvim_buf_set_lines(task.bufnr, task.cache_lnum, -1,
        false, task.cache_lines)
    end)

    task.cache_lines = {}
    task.cache_lnum = nil
    task.defer_obj = nil
end

--- @param task CompileCtx
--- @param lnum integer
--- @param line string
_M.set_line = function(task, lnum, line)
    if #task.cache_lines >= constants.ui.cache_size then
        _M.flush_cache(task)
    end

    if not task.cache_lnum then
        task.cache_lnum = lnum
    end

    if not task.defer_obj then
        task.defer_obj = vim.defer_fn(function()
            _M.flush_cache(task)
        end, constants.ui.cache_flush_interval)
    end

    table.insert(task.cache_lines, line)
end

--- @param task CompileCtx
--- @param lnum integer
--- @param lines string[]
_M.set_lines = function(task, lnum, lines)
    for _, line in ipairs(lines) do
        _M.set_line(task, lnum, line)
        lnum = lnum + 1
    end
end

--- @return boolean
local skip = function(sp, ep, t)
    assert(sp[1] == ep[1])
    local lnum = sp[1]
    local b, e = sp[2], ep[2]

    local it = vim.iter(t)
    local hl = it:next()
    while hl do
        if hl.spos[1] == lnum then
            if e > hl.spos[2] then return true end
        elseif hl.epos[1] == lnum then
            if b < hl.epos[2] then return true end
        end

        hl = it:next()
    end

    return false
end

local skip2 = function(sp, ep, bufnr)
    assert(sp[1] == ep[1])
    local lnum = sp[1]
    local b, e = sp[2], ep[2]

    local hls = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { lnum, 0 },
        { lnum, -1 }, { details = true, hl_name = false, overlap = true })
    vim.list_extend(hls, vim.api.nvim_buf_get_extmarks(bufnr, ns_ln_id,
        { lnum, 0 }, { lnum, -1 },
        { details = true, hl_name = false, overlap = true }))
    vim.list_extend(hls, vim.api.nvim_buf_get_extmarks(bufnr, ns_dir_id,
        { lnum, 0 }, { lnum, -1 },
        { details = true, hl_name = false, overlap = true }))

    for _, hl in ipairs(hls) do
        if hl[2] == lnum then
            if e > hl[3] then return true end
        elseif hl[4].end_row == lnum then
            if b < hl[4].end_col then return true end
        end
    end

    return false
end

-- remove the ui prefix
--- @param matched boolean?
_M.set_hl = function(task, group, spos, epos, matched)

    if task.type == constants.CompileType.COMP
        or task.type == constants.CompileType.NORMRO then
        task.hl_table[spos[1]] = task.hl_table[spos[1]] or {}

        if matched and skip(spos, epos, task.hl_table[spos[1]]) then
            return
        end

        table.insert(task.hl_table[spos[1]], {
            group = group, spos = spos, epos = epos,
        })
    else
        if matched and skip2(spos, epos, task.bufnr) then
            return
        end

        vim.hl.range(task.bufnr, ns_id, group, spos, epos, {
            inclusive = false
        })
    end
end

--- @return integer?
_M.set_link_hl = function(task, spos, epos)
    if task.type == constants.CompileType.COMP
        or task.type == constants.CompileType.NORMRO then
        task.hl_table[spos[1]] = task.hl_table[spos[1]] or {}
        table.insert(task.hl_table[spos[1]], {
            group = "CompileLuaLink", spos = spos, epos = epos,
        })
    else
        return vim.api.nvim_buf_set_extmark(task.bufnr, ns_ln_id, spos[1], spos[2], {
            hl_group = "CompileLuaLink",
            end_line = epos[1],
            end_col = epos[2],

            end_right_gravity = false,  -- default
            right_gravity = true,  -- default
            undo_restore = true,  -- default
            strict = true,  -- default
        })
    end
end

--- @return integer?
_M.set_dir_hl = function(task, spos, epos)
    if task.type == constants.CompileType.COMP
        or task.type == constants.CompileType.NORMRO then
        task.hl_table[spos[1]] = task.hl_table[spos[1]] or {}
        table.insert(task.hl_table[spos[1]], {
            group = "CompileLuaHint", spos = spos, epos = epos,
        })
    else
        return vim.api.nvim_buf_set_extmark(task.bufnr, ns_ln_id, spos[1], epos[2], {
            hl_group = "CompileLuaHint",
            end_line = epos[1],
            end_col = epos[2],

            end_right_gravity = false,  -- default
            right_gravity = true,  -- default
            undo_restore = true,  -- default
            strict = true,  -- default
        })
    end
end

_M.clear = function(task)
    vim.api.nvim_buf_clear_namespace(task.bufnr, ns_id, 0, -1)

    if task.type == constants.CompileType.NORMRW then
        vim.api.nvim_buf_clear_namespace(task.bufnr, ns_ln_id, 0, -1)
        vim.api.nvim_buf_clear_namespace(task.bufnr, ns_dir_id, 0, -1)
    end
end

--- @param task CompileCtx
_M.render_start_info_comp = function(task)
    if not task.bufnr or not vim.api.nvim_buf_is_loaded(task.bufnr) then
        return
    end
    assert(task.parse_info)

    local lnum = task.parse_info.lnum
    local lines = {
        fmt("Working Directory: %s", task.dir_stack[#task.dir_stack]),
        fmt("Compilation started at %s", vim.fn.strftime("%c")),
        fmt("Cmd: %s", task.cmd),
        fmt(""),
    }

    -- NOTE: reset the whole buffer immediately
    _M.clear(task)
    _M.set_lines(task, lnum, lines)
    -- NOTE: make sure the result line has been drawn before set virtual lines
    _M.flush_cache(task)

    _M.set_hl(task, "CompileLuaHint", { lnum, 19 }, { lnum, -1 })
    _M.set_hl(task, "CompileLuaInfo", { lnum + 2, 5 }, { lnum + 2, -1 })

    vim.api.nvim_buf_set_extmark(task.bufnr, ns_id, lnum + 2, 0, {
        virt_lines = { { {  string.rep('-', 255), "CompileLuaSep" } } },
        virt_lines_above = false,
        virt_lines_leftcol = true,
        right_gravity = false,

        undo_restore = false,
        strict = true,  -- default
    })

    task.parse_info.lnum = lnum + #lines
end

--- @param task CompileCtx
--- @param ret_code integer
_M.render_stop_info_comp = function(task, ret_code)
    if not task.bufnr or not vim.api.nvim_buf_is_loaded(task.bufnr) then
        return
    end
    assert(task.parse_info)

    local lnum = task.parse_info.lnum
    local hl_group = "CompileLuaInfo"
    local status = nil

    if ret_code == 0 then
        status = "finished"
    elseif task.lines_limit_reached then
        status = "lines limit reached"
        hl_group = "CompileLuaWarning"
    else
        status = constants.get_err_msg(ret_code)
        hl_group = "CompileLuaError"
    end

    local lines = {
        "",
        fmt("Compilation %s at %s, duration %.03fs", status,
            vim.fn.strftime("%c"), (vim.uv.hrtime() - task.start_time) / 1E9)
    }

    _M.set_lines(task, lnum, lines)
    _M.set_hl(task, hl_group, { lnum + 1, 12 },
        { lnum + 1, 12 + #status })
    -- NOTE: make sure the result line has been drawn before set virtual lines
    _M.flush_cache(task)

    vim.api.nvim_buf_set_extmark(task.bufnr, ns_id, lnum + 1, 0, {
        virt_lines = { { {  string.rep('-', 255), "CompileLuaSep" } } },
        virt_lines_above = true,
        virt_lines_leftcol = true,
        right_gravity = false,

        undo_restore = false,
        strict = true,  -- default
    })

    task.parse_info.lnum = lnum + #lines
end

_M.get_link_extmark_ids = function(bufnr, sp, ep)
    return vim.api.nvim_buf_get_extmarks(bufnr, ns_ln_id, sp, ep,
        { hl_name = false, limit = 1, details = false, overlap = true })
end

_M.get_dir_extmark_ids = function(bufnr, sp)
    return vim.api.nvim_buf_get_extmarks(bufnr, ns_dir_id, sp , -1,
        { hl_name = false, limit = 1, details = false })
end

_M.tmp_debug_tabwin = function(lines)
    vim.cmd("tabnew")
    local bufnr = vim.api.nvim_get_current_buf()
    local opts = { buf = bufnr, scope = "local" }

    vim.api.nvim_set_option_value('modeline', false, opts)
    vim.api.nvim_set_option_value('buftype', "nofile", opts)
    vim.api.nvim_set_option_value('buflisted', false, opts)
    vim.api.nvim_set_option_value('bufhidden', "wipe", opts)
    vim.api.nvim_set_option_value("undolevels", -1, opts)  -- disable undo/redo
    vim.api.nvim_set_option_value('swapfile', false, opts)
    vim.api.nvim_set_option_value('filetype', 'compilation_debug', opts)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

return _M
