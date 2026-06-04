local M = {}
local rules_mod = require("typing-transformer.rules")

-- Characters that can be the LAST character of a trigger's "before" part.
-- We only intercept those keys in insert mode.
local _trigger_chars = {}
local _attached = false

local function collect_trigger_chars(cfg)
  local chars = {}
  local seen = {}

  local function add(list)
    for _, raw in ipairs(list or {}) do
      -- The trigger character is whatever the user just typed —
      -- the last character of the "before" side of the rule.
      -- We find it by scanning for the last char before "|"
      local before = raw:match('^["\'](.-)%|') or raw:match('^["\'](.+)["\']')
      if before and #before > 0 then
        local last = before:sub(-1)
        -- Handle escaped chars: if last is "\" take the one before
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

---Try to apply the best-matching rule for a given filetype.
---Returns the keys to execute (as an expr-map string), or nil if no match.
---@param ft string
---@return string|nil
local function try_apply(ft)
  local line   = vim.api.nvim_get_current_line()
  local col    = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed byte offset

  local rs = rules_mod.for_filetype(ft)

  for _, rule in ipairs(rs) do
    local before = rule.before
    local after  = rule.after

    -- Check that 'before' matches the text immediately left of cursor
    if #before > 0 then
      local start_col = col - #before
      if start_col < 0 then goto continue end
      if line:sub(start_col + 1, col) ~= before then goto continue end
    end

    -- Check that 'after' matches the text immediately right of cursor
    if #after > 0 then
      if line:sub(col + 1, col + #after) ~= after then goto continue end
    end

    -- Match! Build the key sequence.
    -- Steps:
    --   1. Delete 'before' chars to the left
    --   2. Delete 'after' chars to the right
    --   3. Insert res_before
    --   4. Move right over res_after (it already exists; don't re-type)
    --      — but if res_after differs from rule.after, replace it.

    local keys = ""

    -- delete before (backspaces)
    keys = keys .. string.rep("<BS>", #before)

    -- delete after (Del keys)  — only if different from res_after
    if rule.after ~= rule.res_after then
      keys = keys .. string.rep("<Del>", #after)
      -- insert res_before + res_after
      keys = keys .. rule.res_before .. rule.res_after
      -- move cursor back to sit after res_before
      if #rule.res_after > 0 then
        keys = keys .. string.rep("<Left>", vim.fn.strchars(rule.res_after))
      end
    else
      -- after text stays the same → just insert res_before, skip over res_after
      keys = keys .. rule.res_before
      keys = keys .. string.rep("<Right>", vim.fn.strchars(rule.res_after))
    end

    return keys

    ::continue::
  end

  return nil
end

---Map a single character in insert mode as an expr mapping.
local function map_char(char)
  -- We need a unique map name; use a printable escape for special chars.
  local lhs = char

  vim.keymap.set("i", lhs, function()
    local ft = vim.bo.filetype
    -- Temporarily "apply" the key by appending it to the virtual line
    -- so rules that match ON the typed char work correctly.
    -- We do this by checking with the char appended at col.
    local line = vim.api.nvim_get_current_line()
    local col  = vim.api.nvim_win_get_cursor(0)[2]

    -- Inject char into line at cursor so matching works
    local fake_line = line:sub(1, col) .. char .. line:sub(col + 1)
    vim.api.nvim_set_current_line(fake_line)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], col + #char })

    local result = try_apply(vim.bo.filetype)

    -- Restore line (the keys returned will do the actual edit)
    vim.api.nvim_set_current_line(line)
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], col })

    if result then
      -- The char is already accounted for in before/after of the rule,
      -- but we injected it — so we need to type it first, then apply.
      -- Actually: result already encodes BS-ing the before (which includes the char).
      -- So: type the char first (it lands in buffer), then the correction keys run.
      -- Return char .. result so nvim types char then immediately corrects.
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

---Re-read config and remap (call after live config changes)
M.reload = function()
  -- Unmap old chars
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
