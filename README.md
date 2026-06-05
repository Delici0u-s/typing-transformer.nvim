# typing-transformer.nvim

Define insert-mode text transformations that run while you type.

A rule matches text around the cursor and replaces it immediately when the trigger is completed.

## Installation

### lazy.nvim

```lua
{
  "Delici0u-s/typing-transformer.nvim",
  opts = {
    global = {
      '"  |)"  -> ")|"',
      '"cosnt |" -> "const |"',
      '" teh |" -> " the |"',
    },
    filetype = {
      lua = {
        '"!lfn|" -> "local function |"',
        '"test|" -> "successful|"',
      },
    },
  },
}
```

## Rule Syntax

```text
'"<trigger>" -> "<result>"'
```

`|` marks the cursor position.

### Trigger

Text before `|` must exist directly before the cursor.

Text after `|` must exist directly after the cursor.

### Result

Text before `|` replaces the matched text before the cursor.

Text after `|` replaces existing text or moves past it when it already matches.

### Escaping

```text
\|   literal pipe
\\   literal backslash
```

## Priority

1. Filetype rules are checked first.
2. Rules are checked in order.
3. The first matching rule wins.

Put more specific rules before more general ones.

## Examples

### Fix common typos

```lua
'"cosnt |" -> "const |"'
'"funciton |" -> "function |"'
'"retrun |" -> "return |"'
'"teh |" -> "the |"'
```

### Expand Lua snippets

```lua
'"local fn|" -> "local function |"'
'"req|" -> "require(\"|\")"'
```

### Move past existing characters

```lua
'"  |)" -> ")|"'
'"  |]" -> "]|"'
'"  |}" -> "}|"'
```

## Configuration

```lua
require("typing-transformer").setup({
  global = {},

  filetype = {
    lua = {},
  },
})
```

## Rule summary
1. `|` marks the cursor position in both the trigger and the result.
2. Use `\|` for a literal pipe and `\\` for a literal backslash.
3. Rules match text immediately around the cursor and transform it as you type.
4. The matched text is replaced with the rule's result when the trigger completes.
5. Filetype-specific rules are checked before global rules.
6. Rules are evaluated top to bottom; the first match wins.

