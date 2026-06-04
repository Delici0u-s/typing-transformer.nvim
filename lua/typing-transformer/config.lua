local M = {}

---@class TypingTransformerConfig
---@field global string[]           Rules active in all filetypes
---@field filetype table<string, string[]>  Rules active only for specific filetypes

local defaults = {
  global = {},
  filetype = {},
}

local _config = vim.deepcopy(defaults)

---Parse a single rule string like '"  |)" -> ")|"'
---Returns { trigger = string, result = string } or nil + error message
---@param raw string
---@return table|nil, string|nil
M.parse_rule = function(raw)
  -- Strip leading/trailing whitespace
  raw = raw:match("^%s*(.-)%s*$")

  -- Skip comments
  if raw:sub(1, 1) == "#" or raw == "" then
    return nil, nil -- silently skip
  end

  -- Match: "trigger" -> "result"
  -- Supports single or double quotes around each side
  local trigger, result = raw:match('^["\'](.+)["\']%s*%->%s*["\'](.+)["\']$')

  if not trigger or not result then
    return nil, ("typing-transformer: could not parse rule: %s"):format(raw)
  end

  return { trigger = trigger, result = result }, nil
end

M.setup = function(user_config)
  _config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})

  -- Validate rule strings at setup time so errors surface early
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
