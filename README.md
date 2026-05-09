<div align="center">
    <img src="./etoile.webp" width="384" />
    <p>
    <div>A floating, editable file tree for Neovim.</div>
    </p>
    <p>
        English | <a href="./README.ja.md">日本語</a>
    </p>
    <p>
        <a href="https://github.com/tadashi-aikawa/etoile/blob/main/LICENSE">
          <img src="https://img.shields.io/github/license/tadashi-aikawa/etoile.nvim" alt="License" />
        </a>
    </p>
</div>

---

- **Floating File Tree**
    - Opens a file tree in a floating window with the root resolved from the current Git repository or working directory.
    - Keeps the tree near the source window by default, while leaving room for the preview window when possible.
- **Editable File Operations**
    - Edit the tree buffer and save it to create, move, rename, copy, or delete files and directories.
    - New entries become directories when they have indented children or a trailing slash; otherwise they become files.
    - Deletes and moves ask for confirmation by default.
- **Preview**
    - Opens a preview float by default for the entry under the cursor.
    - Supports file previews, directory previews, and optional image previews via [snacks.nvim](https://github.com/folke/snacks.nvim).
- **Search**
    - Searches all files and directories under the current root, including collapsed descendants.
    - Can expand parent directories for matched entries automatically.
- **Git Status**
    - Shows Git status icons in the left gutter when the tree root is inside a Git repository.
    - Propagates non-ignored descendant status to directories.

## Demo Video

TODO: Add a demo video after it is ready.

## Setup

### Requirements

- Neovim 0.10+
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for image previews

### Install with lazy.nvim

```lua
{
  "tadashi-aikawa/etoile.nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    -- Optional, only needed for image previews:
    -- "folke/snacks.nvim",
  },
  config = function()
    require("etoile").setup({
      -- See "Configuration Example" below.
    })
  end,
}
```

### Install with vim.pack

If your Neovim includes the built-in `vim.pack` plugin manager, add this to `init.lua`:

```lua
vim.pack.add({
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/tadashi-aikawa/etoile.nvim",
  -- Optional, only needed for image previews:
  -- "https://github.com/folke/snacks.nvim",
})

require("etoile").setup({
  -- See "Configuration Example" below.
})
```

Open the tree:

```vim
:Etoile
```

Open the tree with an explicit root:

```vim
:Etoile /path/to/project
```

You can also open it from Lua:

```lua
require("etoile").open({ path = "/path/to/project" })
```

## Usage

### Default Keymaps

| Key | Action |
| --- | --- |
| `<CR>` | Open a file or expand/collapse a directory |
| `-` | Move the tree root to the parent directory |
| `<C-]>` | Move the tree root to the directory under the cursor |
| `<C-p>` | Toggle the preview float |
| `<leader>w` | Switch focus between the tree float and preview float |
| `<leader>s` | Search all entries under the current root |
| `<leader>n` | Jump to the next search result |
| `<leader>N` | Jump to the previous search result |
| `<leader>l` | Clear search highlights |
| `q` | Close etoile |
| `<C-o>` / `<C-i>` | Jump backward/forward while staying in the etoile window |

### Editing the Tree

Only file and directory names are editable. Icons and Git status markers are rendered as virtual text outside the buffer text.

Saving the etoile buffer applies the difference between the original tree and the edited tree:

- Rename a line to move or rename the file or directory.
- Change indentation to move an entry under another directory.
- Duplicate an existing line to copy the source entry.
- Add a new line to create a file.
- Add a new line with indented children, or with a trailing `/`, to create a directory.
- Delete a line to delete the file or directory.

When `confirm.delete = true`, deletes open a confirmation window before files are removed. When
`confirm.move = true`, moves and renames open a confirmation window showing the before and after paths.
If multiple confirmed operations are pending, they are shown together in a single confirmation window.
Canceling the confirmation keeps the edited tree buffer unchanged. Press `r` in the confirmation
window to revert pending edits.

### Preview

The preview float opens by default for the entry under the cursor. File previews use regular Neovim buffers with filetype and syntax detection. Directory previews render a shallow tree using the same icons as the main tree.

If [snacks.nvim](https://github.com/folke/snacks.nvim) is installed and `snacks.image` supports the target file, etoile uses it for image previews.

Saving a file from the preview buffer refreshes the main tree's Git status display by default.

### Search

Search is path-based and splits the query into whitespace-separated terms. All terms must match the root-relative path. Directory matches are shown when the last query component matches the directory name.

Matched entries are highlighted and annotated with their result index. By default, parent directories for all matches are expanded automatically.

### Git Status

When the tree root is inside a Git repository, etoile runs `git status --porcelain=v1 -z --untracked-files=all`.

If `git_status.show_ignored = true`, ignored entries are also collected with `--ignored=matching`. Ignored status is shown only for matching paths, while other statuses propagate upward so a directory can show the highest-priority status among its descendants.

## Configuration Example

Complete sample including all options and default values:

```lua
require("etoile").setup({
  root = {
    strategy = "git_or_cwd",
  },
  float = {
    border = "rounded",
    width_padding = 2,
    left_padding = 3,
    icon_width_padding = 4,
    right_padding = 10,
    height_ratio = 0.8,
    max_height = 50,
    max_height_ratio = 0.8,
    min_height = 10,
    min_height_ratio = 0.2,
    min_width = 24,
    max_width = 100,
    position = "source_window",
    reserve_preview_width = true,
    row = nil,
    col = 4,
  },
  preview = {
    enabled = true,
    border = "rounded",
    min_width = 30,
    max_width = 120,
    width_ratio = 0.8,
    max_height = 50,
    max_height_ratio = 0.8,
    min_height = 10,
    min_height_ratio = 0.2,
    height_ratio = 0.8,
    directory = {
      enabled = true,
      max_depth = 2,
    },
  },
  keymaps = {
    open = "<CR>",
    parent = "-",
    child = "<C-]>",
    preview = "<C-p>",
    search = "<leader>s",
    search_next = "<leader>n",
    search_prev = "<leader>N",
    search_clear = "<leader>l",
    close = "q",
    focus_preview = "<leader>w",
  },
  search = {
    exclude = { ".git", "node_modules", ".cache" },
    expand_matches = true,
  },
  git_status = {
    show_ignored = true,
    sync_on_preview_write = true,
  },
  confirm = {
    delete = true,
    move = true,
    copy = false,
    create = false,
  },
  icons = {
    link = "",
    directory = "",
    directory_open = "",
    git_status = {
      modified = "",
      added = "",
      deleted = "",
      renamed = "",
      ignored = "",
      conflicted = "",
    },
  },
  indent = 2,
})
```

## Options

### root

`root.strategy = "git_or_cwd"` is the current root resolution behavior. When no path is passed to `:Etoile` or `require("etoile").open()`, etoile uses the nearest Git root from the current buffer path. If no Git root exists, it falls back to the current working directory.

### float

`float` controls the main tree window.

- The window title shows `Etoile - <root directory name>`.
- `position = "source_window"` places the tree near the left edge of the window that opened etoile.
- Set `position = "editor"` to use the fixed editor-relative `float.col` value.
- `reserve_preview_width = true` shifts the main tree left when needed so the preview can open on the right side.
- `row = nil` vertically centers the tree. Set a number to use a fixed editor-relative row.
- `left_padding` reserves room for Git status icons.
- `icon_width_padding` reserves room for symlink and filetype icons rendered as virtual text.
- `right_padding` adds room on the right side of the tree.

Height is controlled by `height_ratio`, `max_height`, `max_height_ratio`, `min_height`, and `min_height_ratio`. The effective max height uses the larger value from size and ratio, and the effective min height uses the smaller value from size and ratio.

### preview

`preview.enabled = true` opens the preview float as soon as etoile opens. Set it to `false` to start with preview closed.

Preview width is controlled by `preview.width_ratio`, `preview.min_width`, and `preview.max_width`. Preview height uses the same height option semantics as `float`.

Directory preview is enabled by default and limited to `preview.directory.max_depth = 2`. The preview target's direct children are depth `0`. Set `preview.directory.enabled = false` to disable directory previews.

### keymaps

All configurable mappings are buffer-local to the etoile buffer. `focus_preview` is also mapped in the preview buffer so the same key toggles focus back to the main tree.

`<C-o>` and `<C-i>` are always mapped internally to keep jump navigation from accidentally replacing the etoile window with another buffer.

### search

`search.exclude` skips matching entries while rendering the tree, searching, and rendering directory previews.

`search.expand_matches = true` expands parent directories for all matched entries before jumping to the current match. Set it to `false` to keep matches collapsed until they are selected.

### git_status

Set `git_status.show_ignored = false` to disable ignored-file status display.

Set `git_status.sync_on_preview_write = false` to stop refreshing the main tree's Git status after saving a preview buffer.

### confirm

`confirm.delete = true` asks before deleting files or directories. `confirm.move = true` asks before moving or renaming files or directories and shows the before and after paths.

`confirm.copy = false` and `confirm.create = false` keep copies and creates immediate by default. Set them to `true` to ask before applying those operations.

All enabled confirmations are grouped into one confirmation window when saving. Cancel only closes the confirmation and keeps the edited tree buffer as-is. Revert redraws the tree from the current file system state and discards pending tree edits.

### icons

`icons.directory` and `icons.directory_open` customize collapsed and expanded directory icons.

`icons.git_status` customizes the status icons shown in the left gutter. The supported statuses are `modified`, `added`, `deleted`, `renamed`, `ignored`, and `conflicted`.

### indent

`indent` controls the number of spaces per tree depth. It is used when rendering the tree and when interpreting edited indentation during save.

## Development

Install dependencies used by your Neovim test environment, then run:

```bash
make test
```

Format check:

```bash
make format-check
```

Format:

```bash
make format
```

The underlying commands are `busted`, `stylua --check .`, and `stylua .`.

## Acknowledgements

Etoile is inspired by the following projects:

- [oil.nvim](https://github.com/stevearc/oil.nvim)
- [fyler.nvim](https://github.com/A7Lavinraj/fyler.nvim)

## License

MIT
