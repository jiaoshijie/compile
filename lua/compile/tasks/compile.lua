local kit = require("compile.kit")
local ui = require("compile.ui")
local constants = require("compile.constants")
local task_lib = require("compile.tasks")
local if_nil = kit.if_nil
local get_val = task_lib.get_cfg_val
local fmt = string.format

local _M = {}

local unique_id = 0

--- @param ctx CompileCtx
--- @return boolean
local should_kill = function(ctx)
    if not _M.is_running(ctx) then return true end

    local choice = vim.fn.confirm(
        "A compilation process is running, kill it?",
        "&Yes\n&No", 2, "Question"
    )
    if choice == 2 then return false end

    ctx.is_terminated = true
    if _M.is_running(ctx) then
        vim.fn.jobstop(ctx.job_id)
    end
    return true
end

local refresh_env = function(lcfg)
    lcfg.env = if_nil(get_val("env", lcfg), {})

    lcfg.env["TERM"] = "dumb"  -- disable most of control sequences support
    lcfg.env["PAGER"] = ""   -- clear the pager variable, in case some program(git log) will use it
    lcfg.env["MANPAGER"] = ""   -- clear the pager variable, in case some program(git log) will use it
    if get_val("clear_env", lcfg) then
        lcfg.env["LANG"] = if_nil(lcfg.env["LANG"], "C")
        lcfg.env["LC_ALL"] = if_nil(lcfg.env["LC_ALL"], "C")
        lcfg.env["USER"] = if_nil(lcfg.env["USER"], vim.env.USER)
        lcfg.env["HOME"] = if_nil(lcfg.env["HOME"], vim.env.HOME)
        lcfg.env["PATH"] = if_nil(lcfg.env["PATH"], vim.env.PATH)
        lcfg.env["SHELL"] = if_nil(lcfg.env["SHELL"], vim.o.shell)
    end

    return lcfg
end


local init_ctx = function(ctx, cmd, lcfg, work_id)
    -- base class
    ctx.lcfg = refresh_env(lcfg)
    task_lib.init_base_ctx(ctx)

    -- child class
    ctx.cmd = cmd

    ctx.task_id = work_id
    ctx.job_id = nil
    ctx.start_time = vim.uv.hrtime()
    ctx.is_terminated = false
    ctx.remain_chunk = nil

    ctx.mismatched_lines = {}

    ctx.hl_table = {}

    ctx.cache_lines = {}
    ctx.cache_lnum = nil
    if ctx.defer_obj and not vim.uv.is_closing(ctx.defer_obj) then
        vim.uv.timer_stop(ctx.defer_obj)
        vim.uv.close(ctx.defer_obj)
    end
    ctx.defer_obj = nil
end

local cleanup = function(ctx)
    vim.b[ctx.bufnr].channel = nil

    ctx.parse_info = nil

    ctx.task_id = nil
    ctx.job_id = nil
    ctx.start_time = nil
    ctx.is_terminated = nil
    ctx.remain_chunk = nil
    ctx.mismatched_lines = nil

    ctx.cache_lines = nil
    ctx.cache_lnum = nil
    if ctx.defer_obj and not vim.uv.is_closing(ctx.defer_obj) then
        vim.uv.timer_stop(ctx.defer_obj)
        vim.uv.close(ctx.defer_obj)
    end
    ctx.defer_obj = nil
end

