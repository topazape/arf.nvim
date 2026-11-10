# arf.nvim

<p align="center">
  <img src="assets/logo.png" alt="arf.nvim logo" width="560">
</p>

[English](README.md) | 日本語

**R のコードと実行結果を、Neovim の同じバッファで。**

`.R` ファイルから式を実行し、テキストとプロットをコード直下に表示します。
バックエンドには [arf](https://github.com/eitsupi/arf) を使います。

<p align="center">
  <img src="assets/inline-plot.png" alt="R コードの直下にプロットと式ごとの実行時間を表示" width="720">
</p>

- 式単位・選択範囲・バッファ全体を実行。
- R セッションを自動起動し、実行の間でオブジェクトを保持。
- 保存した出力の確認、オブジェクトの検査、プロットのコピー。
- カーソル位置のオブジェクトの `summary()` を表示。`inspect()` で `str()` やモデル診断関数も呼び出せます。
- 結果は仮想行に表示し、ソースファイルはそのまま。

## 必要なもの

- **Neovim 0.12+**、**R**、PATH に通した **[arf](https://github.com/eitsupi/arf) 0.7.0 以降**。
- 式の自動選択・バッファ全体の実行には **R の Tree-sitter パーサー**。
- インライン画像には `image` を有効にした **[Snacks](https://github.com/folke/snacks.nvim)**、**ImageMagick**、**Ghostty** や **Kitty** などの対応ターミナル。

## インストール

[lazy.nvim](https://github.com/folke/lazy.nvim) の設定に追加します。

```lua
return {
  "topazape/arf.nvim",
  version = "*",
  ft = "r",
  dependencies = {
    { "folke/snacks.nvim", opts = { image = { enabled = true } } },
  },
  opts = {},
  keys = {
    { "<LocalLeader>fr", "<Cmd>ArfRun<CR>", ft = "r", desc = "Run R expression" },
    { "<LocalLeader>fr", ":ArfRun<CR>", mode = "x", ft = "r", desc = "Run selected lines" },
    { "<LocalLeader>fc", "<Cmd>ArfClear<CR>", ft = "r", desc = "Clear results" },
    { "<LocalLeader>fo", "<Cmd>ArfOutput<CR>", ft = "r", desc = "Open saved output" },
    { "<LocalLeader>fk", "<Cmd>ArfSummary<CR>", ft = "r", desc = "Inspect R object" },
    { "<LocalLeader>fi", "<Cmd>ArfInterrupt<CR>", ft = "r", desc = "Interrupt R" },
  },
}
```

Snacks を設定済みなら、既存のオプションに `image = { enabled = true }` を追加してください。

## 最初の実行

R プロジェクトのディレクトリで `.R` ファイルを開きます。

```r
x <- mtcars
head(x)
plot(x$mpg, x$wt)
```

各行にカーソルを置き、上から順に `<LocalLeader>fr` を押します。初回に R が自動起動し、以降は同じセッションを使います。代入だけの式は通常テキストを出力しません。

`<LocalLeader>` の既定値は `\` なので、実際のキーは `\fr` です。Visual モードで行を選択すると、同じキーでその範囲を実行できます。

- `<LocalLeader>fo`：カーソル位置の保存済み出力を開く。`/` で検索、`y` でコピー、`q` で閉じる。
- `<LocalLeader>fc`：結果を消す。R のオブジェクトは保持。
- `<LocalLeader>fi`：セッションを保持して実行を中断。

ほかの操作：

- `:ArfRunAll`：バッファ全体を実行。
- `:ArfCopyPlot`：最後の保存済みプロットをコピー。
- `:ArfStop`：自動起動したセッションを終了し、結果を消す。

## オブジェクトの検査

`:ArfObjects` で、現在の R セッションのオブジェクトを Snacks.picker から探せます。
`<CR>` でサマリーを表示し、通常モードの `p` で選んだオブジェクトを出力します。

<p align="center">
  <img src="assets/object-picker.png" alt="R オブジェクトの名前・クラス・サイズを一覧表示" width="720">
</p>

オブジェクトを作成するコードを実行したあと、その名前にカーソルを置いて `<LocalLeader>fk`（上の設定例では `\fk`）または `:ArfSummary` を使うと、`base::summary()` の結果をフロートに表示します。結果は `q` で閉じます。

<p align="center">
  <img src="assets/object-summary.png" alt="線形モデルのサマリーをフロートで表示" width="720">
</p>

`inspect()` では、カーソル位置のオブジェクトに適用する R 関数を指定できます。構造を調べる `str()` や、モデルの評価指標を表示する関数もキーに割り当てられます。lazy.nvim の `keys` に追加してください。

```lua
{
  "<LocalLeader>ft",
  function() require("arf").inspect("utils::str") end,
  ft = "r",
  desc = "Inspect R object structure",
},
{
  "<LocalLeader>fp",
  function()
    require("arf").inspect("performance::model_performance", {
      title = "Model performance",
    })
  end,
  ft = "r",
  desc = "Inspect model performance",
},
```

指定した関数にはオブジェクトが唯一の引数として渡され、テキスト結果をフロートに表示します。`package::function` はパッケージのインストールが必要ですが、`library()` は不要です。セッション内で定義した関数名も指定できます。追加の引数を渡す例などは `:help arf-inspect` を参照してください。

## 設定

設定なしで使えます。変更したい項目だけ、lazy.nvim の `opts` に指定してください。

```lua
opts = {
  inline = { max_lines = 10, border = "rounded" },
  float_window = { width = "80%" },
  output = { tibble = { max_rows = 100 } },
}
```

<details>
<summary>全設定と既定値</summary>

```lua
require("arf").setup({
  executable = "arf",
  pid = nil,                -- 省略: 自動起動、数値: 外部セッション、false: 自動起動に戻す
  startup_timeout_ms = 10000, -- 10秒
  eval_timeout_ms = 300000, -- 1回の評価につき5分

  output = {
    max_bytes = 1048576,      -- 1回の評価で保持するバイト数（エラーを含む）
    tibble = {
      max_rows = "inherit",     -- "inherit" または正の整数
      width = "auto",           -- "inherit"、"auto"、正の整数、"all"
    },
  },

  inline = {
    max_lines = 20,           -- 枠・通知・画像を除く本文の行数
    border = "line",          -- "rounded"、"single"、"double"、"line"、"none"
  },

  float_window = {          -- 保存済み出力とオブジェクト検査で共用
    width = "60%",            -- "auto"、正の整数、"1%"〜"100%"
    max_height = 30,
  },

  image = {
    render = {                -- R が生成する PNG の設定
      width_px = 1200,
      height_px = 800,
      dpi = 180,
    },
    display = {               -- 表示サイズの上限（ターミナルのセル単位）
      max_width = 100,          -- 列数
      max_height = 30,          -- 行数
    },
  },

  theme = "default",        -- "default"、"auto"、"neon"

  signs = {
    enabled = true,
    priority = 5,
    range = { text = "│" },
    success = { text = "│", hl = "ArfSignSuccess" },
    error = { text = "│", hl = "ArfSignError" },
    interrupted = { text = "│", hl = "ArfSignInterrupted" },
    running = {
      text = "…",               -- アニメーション無効時の記号
      hl = "ArfSignRunning",
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      interval_ms = 80,         -- ミリ秒
    },
  },
})
```

</details>

`inline.border` は `"line"`（既定）、`"single"`、`"rounded"`、`"double"`、`"none"` から選べます。囲み枠では、現在のタブで同じバッファを表示している最も狭いウィンドウに合わせて長い行を省略します。保持されている全文は `:ArfOutput` で確認できます。

全設定・コマンド・独自のオブジェクト検査・困ったときの対処は、[ヘルプ](doc/arf.txt)（`:help arf`）を参照してください。全設定の既定値は `:help arf-configuration` にあります。

## このプロジェクトについて

自分の R 作業のために、AI と vibe coding で作りました。小さく保つ方針です。必要に応じて fork して育ててください。

## ライセンス

[MIT ライセンス](LICENSE) © 2026 topazape.
