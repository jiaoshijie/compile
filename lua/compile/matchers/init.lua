--- @class PosCapture link
--- @field b integer
--- @field e integer

--- @class TxtCaptrue : PosCapture file line col
--- @field c string

--- @class HlCapture : PosCapture
--- @field hl string highlight group to use to highlight this keyword

--- @class CdCapture : PosCapture changing directory
--- @field enter boolean true: enter directory, false: leave directory
--- @field dir string absolute path | relative path (will be construct to absolute path according to the current directory stack)

--- 1. If "file", "line" or "col" are nil, that information is not present on the matched line.
---    In that case the filename is assumed to be the same as the previous one,
---    line number and column defaults to 1.
--- 2. If "type" is nil, this match will be considered as an error.
--- 3. If "link" is nil, the whole match position will be used as the hyperlink.
--- 4. Other Captures can be HlCaptures which will be used by `highlights`, or any type
---    which will be used by `*Handles`.
--- @class Captures : PosCapture
--- @field file TxtCaptrue?
--- @field line TxtCaptrue?
--- @field col TxtCaptrue?
--- @field line_end TxtCaptrue?
--- @field col_end TxtCaptrue?
--- @field link PosCapture?
--- @field type CompileSeverity?
--- @field _ HlCapture?  -- other fields should be the type of HlCapture

--- returns `filename`, which can be relative or absolute.
--- @alias FileHandle fun(captrues: Captures): string

--- @alias LineColHandle fun(captrues: Captures): integer

--- 1. The `pattern` should return `Captures` data structure that is defined above when success.
---    When `multiple` is greater than 1, the `pattern2` should return `Captures` when success and
---    `pattern` can simply return a number to indicate that line is the potential 'error'.
---    In that case `pattern2` is also free to return nil which indicates this is a false positive match.
--- @class MatcherSpec
--- @field multiline integer
--- @field pattern vim.lpeg.Pattern
--- @field pattern2 vim.lpeg.Pattern?
--- @field file FileHandle?
--- @field line LineColHandle?
--- @field col LineColHandle?
--- @field line_end LineColHandle?
--- @field col_end LineColHandle?
--- @field highlights string[]?  a list of keys that point to HlCaptures

------------------------------------------------------------------------------
local _M = {}

_M.pos = function(name)
    return vim.lpeg.Cg(vim.lpeg.Cp(), name)
end

_M.wrapper = function(pat, name)
    return vim.lpeg.Cg(vim.lpeg.Ct(_M.pos("b") * vim.lpeg.Cg(pat, "c") * _M.pos("e")), name)
end

_M.hl = function(pat, hl)
    return vim.lpeg.Ct(_M.pos("b") * pat * _M.pos("e") * vim.lpeg.Cg(vim.lpeg.Cc(hl), "hl"))
end

_M.hl_wrapper = function(pat, hl, name)
    return vim.lpeg.Cg(_M.hl(pat, hl), name)
end


_M.trace = function(name)
    return vim.lpeg.Cmt("", function(subject, pos, _)
        print(
            name,
            "pos =", pos,
            "remaining =", string.format("%q", subject:sub(pos))
        )
        return true
    end)
end

return _M
