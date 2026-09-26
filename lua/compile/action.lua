local constants = require("compile.constants")
local kit = require("compile.kit")
local ui = require("compile.ui")
local task_lib = require("compile.tasks")
local compile_task_lib = require("compile.tasks.compile")
local fmt = string.format
local get_val = task_lib.get_cfg_val

local _M = {}

_M.recompile = function(ctx)
    if ctx.type ~= constants.CompileType.COMP then
        return
    end

    if not ctx.cmd or #ctx.cmd == 0 then
        return
    end

    compile_task_lib.run(ctx, ctx.cmd, ctx.lcfg)
end

_M.kill_compilation = function(ctx)
    if ctx.type ~= constants.CompileType.COMP then
        return
    end

    compile_task_lib.stop_task(ctx, false)
end

local send_input = function(ctx, input)
    vim.cmd("redraw")

    if not input then
        return
    end
    if not compile_task_lib.is_running(ctx) then
        kit.echo_info_msg("job has already finished.")
        return
    end

    local ok, reason = pcall(vim.fn.chansend, ctx.job_id, input .. "\n")

    if not ok and type(reason) == "string" then
        kit.echo_err_msg(reason)
    end
end

local stdin = function(ctx, is_secret)
    if ctx.type ~= constants.CompileType.COMP then
        return
    end

    if not compile_task_lib.is_running(ctx) then
        kit.echo_info_msg("job is not running.")
        return
    end

    if not is_secret then
        vim.ui.input({ prompt = ctx.remain_chunk or "stdin: " }, function(input)
            send_input(ctx, input)
        end)
    else
        local input = vim.fn.inputsecret(ctx.remain_chunk or "password: ")
        send_input(ctx, input)
    end
end

_M.stdin = function(ctx)
    stdin(ctx, false)
end

_M.stdin_secret = function(ctx)
    stdin(ctx, true)
end

--- @return boolean
local cmp = function(msg, last_msg, skip)
    if not skip or not last_msg then return false end

    return vim.deep_equal(msg.fe, last_msg.fe)
        and msg.line == last_msg.line
        and msg.col == last_msg.col
        and msg.line_end == last_msg.line_end
        and msg.col_end == last_msg.col_end
end

local file_cmp = function(msg, last_msg, _)
    return vim.deep_equal(msg.fe, last_msg and last_msg.fe)
end

local next_err = function(ctx, cmp_cb)
    local skip_threshold = get_val("skip_threshold", ctx.lcfg) or constants.Severity.WARNING

    local cur = vim.api.nvim_win_get_cursor(0)
    local lnum = cur[1] + 1
    local max_lnum = vim.api.nvim_buf_line_count(0)
    local skip = get_val("skip_the_same_location", ctx.lcfg)

    local cur_msg = task_lib.get_msg(ctx, cur[1])

    while lnum < max_lnum do
        local msg = task_lib.get_msg(ctx, lnum)
        if msg and msg.type >= skip_threshold
            and not cmp_cb(msg, cur_msg, skip) then
            vim.api.nvim_win_set_cursor(0, { lnum, 0 })
            vim.cmd("normal! zz")
            ui.attention(get_val("highlight_on_select"), 0,
                { lnum - 1, 0 }, { lnum - 1, -1 })
            return true
        end
        lnum = lnum + 1
    end

    kit.echo_info_msg(fmt("No next %s found", get_val("error_msg", ctx.lcfg)))
    return false
end

local prev_err = function(ctx, cmp_cb)
    local skip_threshold = get_val("skip_threshold", ctx.lcfg) or constants.Severity.WARNING
    local cur = vim.api.nvim_win_get_cursor(0)
    local lnum = cur[1] - 1
    local skip = get_val("skip_the_same_location", ctx.lcfg)

    local cur_msg = task_lib.get_msg(ctx, cur[1])

    while lnum > 1 do
        local msg = task_lib.get_msg(ctx, lnum)
        if msg and msg.type >= skip_threshold
            and not cmp_cb(msg, cur_msg, skip) then
            vim.api.nvim_win_set_cursor(0, { lnum, 0 })
            vim.cmd("normal! zz")
            ui.attention(get_val("highlight_on_select"), 0,
                { lnum - 1, 0 }, { lnum - 1, -1 })
            return true
        end
        lnum = lnum - 1
    end

    kit.echo_info_msg(fmt("No previous %s found", get_val("error_msg", ctx.lcfg)))
    return false
end

--- @return integer the window id that the bufnr will be placed at
local chose_window = function()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local cur_winid = vim.api.nvim_get_current_win()

    -- 1. first try to use the last window to open the file
    local target_winid = vim.fn.win_getid(vim.fn.winnr('#'))
    if kit.is_valid_target_winid(target_winid)
        and target_winid ~= cur_winid then
        return target_winid
    end

    -- 2. if the first window is not the compilation window,
    --    use the first window(window number is 1) in the current tabpage to open the file
    if vim.fn.winnr() ~= 1 then
        target_winid =  vim.fn.win_getid(1)
        if kit.is_valid_target_winid(target_winid) then
            return target_winid
        end
    end

    -- 3. else try to use other window number to open the file
    for _, win in ipairs(wins) do
        if win ~= cur_winid and kit.is_valid_target_winid2(win) then
            return win
        end
    end

    -- 4. finally, creating a new window open the file
    --    the compilation window is the only window in this tabpage
    --    or all the rest of windows have winfixbuf option set
    local split = "below"
    if #wins == 1 and vim.o.columns >= 160 then
        split = "right"
    end

    return vim.api.nvim_open_win(0, false, {
        win = -1,
        split = split,
        noautocmd = true,
    })
