--- alias: FE_TABLE
--[[
{
    ["/dir1/dir2/file1"] = (FILE_STRUCT){},
    ["/dir1/dir3"] = {
        ["file2"] = (FILE_STRUCT){},
        ["dir4/file3"] = (FILE_STRUCT){},
    },
}
--]]

--- @class FILE_ENTRY
--- @field fname string a file name or an absoulte path
--- @field dname string? a directory path, nil if fname is an absolute path
--- @field fixed_path string? will be set when first access the file. if the file does not exist, prompt an input box to let the user choose a correct path

--- @class MESSAGE
--- @field fe FILE_ENTRY
--- @field type CompileSeverity
--- @field line integer?
--- @field col integer?
--- @field line_end integer?
--- @field col_end integer?

--- @class DIR_STACK
--- @field stack string[]
--- @field limit integer  -- line number(1-based) | ext_mark_id   (exclusive)

--- one shot parse info ctx
--- @class ParseInfo
--- @field lnum integer 0-based      -- line number
--- @field fe_table table?
--- @field last_fe FILE_ENTRY?
--- @field mismatched_index integer?
--- @field matched table<integer, boolean> table<index, boolean>
--- @field eof boolean end of file

--- @class StatInfo
--- @field ret_code integer? | false  -- false means no job
--- @field [CompileSeverity] integer

------------------------------------------------------------------------------

--- @class TaskCtx
--- @field type CompileType
--- @field bufnr integer
--- @field augroup_name string
-- parse ctx
--- @field lcfg table?
--- @field dir_stack string[]?        -- last directory stack snapshot
--- @field dir_stack_arr DIR_STACK[]?
--- @field lookup table<integer, MESSAGE>?   -- table<line_number | ext_mark_id, MESSAGE>
--- @field debug table<integer, integer | string>?    -- table<lnum, index>
--- @field stat_info StatInfo
--- @field parse_info ParseInfo?

--- @class CompileCtx : TaskCtx
--  job control
--- @field cmd string
--- @field hl_table table { { group, spos, epos } }
--
--- @field task_id integer
--- @field job_id integer
--- @field start_time number
--- @field is_terminated boolean
--- @field remain_chunk string
--- @field mismatched_lines string[]
--  ui
--- @field cache_lines string[]
--- @field cache_lnum integer
--- @field defer_obj uv.uv_timer_t


--- @class NormRoCtx : TaskCtx
--- @field old_modifiable boolean
--  ui
--- @field hl_table table { { group, spos, epos } }


--- @class NormRwCtx : TaskCtx
-- ui
-- real time highlight

------------------------------------------------------------------------------
local cfg = require("compile.config")
local ui = require("compile.ui")
local kit = require("compile.kit")
local constants = require("compile.constants")
local fmt = string.format

local _M = {}

local get_lnum = function(lnum, idx, one_based)
    if one_based then
        return lnum + idx
    end

    return lnum + idx - 1
end

