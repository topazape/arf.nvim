# arf.nvim

<p align="center">
  <img src="assets/logo.png" alt="arf.nvim logo" width="560">
</p>

[English](README.md) | 日本語

**R のコードと実行結果を、Neovim の同じバッファで。**

[arf](https://github.com/eitsupi/arf) をバックエンドに使う Neovim プラグインです。
`.R` ファイルから式を実行し、テキストとプロットをコード直下に表示します。ソースコードには出力を書き込みません。

[Features](#features) · [Comparison](#comparison-with-related-plugins) · [Requirements](#requirements) · [Installation](#installation) · [Usage](#usage) · [Configuration](#configuration) · [Limitations](#limitations) · [Troubleshooting](#troubleshooting)

<p align="center">
  <img src="assets/inline-plot.png" alt="R コードの直下に ggplot の散布図を表示し、式ごとの実行時間を確認" width="720">
</p>

## Features

- **式単位・バッファ全体を実行** — Tree-sitter でパイプ・ggplot・関数定義の範囲を判定。Visual 選択・行範囲にも対応。
- **インライン出力** — テキストとプロットをコード直下に表示。複数の画像は生成順に縦に並べ、別の範囲の結果も保持。直近のプロットはクリップボードにコピー可能。
- **継続する R セッション** — 初回実行で自動起動。代入したオブジェクトを次の実行で利用。
- **長い出力を読み返す** — コードの横では短く表示し、続きを `ArfOutput` で検索・コピー。tibble の出力行数も設定可能。
- **オブジェクトを確認** — カーソル下のオブジェクトに `summary()` や指定した R 関数を実行。
- **状態が見える** — 実行中・成功・エラーをサインで表示。記号と色をカスタマイズ可能。

## Comparison with related plugins

**arf.nvim** は、主に `.R` スクリプトで作業し、式ごとのテキストとプロットをコード直下で読みたい場合に向いています。arf の headless R セッションと IPC で通信し、R の構文に沿った式の選択とインライン表示を提供します。Jupyter や IRkernel は不要です。

- **[R.nvim](https://github.com/R-nvim/R.nvim)** は、ターミナル・tmux 経由の R との通信、補完、オブジェクトブラウザー、R のヘルプ、Quarto / R Markdown 対応など、幅広い R 環境を提供します。R の編集とコンソールを統合した作業には R.nvim、スクリプトを実行してソースのそばで結果を読む用途には arf.nvim が向いています。
- **[iron.nvim](https://github.com/Vigemus/iron.nvim)** は、複数の言語で設定可能な REPL にコードを送ります。対話的な REPL を使って作業するなら iron.nvim、実行した R のソース範囲にテキストとプロットを紐づけて読むなら arf.nvim が向いています。
- **[molten.nvim](https://github.com/benlubas/molten-nvim)** は Jupyter カーネル経由でコードを実行し、R には [IRkernel](https://irkernel.github.io/) を使います。インライン出力・画像表示にも対応し、セルと出力の保存・読み込みや、ノートブックとの出力のインポート・エクスポートもできます。Jupyter ベースの作業には molten.nvim が向いています。arf.nvim は arf と直接通信し、セッションをまたぐ結果の保存には対応しません。
- **[quarto-nvim](https://github.com/quarto-dev/quarto-nvim)** は Quarto 原稿の執筆が中心で、プレビューや埋め込み言語の支援を提供し、コード実行は Molten や iron などに委譲します。`.qmd` の執筆には quarto-nvim、`.R` スクリプトの実行と結果表示には arf.nvim が向いています。

arf.nvim 自体は補完や言語サーバーを提供しません。インラインのプロット表示には Snacks と対応ターミナルが必要です。次の Requirements を参照してください。

## Requirements

- **Neovim 0.12+**
- **R と [arf](https://github.com/eitsupi/arf)** — arf の導入手順に従ってインストールし、`arf` を PATH に通してください。実行ファイルのパスも設定できます。arf 0.6.0 で検証済み。
- **R の Tree-sitter パーサー** — `ArfRun` の通常モードの式判定と `ArfRunAll` に使用。利用中のパーサーマネージャーで `r` を導入してください。Visual 選択・明示的な行範囲の実行には不要です。

画像表示には、次も必要です。

- [snacks.nvim](https://github.com/folke/snacks.nvim) — `image` を有効にしてください。2.31.0 の配置 API で検証済み。
- **Ghostty / Kitty など** — Kitty Graphics Protocol のインライン画像に対応したターミナル。
- **ImageMagick** — Snacks が画像サイズの取得に `magick` または `identify` を使います。

`ArfCopyPlot` でのプロットのコピーには、macOS は `osascript`、Linux は `wl-copy`（Wayland）または `xclip`（X11）、Windows は PowerShell が必要です。

## Installation

### lazy.nvim

次の spec を lazy.nvim の設定に追加してください。

```lua
return {
  "topazape/arf.nvim",
  version = "*",
  ft = "r",
  cmd = { "ArfRun", "ArfRunAll", "ArfClear", "ArfSummary", "ArfObjects", "ArfOutput", "ArfCopyPlot", "ArfStop" },
  dependencies = {
    {
      "folke/snacks.nvim",
      opts = { image = { enabled = true } },
    },
  },
  opts = {},
  keys = {
    { "<LocalLeader>fr", "<Cmd>ArfRun<CR>", ft = "r", desc = "Run R expression" },
    { "<LocalLeader>fr", ":ArfRun<CR>", mode = "x", ft = "r", desc = "Run selected R lines" },
    { "<LocalLeader>fR", "<Cmd>ArfRunAll<CR>", ft = "r", desc = "Run all R expressions" },
    { "<LocalLeader>fc", "<Cmd>ArfClear<CR>", ft = "r", desc = "Clear R results" },
    { "<LocalLeader>fs", "<Cmd>ArfStop<CR>", ft = "r", desc = "Stop R session" },
    { "<LocalLeader>fo", "<Cmd>ArfOutput<CR>", ft = "r", desc = "Show saved R output" },
    { "<LocalLeader>fy", "<Cmd>ArfCopyPlot<CR>", ft = "r", desc = "Copy latest plot" },
    { "<LocalLeader>fk", "<Cmd>ArfSummary<CR>", ft = "r", desc = "Show R object summary" },
  },
}
```

Snacks を既に設定している場合は、その設定に `image = { enabled = true }` を追加してください。
画像表示と Object Picker を使わない場合は `dependencies` を省略できます。

## Usage

1. 対象の R プロジェクトを作業ディレクトリにして、Neovim で `.R` ファイルを開きます。
2. 実行したい式にカーソルを置き、`<LocalLeader>fr` を押します。
3. コード直下に出力が表示されます。必要な行だけ試す場合は、Visual 選択して同じキーを押します。

```r
x <- mtcars

head(x)

plot(
  x$mpg, x$wt,
  xlab = "Miles per gallon",
  ylab = "Weight (1000 lbs)"
)

model <- lm(mpg ~ wt, data = x)
plot(model)
```

代入だけの式は通常テキストを出力しません。まず `x <- mtcars` を実行し、続いて `head(x)` や `plot(...)` を実行します。
`x` にカーソルを置いて `<LocalLeader>fk` を押すと summary が開き、`q` で閉じられます。
`model <- ...` を実行してから `plot(model)` を実行すると、4 枚の診断プロットが縦に並びます。

`pid` で外部セッションを指定しなければ、`arf headless` は最初の実行時に自動起動します。手動起動は不要です。バッファ全体を実行する場合は `<LocalLeader>fR` または `:ArfRunAll` を使います。

### Read longer output

実行した範囲にカーソルを置き、`<LocalLeader>fo` または `:ArfOutput` で保存済みテキストを開きます。再計算せずに、`/` で検索、`y` でコピー、`zl` / `zh` で横スクロール、`q` で閉じられます。

R 自身が省略した行・列や保存容量を超えた部分は読めません。[出力設定](doc/arf.txt)（`:help arf-output-settings`）を変更して再実行してください。

### Keymaps

プラグインは R バッファのキーバインドを自動登録しません。Installation の設定例では lazy.nvim を通じてキーを登録します。対応する操作は [Commands](#commands) を参照してください。

`<LocalLeader>` は `vim.g.maplocalleader` に従い、未設定ならバックスラッシュです。
上の設定例では `\fr` / `\fc` になります。カンマにする場合は、プラグインの読み込み前に設定します。

```lua
vim.g.maplocalleader = "," -- ,fr to run, ,fc to clear
```

キーは Installation の lazy.nvim `keys` や `vim.keymap.set()` で変更できます。Visual 用の `:ArfRun<CR>` は選択した行全体を渡します。

### Commands

Installation の設定例で使うキーとコマンドです。コマンドは手動でも実行できます。

| コマンド | 設定例のキー | 操作 |
| --- | --- | --- |
| `:ArfRun` | `<LocalLeader>fr` | 通常モードで現在の式、Visual モードで選択した行全体を実行。`:3,5ArfRun` なら指定した行全体を実行。 |
| `:ArfRunAll` | `<LocalLeader>fR` | 現在バッファのトップレベル式を順番に実行し、それぞれの直下に結果を表示。 |
| `:ArfClear` | `<LocalLeader>fc` | 現在バッファの出力・画像・サインを削除。R の変数は残します。 |
| `:ArfObjects` | — | 現在の R セッションのオブジェクトを検索して検査。 |
| `:ArfSummary` | `<LocalLeader>fk` | カーソル下のオブジェクトに `base::summary()` を実行してフロート表示。 |
| `:ArfOutput` | `<LocalLeader>fo` | カーソルを含む実行範囲の保存済み出力を開く。R は再実行しません。 |
| `:ArfCopyPlot` | `<LocalLeader>fy` | 直近に生成した保存済みプロット画像をクリップボードにコピー。 |
| `:ArfStop` | `<LocalLeader>fs` | 自動起動した arf を実行中でも終了し、全バッファの結果・サインを削除。次の実行は新しいセッションになります。`pid` 指定時は何も変更せず警告します。 |

`:ArfCopyPlot` は全バッファから直近のプロット結果を探し、その最後の画像をコピーします。削除・置換された結果はコピーしません。

### Object Picker

<p align="center">
  <img src="assets/object-picker.png" alt="ArfObjects で R オブジェクトの名前・クラス・次元を一覧表示" width="720">
  <br>
  <em>セッション内のオブジェクトを検索して選択。</em>
</p>

`:ArfObjects` または `require("arf").objects()` で、現在のセッションの `.GlobalEnv` にあるオブジェクトを Snacks.picker で検索できます。名前・クラス・次元（または長さ）を表示します。Snacks.picker が必要です。

- 挿入モードで名前を fuzzy search、`<CR>` で `summary()`。`<Esc>` で通常モードへ移ります。
- 通常モードで `p` は `print()`、`r` は一覧の再取得、`q` は終了。
- 結果は既存のフロートに表示します。`ArfOutput` の保存済み出力とは別です。
- 一覧は Picker を開いた時点の内容です。ドットで始まる名前は表示しません。

### Object inspection

<p align="center">
  <img src="assets/object-summary.png" alt="線形モデルの summary(model) をフロートで表示" width="720">
  <br>
  <em>モデルの要約を、コードを離れずに確認。</em>
</p>

カーソル下のオブジェクトに R 関数を実行し、テキスト出力をフロートで確認できます。キーマップには次のように設定します。

```lua
-- 上の lazy.nvim 設定の keys テーブルに追加します。
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

先に対象オブジェクトを作る式を実行してから、その名前にカーソルを置いてください。

オブジェクト確認（summary を含む）はカーソル下の名前（ドットを含む）をグローバル環境から継承先も含めて検索します。`df$column` や添字式、空白・演算子を含む名前全体は評価せず、`column` 上では独立した名前として検索します。

`inspect(fn, opts)` には ASCII の R 関数名、または公開された `package::function` を指定します。R コードは `{ r = [[ ... ]] }` で明示的に指定できます。パッケージは事前にインストールしてください。`library()` は不要です。画像は表示しません。

`title` は省略可能で、既定は `summary(x)` のような `関数名(オブジェクト名)`、`{ r = ... }` の場合は `inspect(オブジェクト名)` です。

関数にはカーソル下のオブジェクトを一つ渡します。追加引数が必要なら R の無名関数を指定できます。エラーはフロートに表示します。

```lua
require("arf").inspect({
  r = [[
    function(x) {
      stats::confint(x, level = 0.90)
    }
  ]],
}, { title = "90% confidence interval" })
```

文字列には信頼できる R コードを指定してください。既存の R セッションで定義した関数も `inspect("inspect_ci")` のように名前で指定できます。

### Execution and sessions

- 式の自動判定にはバッファ全体の構文が完全である必要があります。関数・ループ内では定義・ループ全体を選び、同じ行の複数式はカーソル位置で選びます。式の外の空行・コメントは実行対象外です。
- `ArfRun` / `ArfRunAll` は式ごとの経過時間（Wall-clock time）を表示します。IPC 通信・結果処理を含み、初回セッションの起動時間は除きます。
- `ArfRunAll` は既存セッションで上から逐次実行し、最初の R エラー・IPC 失敗で停止します。完了済み・未到達の既存結果は残ります。`:%ArfRun` は全体を一つの範囲として評価し、結果を末尾にまとめます。
- 結果は実行範囲の直下に表示します。コードを編集しても直前の結果を薄い色で保持し、実行済みサインを外します。再実行すると結果を置き換え、範囲全体を削除すると結果も削除します。他の範囲の結果は自動更新しないため、元データや変数を変えたら依存する式も再実行してください。
- 評価待ちに実行元バッファを編集・クリア・破棄すると、進行中の結果を破棄し、後続の実行を打ち切ります。R の評価自体は中断しません。
- 同じ Neovim 内の全バッファは、一つの R セッションを共有します。自動起動時の作業ディレクトリは最初の評価時の `:pwd` で、後の `:cd` は反映しません。外部セッションは既存の作業ディレクトリを使います。Neovim 終了時は自動起動したセッションだけを停止します。

詳細な設定・Lua API・ハイライト・旧設定名からの移行は、[ヘルプ](doc/arf.txt)（`:help arf`）を参照してください。

## Configuration

変更したい項目だけ `opts` に指定してください。`signs` の内部も項目単位で変更できます。
`setup()` を再度呼ぶ場合は、それまでの設定に指定項目をマージします。

<details>
<summary>全設定と既定値</summary>

```lua
require("arf").setup({
  theme = "default",          -- "default", "auto", or "neon"

  -- arf / R session
  executable = "arf",         -- Command name or executable path
  pid = nil,                  -- nil: start a session; number: use an existing session
  startup_timeout = 10000,    -- Session startup timeout in milliseconds
  eval_timeout = 300000,      -- IPC response timeout in milliseconds

  -- Image display limits in terminal cells
  image_max_width = 100,      -- Maximum columns
  image_max_height = 30,      -- Maximum rows

  -- PNG generated by R
  plot_width_px = 1200,       -- Width in pixels
  plot_height_px = 800,       -- Height in pixels
  plot_dpi = 180,             -- DPI; also affects text and line sizes

  -- Output display and retention
  tibble_max_rows = false,    -- Set a positive integer to override tibble row printing
  tibble_width = "auto",      -- false, "auto", positive integer, or "all"
  inline_max_lines = 20,      -- Inline body lines, excluding notices and images
  output_max_bytes = 1048576, -- Retained bytes per run, including errors (1 MiB)
  -- Shared by ArfOutput and object inspections
  float_width = "60%",        -- "auto", positive integer, or "1%" to "100%"
  float_max_height = 30,      -- Maximum rows; shrinks for short output

  -- Execution signs
  signs = {
    enabled = true,           -- Set false to hide all execution signs
    priority = 5,             -- Higher values take precedence
    range = { text = "│", hl = "ArfSignRange" },
    success = { text = "│", hl = "ArfSignSuccess" },
    error = { text = "│", hl = "ArfSignError" },
    running = {
      text = "…",             -- Initial symbol; also used when animation is disabled
      hl = "ArfSignRunning",
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      interval = 80,          -- Frame interval in milliseconds
    },
  },
})
```

</details>

各オプションの詳細は、[ヘルプ](doc/arf.txt)（`:help arf-configuration`）を参照してください。

## Limitations

- 評価は一度に一つです。`ArfRunAll` 全体を通して追加実行・オブジェクト確認を拒否します。出力は各評価の完了後に表示し、逐次表示・中断後の再開には対応しません。
- 結果は行範囲ごとに管理します。同じ行にある別の式を実行しても、以前の結果を置き換えます。
- 結果のセッション間保存・復元は未対応です。テキストの保持上限は評価ごとで、全結果の合計容量・画像枚数・画像の合計容量には上限を設けていません。
- stdout の後に stderr を表示するため、両者の出現順序は保持しません。

## Troubleshooting

- **画像が出ない**：`:checkhealth snacks` で依存とターミナル認識を確認してください。`:echo executable('magick')` または `:echo executable('identify')` が `1` ならコマンドを検出できています。
- **式を実行できない**：R の Tree-sitter パーサーとバッファ内の構文を確認してください。Visual 選択・`:3,5ArfRun` はパーサーなしでも使えます。
- **キーが効かない**：`keys` 設定を追加したこと、バッファの filetype が `r` であること、キー登録前に `maplocalleader` を設定したことを確認してください。
- **出力の続きが見えない**：実行したコードの範囲にカーソルを置いて `:ArfOutput` を開いてください。tibble 自身の省略や保存容量の超過は、[出力設定](doc/arf.txt)（`:help arf-output-settings`）を変更して再実行する必要があります。
- **`object not found` と出る**：変数を作る式を先に実行してください。`:ArfStop` 後のセッションには以前の変数がありません。
- **相対パスでファイルが見つからない**：R で `getwd()` を実行して確認してください。起動後の Neovim の `:cd` は R に反映されないため、R 側で `setwd()` するか、自動起動したセッションを `:ArfStop` して作業ディレクトリを変更後に再実行します。
- **計算が終わらない**：`:ArfStop` で自動起動したセッションを終了できます。R の変数は失われます。`pid` 指定の外部セッションは、そのセッション側で停止してください。

## Project philosophy

自分の R 作業のために、AI と vibe coding で作りました。必要な機能は揃ったので、今後も小さく保つ方針です。追加機能が欲しい場合は、気軽に fork して育ててください。

## License

[MIT ライセンス](LICENSE) © 2026 topazape.