end

_M.next_error = function(ctx)
    return next_err(ctx, cmp)
end

_M.prev_error = function(ctx)
    return prev_err(ctx, cmp)
end

_M.next_file = function(ctx)
    next_err(ctx, file_cmp)
end

_M.prev_file = function(ctx)
    prev_err(ctx, file_cmp)
end

local get_path_from_fe = function(ctx, fe, lnum)
    if fe.fixed_path and vim.uv.fs_stat(fe.fixed_path) then
        return fe.fixed_path
    end

    local path = fe.dname and fmt("%s/%s", fe.dname, fe.fname) or fe.fname

    if vim.uv.fs_stat(path) then
        return path
    end

    if fe.dname and get_val("search_whole_directory_stack", ctx.lcfg) then
        local dir_stack = task_lib.get_dir_stack(ctx, lnum)
        local index = #dir_stack - 1  -- skip the last one, because it is the dname
        while index > 0 do
            local fixed_path = fmt("%s/%s", dir_stack[index], fe.fname)
            if vim.uv.fs_stat(fixed_path) then
                fe.fixed_path = fixed_path
                return fe.fixed_path
            end
            index = index - 1
        end
    end

    local search_paths = get_val("search_paths", ctx.lcfg)
    if type(search_paths) == "table" and #search_paths > 0 then
        for _, dname in ipairs(search_paths) do
            local fixed_path = fmt("%s/%s", dname, fe.fname)
            if vim.uv.fs_stat(fixed_path) then
                fe.fixed_path = fixed_path
                return fe.fixed_path
            end
        end
    end

    local ok, fixed_path = pcall(vim.fn.input, {
        prompt = fmt("Find this %s in: ", get_val("error_msg", ctx.lcfg)),
        default = path,
        completion = "file",
        cancelreturn = "",
    })

    if ok and #fixed_path > 1 and string.sub(fixed_path, 1, 1) == "/"
        and vim.uv.fs_stat(fixed_path) then
        fe.fixed_path = fixed_path
        return fe.fixed_path
    end

    kit.echo_err_msg(fmt("%s does not exist", ok and fixed_path or path))
    return nil
end

_M.display_error = function(ctx)
    local cur = vim.api.nvim_win_get_cursor(0)
    local lnum = cur[1]

    local msg = task_lib.get_msg(ctx, lnum)

    if not msg then
        kit.echo_info_msg(fmt("No %s here", get_val("error_msg", ctx.lcfg)))
        return nil
    end

    local abs_path = get_path_from_fe(ctx, msg.fe, lnum)
    if not abs_path then return nil end

    -- three situations here.
    -- 1. path has been loaded and buffer is being displayed in a window
    -- 2. path has been loaded but buffer isn't displayed in any window
    -- 3. path isn't loaded.
    local bufnr = vim.fn.bufnr(abs_path)
    local winid = nil
    if vim.api.nvim_buf_is_loaded(bufnr) then
        winid = vim.fn.bufwinid(bufnr)
        if winid == -1 or not kit.winid_in_tab(winid) then
            winid = chose_window()
            vim.api.nvim_win_set_buf(winid, bufnr)
        end
    else
        winid = chose_window()
        bufnr = vim.api.nvim_win_call(winid, function()
            vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))
            return vim.api.nvim_get_current_buf()
        end)
    end

    local coci = get_val("compile_output_column_index", ctx.lcfg)
    local ok = pcall(vim.api.nvim_win_set_cursor, winid, {
        msg.line or 1,
        msg.col and msg.col - coci or 0,
    })

    if ok then
        ui.attention(get_val("highlight_on_select"), bufnr, {
            (msg.line or 1) - 1,
            msg.col and msg.col - coci or 0,
        }, {
            (msg.line_end or msg.line or 1) - 1,
            msg.col_end and msg.col_end - coci or -1,
        })
    else
        kit.echo_err_msg("Invalid cursor line: out of range")
    end

    return winid
end

_M.select_error = function(ctx)
    local winid = _M.display_error(ctx)
    if winid then
        vim.fn.win_gotoid(winid)
    end
end

_M.display_next_error = function(ctx)
    if _M.next_error(ctx) then
        _M.display_error(ctx)
    end
end

_M.display_prev_error = function(ctx)
    if _M.prev_error(ctx) then
        _M.display_error(ctx)
    end
end

--- @param level CompileSeverity?
_M.set_skip_threshold = function(ctx, level)
    if type(level) ~= "number" then
        level = get_val("skip_threshold", ctx.lcfg)
        print(constants.get_str_by_severity(level))
        return
    end

    ctx.lcfg.skip_threshold = constants.get_valid_severity(level)
end

return _M