--- @param ctx TaskCtx
--- @param idx integer
--- @param cap CdCapture
local update_dir_stack = function(ctx, idx, cap)
    local parse_info = ctx.parse_info
    assert(parse_info)

    local lnum_0 = get_lnum(parse_info.lnum, idx, false)
    local lnum_1 = get_lnum(parse_info.lnum, idx, true)

    local ext_id = ui.set_dir_hl(ctx, { lnum_0, cap.b - 1 },
        { lnum_0, cap.e - 1 })

    table.insert(ctx.dir_stack_arr, {
        stack = vim.deepcopy(ctx.dir_stack, true),
        limit = ext_id or lnum_1
    })

    if not kit.is_absolute_path(cap.dir) then
        cap.dir = fmt("%s/%s", ctx.dir_stack[#ctx.dir_stack], cap.dir)
    end

    cap.dir = kit.normalize_path_no_env(cap.dir)

    if cap.enter then
        table.insert(ctx.dir_stack, cap.dir)
    elseif ctx.dir_stack[#ctx.dir_stack] == cap.dir then
        -- NOTE: if ctx.dir_stack[#ctx.dir_stack] ~= cap.dir, i actually
        -- can't imagine why this happens, so do nothing in that situation.
        table.remove(ctx.dir_stack)
    end
end

--- @param ctx TaskCtx
--- @param lines string[]
local parse_dirs = function(ctx, lines)
    local dir_matcher = _M.get_cfg_val("directory_matcher", ctx.lcfg)
    if vim.lpeg.type(dir_matcher) ~= "pattern" then return end

    for idx, line in ipairs(lines) do
        local cap = dir_matcher:match(line)
        if cap then
            update_dir_stack(ctx, idx, cap)
        end
    end
end

--- @param info ParseInfo
--- @return boolean
local is_matched = function(info, multiline, idx)
    for i = idx, idx + multiline - 1 do
        if info.matched[i] then
            return true
        end
    end

    return false
end

--- @param info ParseInfo
local set_matched = function(info, multiline, idx)
    for i = idx, idx + multiline - 1 do
        info.matched[i] = true
    end
end

--- @return string | number | nil
local get_value_from_txt_capture = function(cap, matcher, field, is_file)
    if type(matcher[field]) == "function" then
        return matcher[field](cap)
    elseif type(cap[field]) == "table" then
        return is_file and cap[field].c or tonumber(cap[field].c)
    end

    return nil
end

--- @return boolean  -- true: matched(ignore this error)  false: not matched
--- @return string?  -- when first return is `false`, this can not be nil
local parse_transform_file_matchers = function(ctx, file)
        local transform_file_matchers = _M.get_cfg_val("transform_file_matchers", ctx.lcfg)

        if type(transform_file_matchers) ~= "table" then
            return false, file
        end

        for _, matcher in ipairs(transform_file_matchers) do
            if vim.lpeg.type(matcher) == "pattern" then
                local ret = matcher:match(file)

                if type(ret) == "number" then
                    return true, nil
                elseif type(ret) == "string" then
                    return false, ret
                end
            end
        end

    return false, file
end

local new_file_entry = function(ctx, info, idx, file)
    file = kit.normalize_path_no_env(file)

    if kit.is_absolute_path(file) then
        local fe = info.fe_table[file]
        if not fe then
            info.fe_table[file] = { fname = file }
            fe = info.fe_table[file]
        end
        return fe
    end

    local dir_stack = _M.get_dir_stack(ctx, get_lnum(info.lnum, idx, true))
    local dir_path = dir_stack[#dir_stack]

    info.fe_table[dir_path] = info.fe_table[dir_path] or {}
    local fe = info.fe_table[dir_path][file]
    if not fe then
        info.fe_table[dir_path][file] = {
            fname = file,
            dname = dir_path,
        }
        fe = info.fe_table[dir_path][file]
    end
    return fe
end

local set_debug_info = function(ctx, id, lnum)
    if ctx.type ~= constants.CompileType.COMP
        and ctx.type ~= constants.CompileType.NORMRO then
        return
    end

    local debug_enabled = _M.get_cfg_val("debug", ctx.lcfg)
    if not debug_enabled then return end

    ctx.debug = ctx.debug or {}
    ctx.debug[lnum] = id
end

local get_pos_range = function(cap, multiline, text, lnum)
    if multiline == 1 then
        return { lnum,  cap.b - 1 }, { lnum, cap.e - 1 }
    end

    local sl, el, b, e = lnum, lnum, cap.b, cap.e

    local np = string.find(text, '\n')
    while np do
        if cap.b > np then
            sl = sl + 1
            b = b - np
        end
        if cap.e > np then
            el = el + 1
            e = e - np
        end
        np = string.find(text, '\n', np + 1)
    end

    -- 0-based line number, 0-based column number
    return { sl,  b - 1 }, { el, e - 1 }
end

local highlight_error = function(ctx, caps, matcher, text, lnum)
    local multiline = matcher.multiline or 1
    local bt, et

    if caps.file then
        bt, et = get_pos_range(caps.file, multiline, text, lnum)
        ui.set_hl(ctx, constants.get_hl_by_severity(caps.type), bt, et)
    end
    if caps.line then
        bt, et = get_pos_range(caps.line, multiline, text, lnum)
        ui.set_hl(ctx, "CompileLuaLnum", bt, et)
    end
    if caps.col then
        bt, et = get_pos_range(caps.col, multiline, text, lnum)
        ui.set_hl(ctx, "CompileLuaCol", bt, et)
    end
    if caps.line_end then
        bt, et = get_pos_range(caps.line_end, multiline, text, lnum)
        ui.set_hl(ctx, "CompileLuaLnum", bt, et)
    end
    if caps.col_end then
        bt, et = get_pos_range(caps.col_end, multiline, text, lnum)
        ui.set_hl(ctx, "CompileLuaCol", bt, et)
    end

    -- other highlights
    if matcher.highlights then
        for _, key in ipairs(matcher.highlights) do
            if caps[key] then
                bt, et = get_pos_range(caps[key], multiline, text, lnum)
                ui.set_hl(ctx, caps[key].hl, bt, et)
            end
        end
    end

    -- link
    bt, et = get_pos_range(caps.link or caps, multiline, text, lnum)
    return ui.set_link_hl(ctx, bt, et)
end

-- 1-based line number
local get_line_range = function(cap, multiline, text, lnum)
    if multiline == 1 then
        return lnum, lnum
    end

    local sl, el = lnum, lnum

    local np = string.find(text, '\n')
    while np do
        if cap.b > np then
            sl = sl + 1
        end
        if cap.e > np then
            el = el + 1
        end
        np = string.find(text, '\n', np + 1)
    end

    return sl, el
end

local set_msg = function(ctx, loc_id, msg)  -- 1-based index
    ctx.lookup[loc_id] = msg
end

local parse_error = function(ctx, caps, idx, text, matcher_id, matcher)
    local parse_info = ctx.parse_info
    assert(parse_info)

    local file = get_value_from_txt_capture(caps, matcher, "file", true)
    local fe = nil
    if file then
        local ignore
        ignore, file = parse_transform_file_matchers(ctx, file)
        if ignore then return end

        local parse_filename_hook = _M.get_cfg_val("on_parse_filename_hook_fn", ctx.lcfg)
        if type(parse_filename_hook) == "function" then
            file = parse_filename_hook(file)
        end
    else
        fe = parse_info.last_fe
    end

    local msg = {
        fe = fe or new_file_entry(ctx, parse_info, idx, file or "unknown"),
        type = constants.get_valid_severity(caps.type),
        line = get_value_from_txt_capture(caps, matcher, "line"),
        col = get_value_from_txt_capture(caps, matcher, "col"),
        line_end = get_value_from_txt_capture(caps, matcher, "line_end"),
        col_end = get_value_from_txt_capture(caps, matcher, "col_end"),
    }

    local lnum1 = get_lnum(parse_info.lnum, idx, true)
    parse_info.last_fe = msg.fe
    ctx.stat_info[msg.type] = ctx.stat_info[msg.type] + 1
    set_debug_info(ctx, matcher_id, lnum1)

    local link_id = highlight_error(ctx, caps, matcher, text,
        get_lnum(parse_info.lnum, idx, false))

    if link_id then
        set_msg(ctx, link_id, msg)
    else
        local sl, el = get_line_range(caps.link or caps, matcher.multiline or 1,
            text, lnum1)
        for lnum = sl, el do set_msg(ctx, lnum, msg) end
    end
end

--- @return boolean
local skip_mismatched = function(parse_info, idx)
    return not parse_info.eof and type(parse_info.mismatched_index) == "number"
        and idx >= parse_info.mismatched_index
end

--- @param ctx TaskCtx
--- @param lines string[]
local parse_errors = function(ctx, lines)
    local parse_info = ctx.parse_info
    assert(parse_info)

    local matchers = _M.get_cfg_val("matchers", ctx.lcfg)
    local matchers_alist = _M.get_cfg_val("matchers_alist", ctx.lcfg)

    for matcher_idx, matcher_val in ipairs(matchers_alist) do
        local matcher, matcher_id = nil, nil

        if type(matcher_val) == "string" then
            matcher = matchers and matchers[matcher_val]
            local found
            if not matcher then
                found, matcher = pcall(require, "compile.matchers." .. matcher_val)
                if not found then goto skip end
            end
            matcher_id = matcher_val
        elseif type(matcher_val) == "table" then
            matcher = matcher_val
            matcher_id = matcher_idx
        else
            goto skip
        end
        assert(type(matcher) == "table")

        local lines_idx = 1
        local multiline = matcher.multiline or 1
        local rest = multiline - 1

        while lines_idx <= #lines do
            if skip_mismatched(parse_info, lines_idx) then break end

            if is_matched(parse_info, multiline, lines_idx) then
                lines_idx = lines_idx + 1
                goto continue
            end

            local text = lines[lines_idx]
            local caps = matcher.pattern:match(text)
            if not caps then
                lines_idx = lines_idx + 1
                goto continue
            end

            if multiline > 1 then
                if lines_idx + rest <= #lines then
                    text = table.concat(lines, '\n', lines_idx,
                        lines_idx + rest)
                    caps = matcher.pattern2:match(text)
                    if not caps then
                        lines_idx = lines_idx + 1
                        goto continue
                    end
                else
                    if type(parse_info.mismatched_index) ~= "number"
                        or lines_idx < parse_info.mismatched_index then
                        parse_info.mismatched_index = lines_idx
                    end
                    break
                end
            end

            set_matched(parse_info, multiline, lines_idx)
            parse_error(ctx, caps, lines_idx, text, matcher_id, matcher)
            lines_idx = lines_idx + multiline

            ::continue::
        end

        ::skip::
    end
end

--- @param ctx TaskCtx
--- @param lines string[]
local parse_keywords = function(ctx, lines)
    local parse_info = ctx.parse_info
    assert(parse_info)

    local keyword_matchers = _M.get_cfg_val("keyword_matchers", ctx.lcfg)
    if type(keyword_matchers) ~= "table" then
        return
    end

    for _, matcher in ipairs(keyword_matchers) do
        if vim.lpeg.type(matcher) ~= "pattern" then
            goto continue
        end

        for idx, line in ipairs(lines) do
            if skip_mismatched(parse_info, idx) then break end

            local caps = matcher:match(line)
            if not caps then
                goto skip
            end

            local lnum0 = get_lnum(parse_info.lnum, idx, false)
            for _, cap in ipairs(caps) do
                ui.set_hl(ctx, cap.hl, { lnum0, cap.b - 1 },
                    { lnum0, cap.e - 1 }, is_matched(parse_info, 1, idx))
            end

            ::skip::
        end

        ::continue::
    end
end

-------------------------- export apis ---------------------------------------

--- @param key string
--- @param lcfg table?
--- @return any
_M.get_cfg_val = function(key, lcfg)
    if lcfg and lcfg[key] ~= nil then
        return lcfg[key]
    end

    return cfg[key]
end

--- @param ctx TaskCtx
--- @param lnum integer 1-based index
_M.get_msg = function(ctx, lnum)
    if ctx.type == constants.CompileType.NORMRW then
        local ids = ui.get_link_extmark_ids(ctx.bufnr, { lnum - 1, -1 },
            { lnum - 1, 0 })
        if #ids == 0 then return nil end

        return ctx.lookup[ids[1][1]]
    else
        return ctx.lookup[lnum]
    end
end

--- @param ctx TaskCtx
--- @param lnum integer 1-based index
_M.get_dir_stack = function(ctx, lnum)
    if ctx.type == constants.CompileType.NORMRW then
        local dirs = ui.get_dir_extmark_ids(ctx.bufnr, { lnum - 1, 0 })
        if #dirs == 0 then return ctx.dir_stack end

        local dir_id = dirs[1][1]
        for _, s in ipairs(ctx.dir_stack_arr) do
            if s["limit"] == dir_id then return s["stack"] end
        end
    else
        for _, s in ipairs(ctx.dir_stack_arr) do
            if s["limit"] > lnum then return s["stack"] end
        end
    end

    return ctx.dir_stack
end

_M.parse = function(ctx, lines)
    -- 1. parse the directory matcher
    parse_dirs(ctx, lines)
    -- 2. parse all matchers
    --    3. trasnform_file_matchers
    --    4. parse-errors-finename callback
    parse_errors(ctx, lines)
    -- 5. keyword matchers
    parse_keywords(ctx, lines)
end

_M.init_base_ctx = function(ctx)
    local cwd = _M.get_cfg_val("cwd", ctx.lcfg) or vim.fn.getcwd()
    ctx.dir_stack = { kit.normalize_path(cwd) }
    ctx.dir_stack_arr = {}
    ctx.lookup = {}
    ctx.debug = nil
    ctx.stat_info = {
        ret_code = nil,
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
        eof = false,
    }
end

return _M
