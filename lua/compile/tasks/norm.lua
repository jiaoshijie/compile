local ui = require("compile.ui")
local constants = require("compile.constants")
local task_lib = require("compile.tasks")
local kit = require("compile.kit")
local fmt = string.format

local _M = {}

local init_ctx = function(ctx)
    local cwd = vim.fn.expand(task_lib.get_cfg_val("cwd", ctx.lcfg))

    --- @cast cwd string
    ctx.dir_stack = { kit.unify_path(cwd or vim.fn.getcwd(), true) }
    ctx.dir_stack_arr = {}
    ctx.lookup = {}
    ctx.debug = nil
    ctx.stat_info = {
        ret_code = false,
        [constants.Severity.ERROR] = 0,
        [constants.Severity.HINT] = 0,
        [constants.Severity.INFO] = 0,
        [constants.Severity.WARNING] = 0,
    }
    ctx.parse_info = {
        lnum = 0,
        fe_table = {},
        last_fe = nil,
        mismatched_index = nil,
        matched = {},
        eof = true,
    }

    if ctx.type == constants.CompileType.NORMRO then
        -- child class
        ctx.hl_table = {}
    end
end

local parse = function(ctx)
    init_ctx(ctx)

    if ctx.type == constants.CompileType.NORMRO then
        local opts = { buf = ctx.bufnr, scope = "local" }
        vim.api.nvim_set_option_value("modifiable", false, opts)
    end

    task_lib.parse(ctx, vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false))
    ctx.parse_info = nil
    kit.redraw()
end

local reparse = function(ctx)
    if ctx.type == constants.CompileType.NORMRO then
        ctx.hl_table = nil
    end

    ui.clear(ctx)
    parse(ctx)
end

_M.cleanup = function(ctx)
    ctx.dir_stack = nil
    ctx.dir_stack_arr = nil
    ctx.lookup = nil
    ctx.debug = nil
    ctx.parse_info = nil

    if ctx.type == constants.CompileType.NORMRO then
        vim.api.nvim_set_option_value("modifiable", ctx.old_modifiable,
            { buf = ctx.bufnr, scope = "local" })
        ctx.hl_table = nil
    end

    ui.clear(ctx)
    kit.redraw()
end

_M.parse = function(typ, bufnr, lcfg)
    local ctx = {
        -- base class
        type = typ,
        bufnr = bufnr,
        augroup_name = fmt("compile_lua_event_norm_%d", bufnr),
        lcfg = lcfg,
    }

    if ctx.type == constants.CompileType.NORMRO then
        -- child class
        local opts = { buf = ctx.bufnr, scope = "local" }
        ctx.old_modifiable = vim.api.nvim_get_option_value("modifiable", opts)
    end

    parse(ctx)

    return ctx
end

_M.set_events = function(ev_group, bufnr, tasks)
    vim.api.nvim_create_autocmd("BufReadPost", {
        buffer = bufnr,
        group = ev_group,
        callback = function(ev)
            local t = tasks[ev.buf]
            if not t then
                return
            end

            if t.type ~= constants.CompileType.NORMRO
                and t.type ~= constants.CompileType.NORMRW then
                return
            end

            reparse(t)
        end,
    })
end

return _M
