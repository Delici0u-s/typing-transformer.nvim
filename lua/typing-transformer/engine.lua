local M = {}
local rules_mod = require("typing-transformer.rules")

local _trigger_chars = {}
local _attached = false

local function collect_trigger_chars(cfg)
  local chars = {}
  local seen = {}

  local function add(list)
    for _, raw in ipairs(list or {}) do
      local before = raw:match('^["\'](.-)%|') or raw:match('^["\'](.+)["\']')
      if before and #before > 0 then
        local last = before:sub(-1)
        if last == "\\" and #before >= 2 then
          last = before:sub(-2, -2)
        end
        if not seen[last] then
          seen[last] = true
          table.insert(chars, last)
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

---Check a single rule against the current buffer state.
---Returns the key sequence string if matched, nil otherwise.
---@param rule table
---@param line string
---@param col number  0-indexed byte offset
---@return string|nil
local function match_rule(rule, line, col)
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

  -- Build key sequence
  local keys = ""

  -- delete before (backspaces)
  keys = keys .. string.rep("<BS>", #before)

  if rule.after ~= rule.res_after then
    -- delete after, then insert both parts
    keys = keys .. string.rep("<Del>", #after)
    keys = keys .. rule.res_before .. rule.res_after
    if #rule.res_after > 0 then
      keys = keys .. string.rep("<Left>", vim.fn.strchars(rule.res_after))
    end
  else
    -- after text stays the same → insert res_before, skip over res_after
    keys = keys .. rule.res_before
    keys = keys .. string.rep("<Right>", vim.fn.strchars(rule.res_after))
  end

  return keys
end

---Try to apply the best-matching rule for a given filetype.
---@param ft string
---@return string|nil
local function try_apply(ft)
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed

  for _, rule in ipairs(rules_mod.for_filetype(ft)) do
    local result = match_rule(rule, line, col)
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

    -- Temporarily inject the typed char so rules can match against it
    local fake_line = line:sub(1, col) .. char .. line:sub(col + 1)
    vim.api.nvim_set_current_line(fake_line)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], col + #char })

    local result = try_apply(vim.bo.filetype)

    -- Restore original line; the returned keys will do the real edit
    vim.api.nvim_set_current_line(line)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], col })

    if result then
      return char .. result
    end
    return char
  end, { expr = true, noremap = true, desc = "typing-transformer: " .. char })
end

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
