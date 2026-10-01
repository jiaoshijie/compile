local kit = require("compile.kit")
local constants = require("compile.constants")
local matchers_lib = require("compile.matchers")
local pos = matchers_lib.pos
local wrapper = matchers_lib.wrapper
local fmt = string.format
local P = vim.lpeg.P
local C = vim.lpeg.C
local CC = vim.lpeg.Cc
local CG = vim.lpeg.Cg
local CT = vim.lpeg.Ct
local LOC = vim.lpeg.locale()

local _f = (P(1) - P"\0") ^ 1
local _l = LOC.digit ^ 1
local _file = wrapper(_f, "file")
local _line = wrapper(_l, "line")
local match = {
    multiline = 1,
    pattern = CT(pos("b") * _file * P"\0" * _line * ":" * pos("e")),
}
local context = {
    multiline = 1,
    pattern = CT(pos("b") * _file * P"\0" * _line * "-" * pos("e") * CG(CC(constants.Severity.HINT), "type"))
}
local _char = _f * P"\0" * _l * C(P":" + P"-")

------------------------------------------------------------------------------

local hl_subm = function(ctx, lnum, line)
    local p, c = 0, 1

    while true do
        local b1, e1 = string.find(line, '\27[0m', p + 1, true)
        if b1 == nil then break end
        local b2, e2 = string.find(line, '\27[m', e1 + 1, true)
        if b2 == nil then break end  -- Must be impossible

        require("compile.ui").set_hl(ctx, "CompileLuaGrepMatch", { lnum, b1 - c }, { lnum, b2 - c - 4 }, false)

        --- @diagnostic disable-next-line: cast-local-type
        p = e2
        c = c + 7
    end
end

local output_parsed = function(ctx, lnum, lines)
    lnum = lnum - 1
    local idx = 1

    while idx <= #lines do
        local line = lines[idx]
        local char = _char:match(line)
        if not char then goto continue end

        hl_subm(ctx, lnum + idx, line)
        -- NOTE: %z to match NUL character
        lines[idx] = line:gsub("\27%[0-m", ""):gsub("%z", char, 1)

        ::continue::
        idx = idx + 1
    end

    return lines
end

------------------------------------------------------------------------------

local _M = {}

_M.create_user_command = function(cmd_name)
    local ok, reason = pcall(vim.api.nvim_create_user_command, cmd_name, function(args)
        local cmd = fmt("grep -ZHInr --color=always --exclude-dir=.git %s", args.args)

        require("compile").compile(cmd, "[compilation.grep]", {
            -- matchers
            matchers_alist = { match, context },
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
            env = { GREP_COLORS="ms=0:mc=:sl=:cx=:fn=:ln=:bn=:se=:ne" },
            close_stdin = true,
            compile_lines_limit = 20000,
        })
    end, { force = true, nargs = "+", complete = "file", bang = true })

    if not ok and type(reason) == "string" then
        kit.echo_info_msg(reason)
    end
end

return _M
