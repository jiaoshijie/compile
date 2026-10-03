local kit = require("compile.kit")
local constants = require("compile.constants")
local matchers_lib = require("compile.matchers")
local pos = matchers_lib.pos
local wrapper = matchers_lib.wrapper
local P = vim.lpeg.P
local S = vim.lpeg.S
local CG = vim.lpeg.Cg
local CT = vim.lpeg.Ct
local LOC = vim.lpeg.locale()
local fmt = string.format

local is_heading = false

local _d = LOC.digit ^ 1
local _file = wrapper((P(1) - #P"\0") ^ 1, "file")
local _line = wrapper(_d, "line")
local _col = wrapper(_d, "col")
local ansi_pattern = P"\27[3" * (S"013" / tonumber) * P"m"

local _search = (P(1) - #ansi_pattern) ^ 0 * ansi_pattern
local _symbols = { [0] = '-', [1] = '=', [3] = ':' }

local null = {
    multiline = 1,
    pattern = CT(pos("b") * _file * P"\0" * _line * P"\0" * (_col * P"\0") ^ -1 * pos("e")
        * (P(1) - #ansi_pattern) ^ 0 * CG(ansi_pattern, "type")),
}

local end_ansi_pattern = P"\27[m" * P(-1)
local _heading_file = wrapper((P(1) - #end_ansi_pattern) ^ 1, "file")
local heading_file = {
    multiline = 1,
    pattern = CT(P"\27[32m" * _heading_file * end_ansi_pattern) / function(t)
        t.file.b = t.file.b - 5
        t.file.e = t.file.e - 5
        t.b = t.file.b
        t.e = t.file.e
        t.type = constants.Severity.INFO
        return t
    end,
}

local heading_pos = {
    multiline = 1,
    pattern = CT(pos("b") * _line * P"\0" * (_col * P"\0") ^ -1 * pos("e")
        * (P(1) - #ansi_pattern) ^ 0 * CG(ansi_pattern, "type")) / function(t)
            t.match = {
                b = t.line.b,
                e = t.line.e,
                hl = constants.get_hl_by_severity(t.type),
            }
            return t
        end,
    file = false,
    highlights = { "match" }
}

local _heading = P"--heading"
local _search_heading = (P(1) - #_heading) ^ 0 * _heading

------------------------------------------------------------------------------

local hl_subm = function(ctx, lnum, line)
    local p, c = 0, 1

    while true do
        local b1, e1 = string.find(line, '\27[33m', p + 1, true)
        if b1 == nil then break end
        local b2, e2 = string.find(line, '\27[m', e1 + 1, true)
        if b2 == nil then break end  -- Must be impossible

        require("compile.ui").set_hl(ctx, "CompileLuaGrepMatch", { lnum, b1 - c }, { lnum, b2 - c - 5 }, false)

        --- @diagnostic disable-next-line: cast-local-type
        p = e2
        c = c + 8
    end
end

local output_parsed = function(ctx, lnum, lines)
    lnum = lnum - 1
    local idx = 1

    while idx <= #lines do
        local line = lines[idx]

        local symbol = _symbols[_search:match(line)]
        if symbol then
            local limit = 2
            if symbol == ":" then
                hl_subm(ctx, lnum + idx, line)
                limit = 3
            end
            -- NOTE: %z to match NUL character
            lines[idx] = line:gsub("\27%[[013]-m", ""):gsub("%z", symbol, limit)
        else
            lines[idx] = line:gsub("\27%[[23]-m", "")
            goto continue
        end

        ::continue::
        idx = idx + 1
    end

    return lines
end

------------------------------------------------------------------------------

local _M = {}

local ggrep_heading = {
    hl_filename = "2",
    matchers_alist = { heading_file, heading_pos },
}

local ggrep_vimgrep = {
    hl_filename = "",
    matchers_alist = { null },
}

local lcfg = {
    -- matchers
    matchers_alist = nil,
    directory_matcher = false,
    keyword_matchers = {},
    cmd_cd_matcher = false,
    -- callbacks
    on_output_parsed_hook_fn = output_parsed,
    -- options
    debug = false,
    error_msg = "match",
    search_whole_directory_stack = false,
    clear_env = true,
    env = nil,
    close_stdin = true,
    compile_lines_limit = 20000,
}

_M.create_user_command = function(cmd_name)
    local ok, reason = pcall(vim.api.nvim_create_user_command, cmd_name, function(args)
        local cmd = fmt("git grep -zHIn --column --color=always %s", args.args)
        is_heading = _search_heading:match(args.args) ~= nil
        local ggrep = is_heading and ggrep_heading or ggrep_vimgrep

        lcfg.debug = args.bang
        lcfg.matchers_alist = ggrep.matchers_alist
        lcfg.env = {
            -- https://git-scm.com/docs/git-config#Documentation/git-config.txt-colorgrepslot
            GIT_CONFIG_COUNT=9,
            GIT_CONFIG_KEY_0="color.grep.context",
            GIT_CONFIG_VALUE_0="0",
            GIT_CONFIG_KEY_1="color.grep.filename",
            GIT_CONFIG_VALUE_1=ggrep.hl_filename,
            GIT_CONFIG_KEY_2="color.grep.function",
            GIT_CONFIG_VALUE_2="1",
            GIT_CONFIG_KEY_3="color.grep.lineNumber",
            GIT_CONFIG_VALUE_3="",
            GIT_CONFIG_KEY_4="color.grep.column",
            GIT_CONFIG_VALUE_4="",
            GIT_CONFIG_KEY_5="color.grep.match",  -- matchContext and matchSelected
            GIT_CONFIG_VALUE_5="3",
            GIT_CONFIG_KEY_6="color.grep.selected",
            GIT_CONFIG_VALUE_6="",
            GIT_CONFIG_KEY_7="color.grep.separator",
            GIT_CONFIG_VALUE_7="",
            GIT_CONFIG_KEY_8="core.quotePath",
            GIT_CONFIG_VALUE_8="false",
        }
        require("compile").compile(cmd, "[compilation.git_grep]", lcfg)
    end, { force = true, nargs = "+", complete = "file", bang = true })

    if not ok and type(reason) == "string" then
        kit.echo_info_msg(reason)
    end
end

return _M
