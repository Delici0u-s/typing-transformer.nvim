local M = {}

---@class TypingTransformerConfig
---@field global string[]
---@field filetype table<string, string[]>

local defaults = {
  global = {},
  filetype = {},
}

local _config = vim.deepcopy(defaults)

---Detect and strip r"..." prefix.
---Returns is_regex (bool), and the inner string with prefix removed.
---@param s string
---@return boolean, string
local function detect_regex(s)
  if s:match("^r\"") or s:match("^r'") then
    return true, s:sub(2)
  end
  return false, s
end

---Parse a single rule string.
---Handles both literal:  '"trigger|" -> "result|"'
---and regex:             'r"trigger|" -> "result|"'
---
---Returns a table:
---  { is_regex, trigger, result }
---or nil + error string.
---@param raw string
---@return table|nil, string|nil
M.parse_rule = function(raw)
  raw = raw:match("^%s*(.-)%s*$")

  if raw:sub(1, 1) == "#" or raw == "" then
    return nil, nil
  end

  -- Split on " -> " allowing optional whitespace
  -- We need to handle r"..." and "..." prefixes on the trigger side.
  -- Pattern: optional-r then quoted-string, arrow, quoted-string
  local trigger_raw, result_raw = raw:match('^(r?["\'].+["\'])%s*%->%s*(["\'].+["\'])$')

  if not trigger_raw or not result_raw then
    return nil, ("typing-transformer: could not parse rule: %s"):format(raw)
  end

  local is_regex, trigger_stripped = detect_regex(trigger_raw)

  -- Strip outer quotes from both sides
  local trigger = trigger_stripped:match('^["\'](.+)["\']$')
  local result  = result_raw:match('^["\'](.+)["\']$')

  if not trigger or not result then
    return nil, ("typing-transformer: malformed quotes in rule: %s"):format(raw)
  end

  return { is_regex = is_regex, trigger = trigger, result = result }, nil
end

M.setup = function(user_config)
  _config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})

  local function validate_list(list, context)
    for _, raw in ipairs(list) do
      local _, err = M.parse_rule(raw)
      if err then
        vim.notify(err .. (" (in %s)"):format(context), vim.log.levels.WARN)
      end
    end
  end

  validate_list(_config.global, "global")
  for ft, list in pairs(_config.filetype) do
    validate_list(list, "filetype." .. ft)
  end
end

M.get = function()
  return _config
end

return M
