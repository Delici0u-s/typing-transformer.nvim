local M = {}

local config = require("typing-transformer.config")
local rules = require("typing-transformer.rules")
local engine = require("typing-transformer.engine")

M.setup = function(user_config)
  config.setup(user_config)
  rules.build(config.get())
  engine.attach()
end

return M
