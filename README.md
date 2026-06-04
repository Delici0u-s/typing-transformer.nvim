# typing-transformer.nvim

Insert-mode typing transformation rules for Neovim — inspired by the [Obsidian Typing Transformer plugin](https://github.com/aptend/typing-transformer-obsidian).

Define rules like `'"  |)" -> ")|"'` and the plugin will automatically transform text around your cursor as you type.

---

## Features

- Simple `"trigger" -> "result"` rule syntax with `|` as cursor marker
- Global rules + per-filetype overrides
- Priority: filetype-specific rules fire before global ones; first match wins
- Zero dependencies — pure Lua

---

## Installation

### lazy.nvim

```lua
{
  "quad/typing-transformer.nvim",
  event = "InsertEnter",
  opts = {
    global = {
      '"  |)"  -> ")|"',
      '"  |]]" -> "]]|"',
      '"  |**" -> "**|"',
      '"  |*"  -> "*|"',
    },
    filetype = {
      markdown = {
        '"  |>" -> ">|"',
      },
    },
  },
}
```

### packer.nvim

```lua
use {
  "quad/typing-transformer.nvim",
  config = function()
    require("typing-transformer").setup({
      global = {
        '"  |)"  -> ")|"',
      },
    })
  end,
}
```

---

## Rule Syntax

```
'"<trigger>" -> "<result>"'
```

`|` marks the cursor position in both trigger and result.

| Part | Meaning |
|------|---------|
| Left of `\|` in trigger | Text that must be immediately **before** the cursor |
| Right of `\|` in trigger | Text that must be immediately **after** the cursor |
| Left of `\|` in result | Replaces text that was left of cursor |
| Right of `\|` in result | Either replaces or is skipped over (if already present) |

Escape `\|` for a literal pipe, `\\` for a literal backslash.

### Priority

1. Filetype-specific rules are checked before global rules
2. Within a list, earlier rules have higher priority (first match wins)
3. Put longer / more specific triggers first

### Examples

```lua
-- Double-space to jump past closing delimiters (your original use case)
'"  |)"  -> ")|"'
'"  |]]" -> "]]|"'
'"  |**" -> "**|"'
'"  |*"  -> "*|"'

-- Auto-correct
'"cosnt |" -> "const |"'

-- Expand abbreviation
'"brb|" -> "be right back|"'

-- Auto-pair and place cursor inside
'"<|" -> "<|>"'
```

---

## Configuration Reference

```lua
require("typing-transformer").setup({
  -- Rules active in all buffers
  global = {
    -- list of rule strings
  },

  -- Rules active only for a specific filetype (higher priority than global)
  filetype = {
    lua = {
      -- list of rule strings
    },
    markdown = {
      -- list of rule strings
    },
  },
})
```

