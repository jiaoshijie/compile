local constants = require("compile.constants")
local hl = require("compile.matchers").hl
local P = vim.lpeg.P
local R = vim.lpeg.R
local V = vim.lpeg.V
local S = vim.lpeg.S
local CG = vim.lpeg.Cg
local CT = vim.lpeg.Ct
local CP = vim.lpeg.Cp
local LOC = vim.lpeg.locale()

local _M = {}

------------------------- matchers configuration -----------------------------

--- @type table<string, MatcherSpec> user defined matchers
_M.matchers = nil

--- multiline parsers should go first to avoid conflict with single parsers
--- @type string[]
_M.matchers_alist = {
    -- TODO: really do not quite know the order of `2` and `2 opt`.
    -- Maybe need sometime to figure out which one is suitable.
    "python_tracebacks_and_caml", -- 2 opt
    "rustc",  -- 2
    -- "rust_panic", "bash", "gmake", "gnu",  -- 1
}

--- @alias TranPattern vim.lpeg.Pattern
--- This pattern can return number and string when matched
--- if number is returned this error will be ignored
--- if string is returned the filename of this error will be replaced by it
--- @type TranPattern[]
_M.transform_file_matchers = {
    P{ P"/bin/" * (R"az" - #V"sh") ^ 0 * V"sh", sh = "sh" * P(-1) },  -- regex: ^/bin/.*sh$
}

--- @alias CdPattern vim.lpeg.Pattern
--- This pattern should return CdCapture
--- @type CdPattern
_M.directory_matcher = P{
    CT((P(1) - #V"enter") ^ 1 * V"enter" * V"dir"),
    dir = P"'" * CG(CP(), "b") * CG((P(1) - #V"eq") ^ 1, "dir") * CG(CP(), "e") * V"eq",
    enter = CG((P"Entering" + P"Leaving") / { ["Entering"] = true, ["Leaving"] = false }, "enter") * " directory ",
    eq = P"'" * P(-1),
}

--- @alias HlPattern vim.lpeg.Pattern
--- This pattern should return HlCapture
--- @type HlPattern[]
_M.keyword_matchers = {
    P{  -- `configure` output lines.
        CT(S"Cc" * "hecking " * V"cond" * V"info" * V"dot3" * P" " ^ 0 * V"res"),
        info = hl((P(1) - #V"dot3") ^ 1, "CompileLuaHint"),
        cond = ((S"Ff" * "or ") + (S"Ii" * "f ") + (S"Ww" * "hether " * P"to " ^ -1)) ^ -1,
        dot3 = P"...",
        res = (P"(cached)" * P" " ^ 0) ^ -1 * (V"other" + V"no" + V"yes" + P(-1)),
        no = hl(P"no", "CompileLuaError") * P(-1),
        yes = hl(P"yes" * (P" " * P(1) ^ 1) ^ -1, "CompileLuaInfo") * P(-1),
        other = hl((P(1) - #(V"no" + V"yes")) ^ 1, "CompileLuaWarning"),
    },
    P{ -- Command output lines.  Recognize `make[n]:' lines too.
        CT(V"cmd" * V"level" ^ -1 * S" \t" ^ 0 * ":"),
        cmd = hl((LOC.alnum + S"_/.+-") ^ 1, "CompileLuaHint"),
        level = P"[" * hl(LOC.digit ^ 1, "CompileLuaWarning") * P"]",
    },
}

--- NOTE: all below matchers are only used in CompileType.COMP

--- @alias CmdCdPattern vim.lpeg.Pattern
--- This pattern should return CmdCdCapture.
--- It should NOT be used to parse complex path.
--- Only Tilde Expansion is supported.
--- ENV Expansion is NOT supported
--- It does NOT match ` $ characters in double quoted and unquoted path.
--- @type CmdCdPattern
_M.cmd_cd_matcher = P{
    CT(V"spaces" * P"cd" * V"spaces" * V"dir" ^ -1 * V"spaces" * V"end_chs"),
    end_chs = S";&\n",
    spaces = LOC.space ^ 0,
    single = P"'" * (P(1) - P"'") ^ 1 * P"'",
    double = P'"' * ((P"\\" * P(1)) + (P(1) - S'\\"`$')) ^ 1 * P'"',
    except = (S'\'\\"`$' + LOC.space + V"end_chs"),
    no_quote = ((P"\\" * P(1)) + (P(1) - V"except")) ^ 1,
    dir = CG(V"single" + V"double" + V"no_quote", "dir"),
}

----------------------------- callbacks --------------------------------------

--- @type fun(fname: string): string
_M.on_parse_filename_hook_fn = nil

--- NOTE: all below callbacks are only called in CompileType.COMP

--- @type fun(job_id: integer): nil
_M.on_job_started_hook_fn = nil

--- NOTE: deleting lines is valid in this function
--- ctx: internal CompileCtx, this function should not modity this ctx directly
--- lnum(0-based): Line number where lines will be inserted.
--- lines: Newly received lines that will be parsed later.
--- @type fun(ctx: CompileCtx, lnum: integer, lines: string[]) : string[]
_M.on_output_hook_fn = nil

--- NOTE: deleting lines is **NOT** allowed in this function
--- ctx: internal CompileCtx, this function should not modity this ctx directly
--- lnum(0-based): Line number where lines will be inserted.
--- lines: Newly received lines that will be parsed later.
--- @type fun(ctx: CompileCtx, lnum: integer, lines: string[]) : string[]
_M.on_output_parsed_hook_fn = nil

--- must not modify the buffer content
--- only meant to be used for highlighting something
--- ctx: internal CompileCtx, this function should not modity this ctx directly
--- @type fun(ctx: CompileCtx, b_lnum: integer, e_lnum: integer): nil
_M.on_output_inserted_hook_fn = nil

--- when the process has been finished
--- like close the opened window when compilation success
--- or send notification when process exits abnormally
--- @type fun(ret_code): nil
_M.on_job_finished_hook_fn = nil

----------------------------- options ----------------------------------------

--- @type boolean
_M.debug = false

--- @type string
_M.error_msg = "error"

--- @type string? -- absolute path or can be expand to absolute path by vim.fs.normalize
_M.cwd = nil

--- motion action will skip less important messages.
--- The message's type that is lower than this value will be skipped.
--- @type CompileSeverity
_M.skip_threshold = constants.Severity.WARNING

--- highlight the matched line in the source file when select or display it
--- @type integer
--- A value less than or equal to 0 disables this option.
--- integer: unit ms
_M.highlight_on_select = 300

--- @type 0 | 1
_M.compile_output_column_index = 1

--- @type boolean
_M.search_whole_directory_stack = true

--- predefined paths to search to find the source file in error message
--- must be absolute path
--- @type string[]?
_M.search_paths = nil

--- @type boolean
_M.skip_the_same_location = true

--- NOTE: all below options only affect CompileType.COMP

--- @type boolean
_M.clear_env = false

--- @type table? { ["TERM"] = "dumb", ["PAGER"] = "" }
_M.env = nil

--- @type boolean
_M.background = false

--- @type boolean
_M.close_stdin = false

----------------------------- keymaps ----------------------------------------

_M.keymap = {
    [constants.CompileType.COMP] = {  -- seems only compilation buffer needs special keybindings
        ["p"] = "display_error",
        ["<C-n>"] = "display_next_error",
        ["<C-p>"] = "display_prev_error",

        ["<M-n>"] = "next_error",
        ["<M-p>"] = "prev_error",
        ["<M-[>"] = "prev_file",  -- move to next error from a different file
        ["<M-]>"] = "next_file",  -- move to prev error from a different file
        ["<cr>"] = "select_error",

        ["<C-r>"] = "recompile",
        ["<C-c>"] = "kill_compilation", -- first send SIGTERM if failed after timeout, send SIGKILL
        ["I"] = "stdin",
        ["A"] = "stdin_secret",
    },
    [constants.CompileType.NORMRO] = {
        ["p"] = "display_error",
        ["<C-n>"] = "display_next_error",
        ["<C-p>"] = "display_prev_error",

        ["<M-n>"] = "next_error",
        ["<M-p>"] = "prev_error",
        ["<M-[>"] = "prev_file",  -- move to next error from a different file
        ["<M-]>"] = "next_file",  -- move to prev error from a different file
        ["<cr>"] = "select_error",
    },
    [constants.CompileType.NORMRW] = {
        ["<C-n>"] = "display_next_error",
        ["<C-p>"] = "display_prev_error",

        ["<M-n>"] = "next_error",
        ["<M-p>"] = "prev_error",
        ["<M-[>"] = "prev_file",  -- move to next error from a different file
        ["<M-]>"] = "next_file",  -- move to prev error from a different file
        ["<cr>"] = "select_error",
    },
}

return _M