--- @param ctx CompileCtx
--- @param lines string[]
--- @param finished boolean
local parse = function(ctx, lines, finished)
    local parse_info = ctx.parse_info
    assert(parse_info)

    if ctx.mismatched_lines and #ctx.mismatched_lines > 0 then
        lines = vim.list_extend(ctx.mismatched_lines, lines)
    end
    ctx.mismatched_lines = {}

    parse_info.mismatched_index = nil
    parse_info.matched = {}
    parse_info.eof = finished

    local output_hook = get_val("on_output_hook_fn", ctx.lcfg)
    if type(output_hook) == "function" then
        lines = output_hook(ctx, parse_info.lnum, lines)
    end

    task_lib.parse(ctx, lines)

    if parse_info.mismatched_index and not finished then
        ctx.mismatched_lines = vim.list_slice(lines, parse_info.mismatched_index)
        lines = vim.list_slice(lines, 1, parse_info.mismatched_index - 1)
    end

    local output_parsed_hook = get_val("on_output_parsed_hook_fn", ctx.lcfg)
    if type(output_parsed_hook) == "function" then
        local new_lines = output_parsed_hook(ctx, parse_info.lnum, lines)
        if #new_lines == #lines then
            lines = new_lines
        end
    end

    -- put all lines into compilation buffer
    if #lines > 0 then
        ui.set_lines(ctx, parse_info.lnum, lines)
        local output_inserted_hook = get_val("on_output_inserted_hook_fn", ctx.lcfg)
        if type(output_inserted_hook) == "function" then
            output_inserted_hook(ctx, parse_info.lnum, parse_info.lnum + #lines - 1)
        end
        parse_info.lnum = parse_info.lnum + #lines
    end
end

local set_buf_options = function(bufnr)
    local opts = { buf = bufnr, scope = "local" }

    vim.api.nvim_set_option_value("modifiable", false, opts)
    vim.api.nvim_set_option_value('modeline', false, opts)
    vim.api.nvim_set_option_value('buflisted', true, opts)
    vim.api.nvim_set_option_value('buftype', "nofile", opts)
    vim.api.nvim_set_option_value('bufhidden', "hide", opts)
    vim.api.nvim_set_option_value('swapfile', false, opts)
    vim.api.nvim_set_option_value('filetype', 'compilation', opts)
    vim.api.nvim_set_option_value("undolevels", -1, opts)  -- disable undo/redo
end

local load_buf = function(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
        set_buf_options(bufnr)
    end
end

--- @param winid integer
local set_win_options = function(winid)
    if not vim.api.nvim_win_is_valid(winid) then
        return
    end

    local opts = { win = winid, scope = "local" }

    vim.api.nvim_set_option_value('cursorline', true, opts)
    vim.api.nvim_set_option_value('number', false, opts)
    vim.api.nvim_set_option_value('relativenumber', false, opts)
    vim.api.nvim_set_option_value('wrap', false, opts)
    vim.api.nvim_set_option_value('spell', false, opts)
    vim.api.nvim_set_option_value('signcolumn', 'no', opts)
    vim.api.nvim_set_option_value('foldenable', false, opts)
    vim.api.nvim_set_option_value('colorcolumn', '0', opts)
end

--- @param ctx CompileCtx
--- @param ret_code integer
local job_finish = function(ctx, ret_code)
    ui.render_stop_info_comp(ctx, ret_code)
    ui.flush_cache(ctx)  -- NOTE: make sure all lines has been flushed
    ctx.stat_info.ret_code = ret_code
    cleanup(ctx)
    vim.cmd([[redrawstatus!]])
end

--- @param ctx CompileCtx
--- @param cmd string
local parse_cmd_leading_cd = function(ctx, cmd)
    local cmd_cd_matcher = get_val("cmd_cd_matcher", ctx.lcfg)

    if vim.lpeg.type(cmd_cd_matcher) ~= "pattern" then
        return
    end

    local cap = cmd_cd_matcher:match(cmd)

    if not cap then return end

    if not cap.dir then
        table.insert(ctx.dir_stack, vim.env.HOME)
        return
    end

    local path = cap.dir
    local ch = path:sub(1, 1)

    if ch == "'" then
        path = path:sub(2, #path - 1)
    else
        if ch == '"' then path = path:sub(2, #path - 1) end
        path = kit.normalize_path_no_env(path:gsub("\\(.)", "%1"))
    end

    if kit.is_absolute_path(path) then
        table.insert(ctx.dir_stack, path)
    else
        assert(#ctx.dir_stack == 1)
        table.insert(ctx.dir_stack,
            kit.normalize_path_no_env(fmt("%s/%s", ctx.dir_stack[1], path)))
    end
end

------------------------------------------------------------------------------

--- @param ctx CompileCtx
--- @return boolean
_M.is_running = function(ctx)
    return ctx.job_id ~= nil and vim.fn.jobwait({ ctx.job_id }, 0)[1] == -1
end

--- @param buf_name string
--- @return CompileCtx
_M.new_task = function(bufnr, buf_name)
    if not bufnr or bufnr == -1
        or not vim.api.nvim_buf_is_valid(bufnr) then
        bufnr = vim.api.nvim_create_buf(true, false)
    end

    vim.api.nvim_buf_set_name(bufnr, buf_name)

    local ctx = {
        type = constants.CompileType.COMP,
        bufnr = bufnr,
        augroup_name = fmt("compile_lua_event_compile_%d", bufnr),
    }

    set_buf_options(bufnr)
    return ctx
end

--- @param ctx CompileCtx
--- @param cmd string
--- @param lcfg table local cfg
_M.run = function(ctx, cmd, lcfg)
    if not should_kill(ctx) then
        return
    end

    local work_id = unique_id
    unique_id = unique_id + 1
    init_ctx(ctx, cmd, lcfg, work_id)
    load_buf(ctx.bufnr)

    parse_cmd_leading_cd(ctx, cmd)

    ui.render_start_info_comp(ctx)

    if not get_val("background", ctx.lcfg) then
        local winid = ui.display_com_win(ctx.bufnr)
        set_win_options(winid)
    end

    local ok, ret = pcall(vim.fn.jobstart, ctx.cmd, {
        pty = true,
        stdin = "pipe",
        cwd = ctx.dir_stack[1],
        clear_env = get_val("clear_env", lcfg),
        env = get_val("env", lcfg),
        on_exit = function(_, ret_code, _)
            if ctx.is_terminated or work_id ~= ctx.task_id then return end

            if ctx.remain_chunk == "" then
                ctx.remain_chunk = nil
            end

            parse(ctx, { ctx.remain_chunk }, true)

            job_finish(ctx, ret_code)

            local job_finished_hook = get_val("on_job_finished_hook_fn", ctx.lcfg)
            if type(job_finished_hook) == "function" then
                job_finished_hook(ret_code)
            end
        end,
        on_stdout = function(_, data, _)
            if ctx.is_terminated or work_id ~= ctx.task_id then return end

            data = vim.tbl_map(function(s)
                return s:gsub("\n", "\0"):gsub("\r$", "")
            end, data)

            if ctx.remain_chunk and #ctx.remain_chunk > 0 then
                data[1] = ctx.remain_chunk .. data[1]
            end

            ctx.remain_chunk = table.remove(data)

            if #data <= 0 then return end

            parse(ctx, data, false)
        end,
    })

    if not ok then
        -- NOTE: no any hook funcitons will be called
        local parse_info = ctx.parse_info
        assert(parse_info)

        if type(ret) == "string" then
            local lines = vim.fn.split(ret, '\n')
            table.insert(lines, 1, "Neovim Compile Plugin Internal Error:")
            ui.set_lines(ctx, parse_info.lnum, lines)
            parse_info.lnum = parse_info.lnum + #lines
        end

        job_finish(ctx, -1)
        return
    end

    ctx.job_id = ret
    vim.b[ctx.bufnr].channel = ctx.job_id

    if get_val("close_stdin", ctx.lcfg) then
        vim.fn.chansend(ctx.job_id, string.char(4))
    end

    local job_started_hook = get_val("on_job_started_hook_fn", ctx.lcfg)
    if type(job_started_hook) == "function" then
        vim.api.nvim_buf_call(ctx.bufnr, function()
            job_started_hook(ctx.job_id)
        end)
    end
end

--- @param ctx CompileCtx
_M.stop_task = function(ctx, force)
    if not _M.is_running(ctx) then return end

    if not force then
        local choice = vim.fn.confirm(
            "Stop the running compilation process?",
            "&Yes\n&No", 2, "Question"
        )
        if choice == 2 then return end
    else
        ctx.is_terminated = true
    end

    vim.fn.jobstop(ctx.job_id)

    if force then
        cleanup(ctx)
    end
end

_M.set_events = function(ev_group, bufnr, tasks)
    vim.api.nvim_create_autocmd("BufWinEnter", {
        buffer = bufnr,
        group = ev_group,
        callback = function(_)
            set_win_options(vim.fn.win_getid())
        end,
    })

    vim.api.nvim_create_autocmd("BufReadCmd", {
        buffer = bufnr,
        group = ev_group,
        callback = function(ev)
            local t = tasks[ev.buf]
            if not t or t.type ~= constants.CompileType.COMP then
                return
            end

            --- @cast t CompileCtx
            _M.stop_task(t, true)

            if not t.cmd or #t.cmd == 0 then
                return
            end

            _M.run(t, t.cmd, t.lcfg)
        end,
    })

    vim.api.nvim_create_autocmd("BufUnload", {
        buffer = bufnr,
        group = ev_group,
        callback = function(ev)
            local t = tasks[ev.buf]
            if not t or t.type ~= constants.CompileType.COMP then
                return
            end

            --- @cast t CompileCtx
            _M.stop_task(t, true)
        end,
    })
end

return _M
