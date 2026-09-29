local kit = require("compile.kit")
local constants = require("compile.constants")
local matchers_lib = require("compile.matchers")
local pos = matchers_lib.pos
local wrapper = matchers_lib.wrapper
local P = vim.lpeg.P
local C = vim.lpeg.C
local CC = vim.lpeg.Cc
local CG = vim.lpeg.Cg
local CT = vim.lpeg.Ct
local LOC = vim.lpeg.locale()
local fmt = string.format

local is_vimgrep = false

local _rg_path = "\27[30m"
local _rg_match = "\27[31m"
local _rg_highlight = "\27[32m"

local _l = LOC.digit ^ 1
local _line = wrapper(_l, "line")
local _col = wrapper(_l, "col")
local _f = (P(1) - P"\0") ^ 1
local _file = wrapper(_f, "file")
local _hint = CG(CC(constants.Severity.HINT), "type")

local only_file = {
    multiline = 1,
    pattern = CT(P(_rg_path) * wrapper(P(1) ^ 1, "file") * P(-1)) / function(t)
        t.file.b = t.file.b - 5
        t.file.e = t.file.e - 5
        t.b = t.file.b
        t.e = t.file.e
        t.type = constants.Severity.INFO
        return t
    end,
}
local only_pos = {
    multiline = 1,
    pattern = CT(pos("b") * _line * P":" * (_col * P":") ^ -1 * pos("e")) / function(t)
        t.match = {
            b = t.line.b,
            e = t.line.e,
            hl = "CompileLuaError",
        }
        return t
    end,
    file = false,
    highlights = { "match" }
}
local only_pos_content = {
    multiline = 1,
    pattern = CT(pos("b") * _line * P"-" * pos("e") * _hint) / function(t)
        t.match = {
            b = t.line.b,
            e = t.line.e,
            hl = "CompileLuaHint",
        }
        return t
    end,
    file = false,
    highlights = { "match" }
}

local match = {
    multiline = 1,
    pattern = CT(pos("b") * _file * P"\0" * _line * ":" * (_col * P":") ^ -1 * pos("e")),
}
local context = {
    multiline = 1,
    pattern = CT(pos("b") * _file * P"\0" * _line * "-" * pos("e") * _hint)
}
local _char = _f * P"\0" * _l * C(P":" + P"-")

local _vimgrep = P"--vimgrep" + P"--no-heading"
local _search_vimgrep = (P(1) - #_vimgrep) ^ 0 * _vimgrep

------------------------------------------------------------------------------

local output = function(_, _, lines)
    return vim.tbl_map(function(line)
        return line:gsub("\27%[0-m", "")
    end, lines)
end

local hl_subm = function(ctx, lnum, line)
    local p, c = 0, 1

    local b0, e0 = string.find(line, _rg_highlight, p, true)
    if b0 == nil then return end

    --- @diagnostic disable-next-line: cast-local-type
    p = e0
    c = c + 5

    while true do
        local b1, e1 = string.find(line, _rg_match, p + 1, true)
        if b1 == nil then break end
        local b2, e2 = string.find(line, _rg_highlight, e1 + 1, true)
        if b2 == nil then break end  -- Must be impossible

        require("compile.ui").set_hl(ctx, "CompileLuaGrepMatch", { lnum, b1 - c }, { lnum, b2 - c - 5 }, false)

        --- @diagnostic disable-next-line: cast-local-type
        p = e2
        c = c + 10
    end
end

local output_parsed = function(ctx, lnum, lines)
    lnum = lnum - 1
    local idx = 1

    while idx <= #lines do
        local line = lines[idx]

        hl_subm(ctx, lnum + idx, line)

        if is_vimgrep then
            local char = _char:match(line)
            if not char then goto continue end
            -- NOTE: %z to match NUL character
            lines[idx] = line:gsub("\27%[[123]-m", ""):gsub("%z", char, 1)
        else
            lines[idx] = line:gsub("\27%[[0123]-m", "")
        end

        ::continue::
        idx = idx + 1
    end

    return lines
end

------------------------------------------------------------------------------

local _M = {}

local script_dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
local cfg_path = fmt("%s%s", script_dir, ".res/ripgreprc")

local rg_heading = {
    args = "--colors 'path:fg:black'",
    matchers_alist = { only_file, only_pos, only_pos_content },
}

local rg_vimgrep = {
    args = "--null",
    matchers_alist = { match, context },
}

_M.create_user_command = function(cmd_name)
    local major, _, _ = kit.get_cmd_version('rg', '--version')
    if major < 15 then
        kit.echo_info_msg("rg version is less than 15.0.0, then `Rg` will not enabled")
        return
    end

    local ok, reason = pcall(vim.api.nvim_create_user_command, cmd_name, function(args)
        is_vimgrep = _search_vimgrep:match(args.args) ~= nil
        local rg = is_vimgrep and rg_vimgrep or rg_heading

        local cmd = fmt("rg %s %s", rg.args, args.args)

        require("compile").compile(cmd, "[compilation.ripgrep]", {
            -- matchers
            matchers_alist = rg.matchers_alist,
            directory_matcher = false,
            keyword_matchers = {},
            cmd_cd_matcher = false,
            -- callbacks
            on_output_hook_fn = output,
            on_output_parsed_hook_fn = output_parsed,
            -- options
            debug = args.bang,
            error_msg = "match",
            search_whole_directory_stack = false,
            clear_env = true,
            env = { RIPGREP_CONFIG_PATH=cfg_path },
            close_stdin = true,
        })
    end, { force = true, nargs = "+", complete = "file", bang = true })

    if not ok and type(reason) == "string" then
        kit.echo_info_msg(reason)
    end
end

return _M
