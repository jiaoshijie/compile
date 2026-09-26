local _M = {}
local fmt = string.format

--- @param msg string
_M.echo_info_msg = function(msg)
    vim.api.nvim_echo({ { fmt("compile.lua: %s", msg) } }, true, { err = false })
end

--- @param msg string
_M.echo_err_msg = function(msg)
    vim.api.nvim_echo({ { fmt("compile.lua: %s", msg) } }, true, { err = true })
end

_M.if_nil = function(val, default)
    return val == nil and default or val
end

--- @param bufnr integer
--- @param cb fun()
_M.modify_buf = function(bufnr, cb)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    local opts = { buf = bufnr, scope = "local" }

    vim.api.nvim_set_option_value("modifiable", true, opts)
    cb()
    vim.api.nvim_set_option_value("modifiable", false, opts)
end

--- @param winid integer?
--- @return boolean
_M.winid_in_tab = function(winid)
    if winid == nil then return false end
    return vim.fn.tabpagenr() == vim.fn.win_id2tabwin(winid)[1]
end

--- @param winid integer
--- @return boolean
_M.is_valid_target_winid = function(winid)
    if winid ~= 0 and vim.api.nvim_win_is_valid(winid)
        and _M.winid_in_tab(winid)
        and not vim.api.nvim_get_option_value('winfixbuf', { win = winid })
        and vim.api.nvim_win_get_config(winid).relative == ""  -- not a floating window
    then
        return true
    end
    return false
end

--- @param winid integer
--- @return boolean
_M.is_valid_target_winid2 = function(winid)
    if not vim.api.nvim_get_option_value('winfixbuf', { win = winid })
        and vim.api.nvim_win_get_config(winid).relative == ""  -- not a floating window
    then
        return true
    end
    return false
end

_M.redraw = function()
    local ctrl_l = vim.api.nvim_replace_termcodes("<C-l>", true, false, true)
    vim.api.nvim_feedkeys(ctrl_l, "n", false)
end

--- @param path string
--- @return string
_M.normalize_path = function(path)
    return vim.fs.normalize(path, { expand_env = true, win = false })
end

--- @param path string
--- @return string
_M.normalize_path_no_env = function(path)
    return vim.fs.normalize(path, { expand_env = false, win = false })
end

--- @param path string
--- @return boolean
_M.is_absolute_path = function(path)
    return path:sub(1, 1) == "/"
end

return _M
