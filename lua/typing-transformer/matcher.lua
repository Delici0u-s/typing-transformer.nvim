---Matcher module: owns all rule-matching logic.
---Called by engine.lua with a compiled Rule and the current line state.
---Returns a key sequence string on match, nil otherwise.

local M = {}

-- ── Literal matching ──────────────────────────────────────────────────────────

---@param rule LiteralRule
---@param line string
---@param col  number  0-indexed byte offset
---@return string|nil
function M.literal_match(rule, line, col)
  local before = rule.before
  local after  = rule.after

  if #before > 0 then
    local start_col = col - #before
    if start_col < 0 then return nil end
    if line:sub(start_col + 1, col) ~= before then return nil end
  end

  if #after > 0 then
    if line:sub(col + 1, col + #after) ~= after then return nil end
  end

  return M.build_keys(
    #before, #after,
    rule.res_before, rule.res_after,
    rule.after
  )
end

-- ── Regex matching ────────────────────────────────────────────────────────────

---Run vim.fn.matchlist and return captures (indices 2..n, index 1 is full match).
---Returns nil if no match.
---@param pattern string  vim regex pattern
---@param str     string
---@return string[]|nil
local function matchlist_captures(pattern, str)
  local results = vim.fn.matchlist(str, pattern)
  if not results or results[1] == "" and #results == 1 then
    return nil
  end
  -- results[1] = full match, results[2]+ = captures
  -- Return empty-string captures as "" (consistent with no-capture rules)
  local caps = {}
  for i = 2, #results do
    caps[i - 1] = results[i]
  end
  return caps
end

---@param rule RegexRule
---@param line string
---@param col  number  0-indexed byte offset
---@return string|nil
function M.regex_match(rule, line, col)
  local text_before = line:sub(1, col)   -- text left of cursor
  local text_after  = line:sub(col + 1)  -- text right of cursor

  -- Match before-pattern (anchored $) against text left of cursor
  local caps_before = {}
  if rule.pat_before ~= "$" then  -- non-empty before pattern
    local cb = matchlist_captures(rule.pat_before, text_before)
    if not cb then return nil end
    caps_before = cb
  end

  -- Match after-pattern (anchored ^) against text right of cursor
  local caps_after = {}
  if rule.pat_after ~= "^" then  -- non-empty after pattern
    local ca = matchlist_captures(rule.pat_after, text_after)
    if not ca then return nil end
    caps_after = ca
  end

  -- Merge captures: before first, then after
  local captures = {}
  for _, v in ipairs(caps_before) do table.insert(captures, v) end
  for _, v in ipairs(caps_after)  do table.insert(captures, v) end

  -- Substitute captures into result templates
  local rules_mod = require("typing-transformer.rules")
  local res_before = rules_mod.apply_captures(rule.res_before, captures)
  local res_after  = rules_mod.apply_captures(rule.res_after,  captures)

  -- Measure how many bytes were consumed by each pattern match
  -- so we know how many BS / Del keys to emit.
  local matched_before = vim.fn.matchstr(text_before, rule.pat_before)
  local matched_after  = vim.fn.matchstr(text_after,  rule.pat_after)

  return M.build_keys(
    #matched_before, #matched_after,
    res_before, res_after,
    matched_after  -- original "after" text for comparison
  )
end

-- ── Shared key builder ────────────────────────────────────────────────────────

---Build the insert-mode key sequence that replaces matched text with result.
---@param n_before   number  bytes to delete left of cursor  (BS)
---@param n_after    number  bytes to delete right of cursor (Del)
---@param res_before string  text to insert left of final cursor position
---@param res_after  string  text to insert/skip right of final cursor position
---@param orig_after string  the original matched text right of cursor
---@return string
function M.build_keys(n_before, n_after, res_before, res_after, orig_after)
  local keys = ""

  keys = keys .. string.rep("<BS>", n_before)

  if orig_after ~= res_after then
    -- Replace the after text entirely
    keys = keys .. string.rep("<Del>", n_after)
    keys = keys .. res_before .. res_after
    if #res_after > 0 then
      keys = keys .. string.rep("<Left>", vim.fn.strchars(res_after))
    end
  else
    -- After text unchanged → insert res_before, skip over res_after
    keys = keys .. res_before
    keys = keys .. string.rep("<Right>", vim.fn.strchars(res_after))
  end

  return keys
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

---Main entry point called by engine.lua.
---@param rule  table   LiteralRule or RegexRule
---@param line  string
---@param col   number  0-indexed
---@return string|nil
function M.match(rule, line, col)
  if rule.is_regex then
    return M.regex_match(rule, line, col)
  else
    return M.literal_match(rule, line, col)
  end
end

return M
