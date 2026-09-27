local constants = require("compile.constants")
local kit = require("compile.kit")
local ui = require("compile.ui")
local cfg = require("compile.config")
local action = require("compile.action")
local fmt = string.format

local task_entries = {
    [constants.CompileType.COMP] = require("compile.tasks.compile"),
    [constants.CompileType.NORMRO] = require("compile.tasks.norm"),
    [constants.CompileType.NORMRW] = require("compile.tasks.norm"),
}

--- @type table<integer, TaskCtx>
local tasks = {}

local _M = {}

--- @param typ CompileType
--- @return boolean
local validate_env = function(typ)
    -- 1. if the focused window is command line
    if vim.fn.win_gettype() == "command" then
        kit.echo_err_msg("Unable to open from command-line window: `:h E11`")
        return false
    end
    -- 2. check buftype
    if typ ~= constants.CompileType.COMP and #vim.bo.buftype > 0 then
        kit.echo_err_msg(fmt("buftype %s is not supported", vim.bo.buftype))
        return false
    end

    -- 3. task env validation
    if task_entries[typ] == nil then return false end

    -- 4. init namespace
    ui.init_namespaces(tasks, typ)

    return true
end

local set_keymaps = function(task)
    local opts = { silent = true, buffer = task.bufnr }

    for k, v in pairs(cfg.keymap[task.type]) do
        pcall(vim.keymap.del, "n", k, opts)
        vim.keymap.set("n", k, function() action[v](task) end, opts)
    end
end

local unset_keymaps = function(task)
    local opts = { silent = true, buffer = task.bufnr }

    for k, _ in pairs(cfg.keymap[task.type]) do
        pcall(vim.keymap.del, "n", k, opts)
    end
end

local unset_events = function(task)
    assert(type(task.augroup_name) == "string")
    vim.api.nvim_del_augroup_by_name(task.augroup_name)
end

local set_events = function(task)
    assert(type(task.augroup_name) == "string")
    local ev_group = vim.api.nvim_create_augroup(task.augroup_name, { clear = true })

    if type(task_entries[task.type].set_events) == "function" then
        task_entries[task.type].set_events(ev_group, task.bufnr, tasks)
    end

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        buffer = task.bufnr,
        group = ev_group,
        callback = function(ev)
            local t = tasks[ev.buf]
            if not t then return end

            if t.type == constants.CompileType.COMP then
                task_entries[task.type].stop_task(t, true)
            end

            unset_events(t)
            tasks[ev.buf] = nil
        end,
    })
end

local set_user_cmd = function(task)
    vim.api.nvim_buf_create_user_command(task.bufnr, "CompileSetLevel", function(args)
        local level_str = args.args
        local level = constants.get_severity_by_str(level_str)

        if not level and #level_str ~= 0 then
            kit.echo_err_msg(fmt("Invalid level string: %s", level_str))
            return
        end

        action.set_skip_threshold(task, level)
    end, { nargs = "?", complete = function(_, _, _)
        return constants.get_severity_strs()
    end })

    vim.api.nvim_buf_create_user_command(task.bufnr, "CompileDebug", function(args)
        if args.bang then
            vim.print(task)
            return
        end
        local content = task[args.args] or task

        if type(content) == "table" then
            ui.tmp_debug_tabwin(vim.fn.split(vim.inspect(content), '\n'))
        else
            vim.print(content)
        end
    end, { nargs = "?", bang = true, complete = function(arg_lead, _, _)
        print(arg_lead)
        return vim.tbl_map(function(item)
            return vim.startswith(item, arg_lead) and item or nil
        end, vim.tbl_keys(task))
    end })
end

local unset_user_cmd = function(task)
    vim.api.nvim_buf_del_user_command(task.bufnr, "CompileSetLevel")
    vim.api.nvim_buf_del_user_command(task.bufnr, "CompileDebug")
end

_M.compile = function(cmd, buf_name, lcfg)
    local typ = constants.CompileType.COMP

    if cmd == nil or #cmd == 0 then
        kit.echo_err_msg("CompileTask: empty command is not allowed")
        return false
    end

    if not validate_env(typ) then
        return
    end

    local entry = task_entries[typ]
    buf_name = fmt("compile_lua://%s", buf_name or constants.default_name)

    -- 1. get task
    local bufnr = vim.fn.bufnr(buf_name)
    local task = bufnr ~= -1 and tasks[bufnr] or nil

    if not task then
        -- 2. if failed, create new one
        task = entry.new_task(bufnr, buf_name)
        tasks[task.bufnr] = task
        set_keymaps(task)
        set_events(task)
        set_user_cmd(task)
    end

    if task.type ~= constants.CompileType.COMP then
        kit.echo_err_msg(fmt("CompileTask: A buffer with %s name already exists.", buf_name))
        return
    end

    --- @cast task CompileCtx
    -- 3. run this task
    entry.run(task, cmd, lcfg)
end

_M.norm = function(ro, bufnr, lcfg)
    local typ = ro and constants.CompileType.NORMRO or constants.CompileType.NORMRW
    if not validate_env(typ) then
        return
    end
    local entry = task_entries[typ]
    local task = tasks[bufnr]

    if task then -- disable
        if task.type ~= typ then
            kit.echo_err_msg(fmt("This buffer enabled ohter task."))
            return
        end

        entry.cleanup(task)
        unset_keymaps(task)
        unset_events(task)
        unset_user_cmd(task)
        tasks[bufnr] = nil
    else
        tasks[bufnr] = entry.parse(typ, bufnr, lcfg)
        set_keymaps(tasks[bufnr])
        set_events(tasks[bufnr])
        set_user_cmd(tasks[bufnr])
    end
end

_M.terminal = function(bufnr, lcfg)
    local _ = bufnr
    local _ = lcfg

    -- BUG: https://github.com/neovim/neovim/issues/42053
    kit.echo_err_msg("TERM task is not supported right now.")
end

--- list all the compilation buffers
_M.ls = function()
    -- format: bufnr type bufname
    for _, task in pairs(tasks) do
        print(fmt("%d %s %s", task.bufnr, constants.type2str(task.type),
            vim.fn.bufname(task.bufnr)))
    end
    print()
end

_M.statusline = function(winid)
    if not vim.api.nvim_win_is_valid(winid) then
        return nil
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)
    local task = tasks[bufnr]
    return task and task.stat_info
end

return _M
