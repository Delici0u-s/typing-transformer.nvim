local M = {}
local config_mod = require("typing-transformer.config")

---@class Rule
---@field trigger string   Text that must appear before+at cursor (cursor = | in obsidian notation)
---@field before  string   The part of trigger BEFORE the cursor
---@field after   string   The part of trigger AFTER the cursor  (text already typed ahead)
---@field result  string   Replacement; "|" marks where cursor lands
---@field res_before string  Result text before cursor
---@field res_after  string  Result text after cursor (typed-ahead to skip or replace)

-- Split a pattern on the FIRST unescaped "|"
-- Returns before, after  (after may be empty string)
local function split_cursor(s)
  -- Find a "|" not preceded by "\"
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2 -- skip escaped char
    elseif c == "|" then
      return s:sub(1, i - 1), s:sub(i + 1)
    else
      i = i + 1
    end
  end
  -- No "|" found → cursor is at the end
  return s, ""
end

-- Unescape "\|" and "\\" in a pattern string
local function unescape(s)
  return s:gsub("\\(.)", "%1")
end

---@param raw string
---@return Rule|nil
local function compile(raw)
  local parsed, err = config_mod.parse_rule(raw)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return nil
  end
  if not parsed then return nil end -- comment / blank

  local tb, ta = split_cursor(parsed.trigger)
  local rb, ra = split_cursor(parsed.result)

  return {
    trigger    = parsed.trigger,
    before     = unescape(tb),
    after      = unescape(ta),
    result     = parsed.result,
    res_before = unescape(rb),
    res_after  = unescape(ra),
  }
end

-- compiled_rules["global"] = Rule[]
-- compiled_rules["lua"]    = Rule[]   (filetype overrides)
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

---Return the ordered rule list for a given filetype.
---Filetype-specific rules come FIRST (higher priority), then global.
---@param ft string
---@return Rule[]
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

return M
