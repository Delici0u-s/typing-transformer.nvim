local M = {}
local rules_mod  = require("typing-transformer.rules")
local matcher    = require("typing-transformer.matcher")

local _trigger_chars = {}
local _attached = false

-- ── Trigger char collection ───────────────────────────────────────────────────

-- Vim regex metacharacters — these can't be used as reliable trigger chars.
local METACHARS = {
  ["*"] = true, ["."] = true, ["~"] = true, ["["] = true, ["]"] = true,
  ["^"] = true, ["$"] = true, ["\\"] = true, ["/"] = true,
  ["{"] = true, ["}"] = true, ["%"] = true,
}

---Extract the last reliable literal character from the before-side of a trigger.
---For literal rules: last char of the before string.
---For regex rules:   scan backwards through the raw pattern before "|" for the
---                   last non-metacharacter.
---Returns nil if no reliable char can be found (engine will use fallback set).
---@param raw string  the raw rule string as the user wrote it
---@return string|nil
local function extract_trigger_char(raw)
  local is_regex = raw:match("^%s*r[\"']") ~= nil

  -- Get the trigger side (before "->")
  local trigger_raw = raw:match('^%s*(r?["\'].+["\'])%s*%->')
  if not trigger_raw then return nil end

  -- Strip r prefix and quotes
  local inner = trigger_raw:match("^r?[\"'](.+)[\"']$")
  if not inner then return nil end

  -- Get the before-cursor part
  local before = inner:match("^(.-)%|") or inner

  if not is_regex then
    -- Literal: last char (accounting for \| escape)
    if #before == 0 then return nil end
    local last = before:sub(-1)
    if last == "|" and #before >= 2 and before:sub(-2, -2) == "\\" then
      return "|"
    end
    return last
  else
    -- Regex: scan backwards for last non-metachar, not part of an escape seq
    local i = #before
    while i >= 1 do
      local c = before:sub(i, i)
      if c == "\\" then
        -- This char is an escape leader — skip both
        i = i - 2
      elseif not METACHARS[c] then
        -- Plain literal character — safe to use as trigger
        return c
      else
        i = i - 1
      end
    end
    return nil  -- entire pattern is metacharacters
  end
end

-- Characters we register as fallbacks for regex rules whose trigger char
-- cannot be determined statically. Space is the most common "completion" key.
local REGEX_FALLBACK_CHARS = { " ", ")", "]", "}", '"', "'", ">", ";" }

local function collect_trigger_chars(cfg)
  local chars = {}
  local seen = {}

  local function add(list)
    for _, raw in ipairs(list or {}) do
      local c = extract_trigger_char(raw)
      if c then
        if not seen[c] then
          seen[c] = true
          table.insert(chars, c)
        end
      else
        -- Regex rule with no deterministic trigger char → register fallbacks
        for _, fc in ipairs(REGEX_FALLBACK_CHARS) do
          if not seen[fc] then
            seen[fc] = true
            table.insert(chars, fc)
          end
        end
      end
    end
  end

  add(cfg.global)
  for _, list in pairs(cfg.filetype or {}) do
    add(list)
  end

  return chars
end

-- ── Match + key dispatch ──────────────────────────────────────────────────────

---@param ft   string
---@param line string  fake line with typed char already at col
---@param col  number  0-indexed, after the typed char
---@return string|nil
local function try_apply(ft, line, col)
  for _, rule in ipairs(rules_mod.for_filetype(ft)) do
    local result = matcher.match(rule, line, col)
    if result then
      return result
    end
  end
  return nil
end

local function map_char(char)
  vim.keymap.set("i", char, function()
    local col  = vim.api.nvim_win_get_cursor(0)[2]
    local line = vim.api.nvim_get_current_line()

    local fake_line = line:sub(1, col) .. char .. line:sub(col + 1)
    local fake_col  = col + #char

    local result = try_apply(vim.bo.filetype, fake_line, fake_col)

    if result then
      return char .. result
    end
    return char
  end, { expr = true, noremap = true, desc = "typing-transformer: " .. char })
end

-- ── Public API ────────────────────────────────────────────────────────────────

M.attach = function()
  if _attached then return end
  _attached = true

  local cfg = require("typing-transformer.config").get()
  _trigger_chars = collect_trigger_chars(cfg)

  for _, c in ipairs(_trigger_chars) do
    map_char(c)
  end
end

M.reload = function()
  for _, c in ipairs(_trigger_chars) do
    pcall(vim.keymap.del, "i", c)
  end
  _attached = false
  local cfg = require("typing-transformer.config").get()
  require("typing-transformer.rules").build(cfg)
  _trigger_chars = collect_trigger_chars(cfg)
  M.attach()
end

return M
