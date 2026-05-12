<div align="center">
    <img src="./etoile.webp" width="384" />
    <p>
    <div>Neovim のための、編集可能なフローティングファイルツリー</div>
    </p>
    <p>
        <a href="./README.md">English</a> | 日本語
    </p>
    <p>
        <a href="https://github.com/tadashi-aikawa/etoile/blob/main/LICENSE">
          <img src="https://img.shields.io/github/license/tadashi-aikawa/etoile.nvim" alt="License" />
        </a>
    </p>
</div>

---

- **Floating File Tree**
    - Git リポジトリまたはカレントディレクトリから root を解決し、ファイルツリーをフローティングウィンドウで開く。
    - デフォルトでは呼び出し元ウィンドウの近くに表示し、可能な範囲で preview 用のスペースも確保する。
- **Editable File Operations**
    - ツリーバッファを編集して保存すると、ファイルやディレクトリの作成・移動・リネーム・コピー・削除を適用する。
    - インデントされた子を持つ新規行、または末尾 `/` の新規行はディレクトリとして扱い、それ以外はファイルとして扱う。
    - 削除時と移動時はデフォルトで確認する。
- **Preview**
    - カーソル下の entry に対する preview float をデフォルトで開く。
    - ファイル preview、ディレクトリ preview、[snacks.nvim](https://github.com/folke/snacks.nvim) による任意の画像 preview に対応する。
- **Search**
    - 現在の root 配下のファイルとディレクトリを、折りたたまれた子孫も含めて検索する。
    - マッチした entry の親ディレクトリを自動展開できる。
- **Git Status**
    - ツリー root が Git リポジトリ内にある場合、左ガターに Git status アイコンを表示する。
    - ignored 以外の子孫 status はディレクトリへ伝搬する。

## デモ動画

TODO: 動画が準備できたら追加する。

## セットアップ

### 要件

- Neovim 0.10+
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
- 任意: 画像 preview 用の [snacks.nvim](https://github.com/folke/snacks.nvim)

### lazy.nvim でインストール

```lua
{
  "tadashi-aikawa/etoile.nvim",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
    -- 任意。画像 preview が必要な場合のみ:
    -- "folke/snacks.nvim",
  },
  ---@class etoile.Config
  ---@diagnostic disable: missing-fields
  opts = {
    -- 後述の「設定例」を参照
  }
}
```

### vim.pack でインストール

組み込みの `vim.pack` plugin manager を含む Neovim を使っている場合は、`init.lua` に以下を追加:

```lua
vim.pack.add({
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/tadashi-aikawa/etoile.nvim",
  -- 任意。画像 preview が必要な場合のみ:
  -- "https://github.com/folke/snacks.nvim",
})

require("etoile").setup({
  -- 後述の「設定例」を参照
})
```

ツリーを開く:

```vim
:Etoile
```

明示した root でツリーを開く:

```vim
:Etoile /path/to/project
```

Lua から開くこともできる:

```lua
require("etoile").open({ path = "/path/to/project" })
```

## 使い方

### デフォルトキーマップ

| キー | 動作 |
| --- | --- |
| `<CR>` | ファイルを開く、またはディレクトリを展開/折りたたみ |
| `-` | ツリー root を親ディレクトリへ移動 |
| `<C-]>` | ツリー root をカーソル下のディレクトリへ移動 |
| `<C-p>` | preview float を toggle |
| `<C-w>w` | tree window と preview float の focus を切り替え |
| `<C-w>l` | preview float へ focus |
| `<C-w>h` | tree window へ focus |
| `<leader>s` | 現在の root 配下を検索 |
| `<leader>n` | 次の検索結果へ移動 |
| `<leader>N` | 前の検索結果へ移動 |
| `<leader>l` | 検索 highlight をクリア |
| `<leader>?` | tree/preview の keymap ヘルプを表示 |
| `q` | etoile を閉じる |
| `<C-o>` / `<C-i>` | etoile window に留まったまま jump backward/forward |

### ツリー編集

編集対象はファイル名とディレクトリ名だけ。アイコンと Git status marker は buffer text の外側に virtual text として描画される。既存 entry には行 indent の後ろに concealed な `000001` のような6桁 source id が含まれるため、通常の yank/delete 操作でも etoile root を移動した後の source identity を保持する。カーソルは編集可能なファイル名部分に補正される。この id は etoile 外へ register を paste した場合や conceal を無効化した場合に見えることがある。

etoile buffer を保存すると、元のツリーと編集後ツリーの差分を適用する:

- 行名を変更するとファイルやディレクトリを移動/リネームする。
- インデントを変更すると entry を別ディレクトリ配下へ移動する。
- 既存行を複製すると元 entry をコピーする。
- 新しい行を追加するとファイルを作成する。
- インデントされた子を持つ新しい行、または末尾 `/` の新しい行を追加するとディレクトリを作成する。
- 行を削除するとファイルやディレクトリを削除する。

`confirm.delete = true` の場合、削除前に確認ウィンドウを表示する。`confirm.move = true` の場合、移動/リネーム前に変更前後のパスを確認ウィンドウに表示する。確認対象の操作が複数ある場合は、1つの確認ウィンドウにまとめて表示する。確認を cancel しても編集中の tree buffer はそのまま残る。保留中の編集を破棄するには確認ウィンドウで `r` を押す。

### Preview

preview float はデフォルトでカーソル下の entry に対して開く。ファイル preview は通常の Neovim buffer を使い、filetype と syntax を検出する。ディレクトリ preview は main tree と同じ icon を使って浅いツリーを描画する。

[snacks.nvim](https://github.com/folke/snacks.nvim) がインストールされていて、`snacks.image` が対象ファイルをサポートしている場合、etoile は画像 preview にそれを使う。

preview buffer のファイルを保存すると、デフォルトでは main tree の Git status 表示を更新する。

### Search

検索は path-based で、query は空白区切りの term に分割される。root からの相対 path にすべての term が含まれ、最後の query component が entry 名にマッチする場合に結果へ含まれる。

マッチした entry は highlight され、結果 index が注釈として表示される。デフォルトでは、すべてのマッチの親ディレクトリを自動展開する。

### Git Status

ツリー root が Git リポジトリ内にある場合、etoile は `git status --porcelain=v1 -z --untracked-files=all` を実行する。

`git_status.show_ignored = true` の場合、ignored entry も `--ignored=matching` で取得する。ignored status は該当 path にだけ表示し、それ以外の status は上位へ伝搬するため、ディレクトリには子孫のうち最も優先度の高い status が表示される。

## 設定例

全設定を含むサンプル（デフォルト値）:

```lua
{
  root = {
    strategy = "git_or_cwd",
  },
  tree = {
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
    open_split = "<C-x>",
    open_vsplit = "<C-v>",
    open_tab = "<C-t>",
    parent = "-",
    child = "<C-]>",
    preview = "<C-p>",
    search = "<leader>s",
    search_next = "<leader>n",
    search_prev = "<leader>N",
    search_clear = "<leader>l",
    help = "<leader>?",
    close = "q",
    focus_toggle = "<C-w>w",
    focus_preview = "<C-w>l",
    focus_tree = "<C-w>h",
  },
  search = {
    exclude = { ".git", "node_modules", ".cache", "venv", ".venv" },
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
}
```

## オプション

### root

`root.strategy = "git_or_cwd"` は現在の root 解決動作を表す。`:Etoile` または `require("etoile").open()` に path が渡されない場合、現在 buffer path から最寄りの Git root を使う。Git root が存在しない場合は current working directory に fallback する。

### tree

`tree` は main tree window を制御する。

- window title には `Etoile - <root directory name>` を表示する。
- `position = "source_window"` は etoile を開いた window の左端付近に tree を表示する。
- `position = "editor"` にすると、固定の editor-relative な `tree.col` を使う。
- `reserve_preview_width = true` は preview を右側に開けるよう、必要に応じて main tree を左へ寄せる。
- `row = nil` の場合は tree を垂直中央に配置する。数値を指定すると固定の editor-relative row を使う。
- `left_padding` は Git status icon 用の領域を確保する。
- `icon_width_padding` は virtual text として描画される symlink / filetype icon 用の領域を確保する。
- `right_padding` は tree 右側の余白を追加する。

高さは `height_ratio`, `max_height`, `max_height_ratio`, `min_height`, `min_height_ratio` で制御する。effective max height は size と ratio の大きい方、effective min height は size と ratio の小さい方を使う。

### preview

`preview.enabled = true` の場合、etoile を開いた時点で preview float も開く。`false` にすると preview を閉じた状態で開始する。

preview 幅は `preview.width_ratio`, `preview.min_width`, `preview.max_width` で制御する。preview 高さは `tree` と同じ height option の semantics を使う。

`preview.debounce_ms = 80` は cursor move による preview 更新を遅延させる。`j` や `k` を押しっぱなしにした場合は、移動が落ち着いてから preview する。`0` にするとカーソル移動ごとに即時更新する。

ディレクトリ preview はデフォルトで有効で、`preview.directory.max_depth = 2` まで表示する。preview 対象の直下 child は depth `0`。`preview.directory.enabled = false` で無効化できる。

### keymaps

設定可能な mapping はすべて buffer local。`focus_toggle` は tree window と preview buffer の focus を切り替える。`focus_preview` は tree buffer、`focus_tree` は preview buffer に mapping される。

`help` は tree buffer と preview buffer の両方に mapping される。ヘルプウィンドウは現在の buffer のタブを選択した状態で開き、`<Tab>`、`<S-Tab>` で Tree / Preview タブを切り替えられる。

`open_split`、`open_vsplit`、`open_tab` は選択中の file をそれぞれ `:split`、`:vsplit`、`:tabedit` で開く。

`<C-o>` と `<C-i>` は、jump navigation で etoile window が別 buffer に置き換わるのを避けるため、内部的に常に mapping される。

### search

`search.exclude` は tree rendering、検索、directory preview rendering の対象から entry を除外する。

`search.expand_matches = true` の場合、current match へ移動する前にすべての matched entry の親ディレクトリを展開する。`false` にすると、match が選択されるまで折りたたまれた状態を維持する。

### git_status

`git_status.show_ignored = false` にすると ignored file の status 表示を無効化する。

`git_status.sync_on_preview_write = false` にすると、preview buffer 保存後に main tree の Git status を更新しない。

### confirm

`confirm.delete = true` はファイルやディレクトリの削除前に確認する。`confirm.move = true` はファイルやディレクトリの移動/リネーム前に確認し、変更前後のパスを表示する。

`confirm.copy = false` と `confirm.create = false` により、コピーと作成はデフォルトでは即時適用される。`true` にすると、それぞれの操作前に確認する。

保存時に有効な確認対象が複数ある場合は、1つの確認ウィンドウにまとめて表示する。Cancel は確認ウィンドウを閉じるだけで、編集中の tree buffer は変更しない。Revert は現在のファイルシステム状態から tree を再描画し、保留中の tree 編集を破棄する。

### icons

`icons.directory` と `icons.directory_open` で、閉じた/開いたディレクトリ icon をカスタマイズできる。

`icons.git_status` で左ガターに表示する status icon をカスタマイズできる。対応 status は `modified`, `added`, `deleted`, `renamed`, `ignored`, `conflicted`。

### indent

`indent` は tree depth ごとの space 数を制御する。tree の描画と、保存時に編集されたインデントを解釈するために使う。

## 開発

Neovim test environment で使う依存関係をインストールしたうえで実行:

```bash
make test
```

format check:

```bash
make format-check
```

format:

```bash
make format
```

内部的には `busted`, `stylua --check .`, `stylua .` を実行する。

## 謝辞

Etoile は以下のプロジェクトから影響を受けています:

- [oil.nvim](https://github.com/stevearc/oil.nvim)
- [fyler.nvim](https://github.com/A7Lavinraj/fyler.nvim)

## ライセンス

MIT
