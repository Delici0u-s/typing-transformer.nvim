local M = {}
local config_mod = require("typing-transformer.config")

---@class LiteralRule
---@field is_regex  false
---@field before    string   literal text left of cursor
---@field after     string   literal text right of cursor
---@field res_before string
---@field res_after  string

---@class RegexRule
---@field is_regex     true
---@field pat_before   string   vim-regex pattern, will be anchored at end ($)
---@field pat_after    string   vim-regex pattern, will be anchored at start (^)
---@field res_before   string   result template, \1..\n substituted from captures
---@field res_after    string   result template

-- ── Shared helpers ────────────────────────────────────────────────────────────

---Split a string on the first unescaped "|".
---Returns before, after.  after may be "".
---@param s string
---@return string, string
local function split_cursor(s)
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == "|" then
      return s:sub(1, i - 1), s:sub(i + 1)
    else
      i = i + 1
    end
  end
  return s, ""
end

---Unescape \| and \\ in a literal string.
local function unescape(s)
  return s:gsub("\\(.)", "%1")
end

-- ── Regex helpers ─────────────────────────────────────────────────────────────

---Convert a POSIX-style regex (bare parens) to Vim regex (\(...\)).
---Also converts \d \w \s \D \W \S which Vim supports natively.
---@param s string
---@return string
local function posix_to_vim(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      -- pass escape sequences through unchanged (\d, \w, \1, etc.)
      out[#out + 1] = s:sub(i, i + 1)
      i = i + 2
    elseif c == "(" then
      out[#out + 1] = "\\("
      i = i + 1
    elseif c == ")" then
      out[#out + 1] = "\\)"
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

---Apply capture substitution to a result template.
---\1..\9 are replaced with captures[1]..captures[9].
---@param template string
---@param captures string[]
---@return string
local function apply_captures(template, captures)
  return (template:gsub("\\(%d+)", function(n)
    return captures[tonumber(n)] or ""
  end))
end

-- ── Compilers ─────────────────────────────────────────────────────────────────

---Compile a literal rule.
---@param parsed table  { is_regex=false, trigger, result }
---@return LiteralRule|nil
local function compile_literal(parsed)
  local tb, ta = split_cursor(parsed.trigger)
  local rb, ra = split_cursor(parsed.result)
  return {
    is_regex   = false,
    before     = unescape(tb),
    after      = unescape(ta),
    res_before = unescape(rb),
    res_after  = unescape(ra),
  }
end

---Compile a regex rule.
---@param parsed table  { is_regex=true, trigger, result }
---@return RegexRule|nil
local function compile_regex(parsed)
  local tb, ta = split_cursor(parsed.trigger)
  local rb, ra = split_cursor(parsed.result)

  local vim_before = posix_to_vim(tb) .. "$"  -- must end at cursor
  local vim_after  = "^" .. posix_to_vim(ta)  -- must start at cursor

  -- Pre-compile patterns to catch errors at setup time, not at keypress time
  local ok_b, err_b = pcall(vim.regex, vim_before)
  if not ok_b then
    vim.notify(("typing-transformer: invalid regex in trigger (before |): %s — %s"):format(tb, err_b), vim.log.levels.WARN)
    return nil
  end

  local ok_a, err_a = pcall(vim.regex, vim_after)
  if not ok_a then
    vim.notify(("typing-transformer: invalid regex in trigger (after |): %s — %s"):format(ta, err_a), vim.log.levels.WARN)
    return nil
  end

  return {
    is_regex   = true,
    pat_before = vim_before,
    pat_after  = vim_after,
    -- result sides are plain templates — no unescape, \1 etc. must survive
    res_before = rb,
    res_after  = ra,
  }
end

---@param raw string
---@return LiteralRule|RegexRule|nil
local function compile(raw)
  local parsed, err = config_mod.parse_rule(raw)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return nil
  end
  if not parsed then return nil end

  if parsed.is_regex then
    return compile_regex(parsed)
  else
    return compile_literal(parsed)
  end
end

-- ── Rule store ────────────────────────────────────────────────────────────────

local compiled_rules = {}

M.build = function(cfg)
  compiled_rules = {}
  compiled_rules["global"] = {}

  for _, raw in ipairs(cfg.global or {}) do
    local r = compile(raw)
    if r then table.insert(compiled_rules["global"], r) end
  end

  for ft, list in pairs(cfg.filetype or {}) do
    compiled_rules[ft] = {}
    for _, raw in ipairs(list) do
      local r = compile(raw)
      if r then table.insert(compiled_rules[ft], r) end
    end
  end
end

---Return ordered rule list for a filetype.
---Filetype-specific rules come before global.
---@param ft string
---@return table[]
M.for_filetype = function(ft)
  local out = {}
  for _, r in ipairs(compiled_rules[ft] or {}) do
    table.insert(out, r)
  end
  for _, r in ipairs(compiled_rules["global"] or {}) do
    table.insert(out, r)
  end
  return out
end

-- expose for engine
M.apply_captures = apply_captures

return M
