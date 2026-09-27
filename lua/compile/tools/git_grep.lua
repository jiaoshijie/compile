local matchers_lib = require("compile.matchers")
local pos = matchers_lib.pos
local wrapper = matchers_lib.wrapper
local fmt = string.format
local P = vim.lpeg.P
local S = vim.lpeg.S
local CG = vim.lpeg.Cg
local CT = vim.lpeg.Ct
local LOC = vim.lpeg.locale()

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
        local limit = 2

        if not symbol then goto continue end

        if symbol == ":" then
            hl_subm(ctx, lnum + idx, line)
            limit = 3
        end
        -- NOTE: %z to match NUL character
        lines[idx] = line:gsub("\27%[[013]-m", ""):gsub("%z", symbol, limit)

        ::continue::
        idx = idx + 1
    end

    return lines
end

------------------------------------------------------------------------------

local _M = {}

_M.setup = function()
    vim.api.nvim_create_user_command("GGrep", function(args)
        local cmd = fmt("git grep -zHIn --column --color=always %s", args.args)

        require("compile").compile(cmd, "[compilation.git_grep]", {
            -- matchers
            matchers_alist = { null },
            directory_matcher = false,
            keyword_matchers = {},
            cmd_cd_matcher = false,
            -- callbacks
            on_output_parsed_hook_fn = output_parsed,
            -- options
            debug = args.bang,
            error_msg = "match",
            search_whole_directory_stack = false,
            clear_env = true,
            env = {
                -- https://git-scm.com/docs/git-config#Documentation/git-config.txt-colorgrepslot
                GIT_CONFIG_COUNT=9,
                GIT_CONFIG_KEY_0="color.grep.context",
                GIT_CONFIG_VALUE_0="0",
                GIT_CONFIG_KEY_1="color.grep.filename",
                GIT_CONFIG_VALUE_1="",
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
            },
            close_stdin = true,
        })
    end, { force = true, nargs = "+", complete = "file", bang = true })
end

return _M
