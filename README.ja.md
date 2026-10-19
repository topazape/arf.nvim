# arf.nvim

<p align="center">
  <img src="assets/logo.png" alt="arf.nvim logo" width="560">
</p>

[English](README.md) | 日本語

**R のコードと実行結果を、Neovim の同じバッファで。**

[arf](https://github.com/eitsupi/arf) をバックエンドに使う Neovim プラグインです。
`.R` ファイルから式を実行し、テキストとプロットをコード直下に表示します。ソースコードには出力を書き込みません。

[Features](#features) · [Requirements](#requirements) · [Installation](#installation) · [Usage](#usage) · [Configuration](#configuration) · [API](#api) · [Highlights](#highlights) · [Troubleshooting](#troubleshooting)

## Features

- **式単位で実行** — Tree-sitter でパイプ・ggplot・関数定義の範囲を判定。Visual 選択にも対応。
- **インライン出力** — テキストとプロットを表示し、別の場所の結果も保持。
- **継続する R セッション** — 初回実行で自動起動。代入したオブジェクトを次の実行で利用。
- **出力を読み返す** — 保存済み出力とエラーを、検索・コピーできるフロートで表示。
- **オブジェクトを確認** — カーソル下のオブジェクトに `summary()` や指定した R 関数を実行。
- **状態が見える** — 実行中・成功・エラーをサインで表示。記号と色をカスタマイズ可能。

## Requirements

- **Neovim 0.12+**
- **Nerd Font** — 既定の成功・エラーアイコンに使用。通常の Unicode 記号に変更する場合は不要です（[Signs](#signs)）。
- **R と [arf](https://github.com/eitsupi/arf)** — arf の導入手順に従ってインストールし、`arf` を PATH に通してください。実行ファイルのパスも設定できます。arf 0.6.0 で検証済み。
- **R の Tree-sitter パーサー** — `ArfRun` の通常モードの式判定と `ArfRunAll` に使用。利用中のパーサーマネージャーで `r` を導入してください。Visual 選択・明示的な行範囲の実行には不要です。

画像表示には、次も必要です。

- [snacks.nvim](https://github.com/folke/snacks.nvim) — `image` を有効にしてください。2.31.0 の配置 API で検証済み。
- **Ghostty / Kitty など** — Kitty Graphics Protocol のインライン画像に対応したターミナル。
- **ImageMagick** — 使用中の Snacks の実装では、PNG も `magick identify` または `identify` を使います。

## Installation

### lazy.nvim

次の spec を lazy.nvim の設定に追加してください。

```lua
return {
  "topazape/arf.nvim",
  ft = "r",
  cmd = { "ArfRun", "ArfRunAll", "ArfClear", "ArfSummary", "ArfOutput", "ArfStop" },
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
    { "<LocalLeader>fk", "<Cmd>ArfSummary<CR>", ft = "r", desc = "Show R object summary" },
  },
}
```

Snacks を既に設定している場合は、その設定に `image = { enabled = true }` を追加してください。
テキスト出力だけを使う場合は `dependencies` を省略できます。
上の設定では、R ファイルを開いたときに lazy.nvim がプラグインを読み込み、指定したキーを登録します。

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
```

まず `x <- mtcars` を実行し、続いて `head(x)` や `plot(...)` を実行します。
`x` にカーソルを置いて `<LocalLeader>fk` を押すと summary が開き、`q` で閉じられます。

`pid` で外部セッションを指定しなければ、`arf headless` は最初の実行時に自動起動します。手動起動は不要です。バッファ全体を実行する場合は `<LocalLeader>fR` または `:ArfRunAll` を使います。

### Keymaps

プラグインは R バッファのキーバインドを自動登録しません。Installation の設定例では、lazy.nvim を通じて次のキーを登録します。フロート内の `q` はプラグインが登録します。

| キー | モード | 対象 | 操作 |
| --- | --- | --- | --- |
| `<LocalLeader>fr` | 通常 | R バッファ | カーソルを含むトップレベルの式を実行。 |
| `<LocalLeader>fr` | Visual | R バッファ | 選択した行全体を実行。 |
| `<LocalLeader>fR` | 通常 | R バッファ | 全トップレベル式を上から順に実行。 |
| `<LocalLeader>fc` | 通常 | R バッファ | 現在バッファの結果をクリア。R の変数は維持。 |
| `<LocalLeader>fs` | 通常 | R バッファ | 所有する R セッションを停止し、すべての結果をクリア。 |
| `<LocalLeader>fo` | 通常 | R バッファ | カーソル位置の保存済み出力を表示。 |
| `<LocalLeader>fk` | 通常 | R バッファ | カーソル下のオブジェクトの summary を表示。 |
| `q` | 通常 | arf フロート | フロートを閉じる。 |

`<LocalLeader>` は `vim.g.maplocalleader` に従い、未設定ならバックスラッシュです。
上の設定例では `\fr` / `\fc` になります。カンマにする場合は、プラグインの読み込み前に設定します。

```lua
vim.g.maplocalleader = "," -- ,fr to run, ,fc to clear
```

キーは lazy.nvim の `keys`（各項目に `ft = "r"` を指定）や `vim.keymap.set()` で設定できます。以前の自動登録から移行する場合は、Installation の `keys` 設定を追加し、廃止した `default_keymaps` オプションを削除してください。

Installation の `keys` を変更して好きなキーを設定できます。Visual 用の `:ArfRun<CR>` は選択行を渡します。

### Commands

設定例のキーバインドは次のコマンドを呼びます。コマンドは手動でも実行できます。

| コマンド | 操作 |
| --- | --- |
| `:ArfRun` | 現在の式を実行。`:3,5ArfRun` なら指定した行全体を実行。 |
| `:ArfRunAll` | 現在バッファのトップレベル式を順番に実行し、それぞれの直下に結果を表示。 |
| `:ArfClear` | 現在バッファの出力・画像・サインを削除。 |
| `:ArfSummary` | カーソル下のオブジェクトに `base::summary()` を実行してフロート表示。 |
| `:ArfOutput` | カーソルを含む実行範囲の保存済み出力を開く。R は再実行しません。`/` で検索、`y` でコピーできます。 |
| `:ArfStop` | 自動起動した arf を実行中でも終了し、全バッファの結果・サインを削除。次の実行は新しいセッションになります。 |

### Object inspection

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

`inspect(fn, opts)` には ASCII の R 関数名、または公開された `package::function` を指定します。任意の R 式には対応しません。パッケージは事前にインストールしてください。`library()` は不要です。画像は表示しません。

`title` は省略可能で、既定は `関数名(オブジェクト名)` です。`base::summary` の場合は `summary(オブジェクト名)` になります。

渡す引数はカーソル下のオブジェクト一つです。追加引数が必要なら、R セッションでラッパー関数を定義・実行し、`inspect("inspect_ci")` のように指定します。

```r
inspect_ci <- function(x) stats::confint(x, level = 0.90)
```

### Execution and sessions

- 式の自動判定にはバッファ全体の構文が完全である必要があります。関数・ループ内では定義・ループ全体を選び、同じ行の複数式はカーソル位置で選びます。式の外の空行・コメントは実行対象外です。
- `ArfRunAll` は既存セッションで上から逐次実行し、最初の R エラー・IPC 失敗で停止します。完了済み・未到達の既存結果は残ります。`:%ArfRun` は全体を一つの範囲として評価し、結果を末尾にまとめます。
- 結果は実行範囲の直下に表示し、重なる範囲の再実行や範囲内の編集で置き換え・削除します。
- 評価待ちに実行元バッファを編集・クリア・破棄すると、進行中の結果を破棄し、後続の実行を打ち切ります。R の評価自体は中断しません。
- R セッションは Neovim ごとに一つで、初回実行時の `:pwd` を使います。後の `:cd` は R に反映しません。終了時は自動起動したセッションだけを停止します。

## Configuration

変更したい項目だけ `opts` に指定してください。`signs` の内部も項目単位で変更できます。
`setup()` を再度呼ぶ場合は、それまでの設定に指定項目をマージします。

<details>
<summary>全設定と既定値</summary>

```lua
require("arf").setup({
  -- arf / R session
  executable = "arf",        -- Command name or executable path
  pid = nil,                 -- nil: start a session; number: use an existing session
  startup_timeout = 10000,    -- Session startup timeout in milliseconds
  timeout = 300000,           -- IPC response timeout in milliseconds

  -- Image display limits in terminal cells
  image_width = 100,          -- Maximum columns
  image_height = 30,          -- Maximum rows

  -- PNG generated by R
  plot_width = 1200,          -- Width in pixels
  plot_height = 800,          -- Height in pixels
  plot_res = 180,             -- DPI; also affects text and line sizes

  -- Inspection floats (including summary)
  summary_width = 120,        -- Columns, including for short output
  summary_max_height = 20,    -- Maximum rows; shrinks for short output

  -- Output display and retention
  output_max_lines = 20,      -- Inline body lines, excluding notices and images
  output_max_bytes = 1048576, -- Retained bytes per run, including errors (1 MiB)
  output_width = 120,         -- Saved-output float width in columns
  output_max_height = 30,     -- Saved-output float maximum height in rows

  -- Execution signs
  signs = {
    enabled = true,           -- Set false to hide all execution signs
    priority = 5,             -- Higher values take precedence
    range = { text = "│", hl = "ArfSignRange" },
    success = { text = "", hl = "ArfSignSuccess" },
    error = { text = "", hl = "ArfSignError" },
    running = {
      text = "…",            -- Initial symbol; also used when animation is disabled
      hl = "ArfSignRunning",  -- Also applies to range markers during execution
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      interval = 80,          -- Frame interval in milliseconds
    },
  },
})
```

</details>

### Session

- `executable`：コマンド名または実行ファイルのパス。起動済みセッションの実行ファイルを変える場合は `ArfStop` 後に再実行します。
- `pid`：省略時は自動起動。既存セッションを使う場合は `arf ipc list` で調べた PID を数値で指定します。
- `startup_timeout`：起動待機時間。起動失敗・タイムアウト後は次の実行で再試行します。
- `timeout`：各評価の IPC 応答の待機時間。`ArfRunAll` 全体の制限時間ではありません。タイムアウトだけでは R の計算は止まりません。所有するセッションを止める場合は `ArfStop` を使ってください。`pid` を明示した場合、`ArfStop` は評価の停止も結果のクリアも行いません。外部セッションは別途管理してください。

### Plots

`image_width` / `image_height` は表示上限（セル）、`plot_width` / `plot_height` / `plot_res` は生成 PNG の幅・高さ（px）・解像度（dpi）です。表示サイズはウィンドウにも制限されます。

PNG 設定は正の整数で指定し、変更後は再実行してください。`plot_res` は文字・線の大きさにも影響します。ピクセル数と DPI を同じ比率で増やすと、表示サイズを変えず画質だけが上がる場合があります。

### Output and floats

| 設定項目 | 説明 |
| --- | --- |
| `output_max_lines` | インラインに表示する本文の最大行数。既定は 20 行で、残りは「ほか N 行」と表示します。省略案内と画像は別枠です。 |
| `output_max_bytes` | 1 回の実行で保持する stdout・stderr・エラー本文の合計上限。既定は 1 MiB。超過分は破棄し、その旨を表示します。画像はこの上限に含みません。 |
| `output_width` / `output_max_height` | `ArfOutput` のフロートの幅と最大高さ。 |
| `summary_width` / `summary_max_height` | summary を含むすべての確認用フロートの幅と最大高さ。 |

正の整数で指定します。フロートは画面内に収め、短い出力では高さを縮めます。

- `output_max_lines` は次の表示更新、`output_max_bytes` は再実行、フロート寸法は開き直しで反映します。
- 保持上限は run-all の各式・各オブジェクト確認に適用します。確認用フロートにも省略案内を表示します。
- 捨てた本文・削除した結果は復元できません。上限は R の計算・メモリ・捕捉中の一時ファイル容量を制限しません。

### Signs

既定の記号は範囲 `│`、成功 ``、エラー `` です。端末のフォントに Nerd Font を設定してください。`nvim-web-devicons` は不要です。
記号は `signs.range.text` / `signs.success.text` / `signs.error.text` / `signs.running.text` でそれぞれ指定できます。

| 設定項目 | 説明 |
| --- | --- |
| `signs.enabled = false` | すべての実行サインを非表示にします。 |
| `signs.range.text = ""` | 範囲内の縦線を消し、最終行だけ表示します。 |
| 各 `text` | 幅 1〜2 セルの記号、または非表示用の空文字を指定します。 |
| 各 `hl` | ハイライトグループ名。色の変更は [Highlights](#highlights) を参照してください。 |
| `signs.priority` | 非負の整数。大きい値を優先します。既定は 5。 |
| `signs.running.frames` | 実行中に順番に表示する記号のリスト。各コマも幅 1〜2 セルにします。2 コマ以上ならアニメーションし、空リスト `{}` または 1 コマなら `running.text` の静止表示です。 |
| `signs.running.interval` | 更新間隔の正の整数（ミリ秒）。既定は 80。 |

Nerd Font を使わない場合は、`text` を通常の Unicode 記号に変更できます。

```lua
require("arf").setup({
  signs = {
    range = { text = "│" },
    success = { text = "✓" },
    error = { text = "✗" },
  },
})
```

スピナーは標準の Unicode 記号で回転します。実行中の最終行だけを更新し、完了・エラー・停止・クリア・実行範囲内の編集・バッファ破棄時にはタイマーを終了します。
`running.text = ""` なら最終行の記号とアニメーションを非表示にします。追加のアイコンプラグインへの依存はありません。

実行中の縦線には `signs.running.hl` を適用します。設定変更は次の実行から反映されます。
サインが見えない場合は `:set signcolumn=yes` を確認してください。

## API

コマンド・独自キーから使える Lua API です。

```lua
local arf = require("arf")

arf.run()          -- Run the top-level expression containing the cursor
arf.run_all()      -- Run all top-level expressions in the current buffer in order
arf.run(3, 5)       -- Run complete lines 3–5 (1-based, inclusive)
arf.clear()        -- Clear current-buffer results, images, and signs; keep R objects
arf.clear(bufnr)   -- Clear a buffer; 0 means the current buffer
arf.inspect(fn, opts) -- Call an R function on the object under the cursor; opts.title is optional
arf.summary()        -- Shorthand for arf.inspect("base::summary")
arf.output()       -- Show saved output at the cursor without evaluating R again
arf.stop()         -- Terminate the owned session and clear results in all buffers
```

`run`・`run_all`・`inspect`・短縮形の `summary` の R 評価は非同期です。独自キーマップとタイトル指定は [Object inspection](#object-inspection) を参照してください。
`clear` は実行中の R 自体を中断しません。終了させる場合は `stop` を使ってください。
`setup(opts)` の全設定と既定値は [Configuration](#configuration) を参照してください。

## Highlights

出力・フロート・サインは、以下のすべての専用ハイライトグループで色を設定できます。
色の設定は `opts` ではなく、Neovim の `nvim_set_hl()` を使います。

| グループ | 用途 | 既定 |
| --- | --- | --- |
| `ArfOutput` | 通常出力 | `Normal` の文字色を RGB 各成分で 15% 暗くした色 |
| `ArfSeparator` | コードとインライン出力を表示幅いっぱいに区切る罫線 | `NonText` |
| `ArfMessage` | `message()` やパッケージ起動時のメッセージ | `DiagnosticInfo` |
| `ArfStderr` | その他の stderr（警告や stderr への直接出力） | `DiagnosticWarn` |
| `ArfFloatNormal` | 確認用・出力フロートの本文と背景 | `NormalFloat` |
| `ArfFloatBorder` | 確認用・出力フロートの枠 | `FloatBorder` |
| `ArfFloatTitle` | 確認用・出力フロートのタイトル | `FloatTitle` |
| `ArfSignRunning` | 実行中の範囲 | `DiagnosticInfo` |
| `ArfError` | 実行エラー | `DiagnosticError` |
| `ArfWarning` | 画像表示などの案内 | `DiagnosticWarn` |
| `ArfSignRange` | 実行範囲の `│` | `ArfOutput` |
| `ArfSignSuccess` | 実行成功のマーク | `DiagnosticOk` |
| `ArfSignError` | 実行エラーのマーク | `DiagnosticError` |

カラースキーム変更時にも既定の色とリンクを設定します。既に定義された色は上書きしません。
好みの色に変更する場合は、Neovim 設定に次のように追加できます。

```lua
local function arf_colors()
  vim.api.nvim_set_hl(0, "ArfOutput", { fg = "#a6adc8" })
  vim.api.nvim_set_hl(0, "ArfSignSuccess", { fg = "#a6e3a1" })
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = arf_colors })
arf_colors()
```

画像のプレースホルダーは Snacks が管理する色を使います。arf フロートの配色は、そのフロートだけの `winhighlight` で適用します。

## Limitations

- 評価は一度に一つ。`ArfRunAll` 全体を通して追加実行・オブジェクト確認は拒否します。出力は各評価の完了後に表示し、実行中の逐次表示・中断後の再開は未対応です。
- 画像は各評価の最後の 1 枚のみ。run-all は式ごとに表示しますが、同じ行など範囲が重なる結果は置き換わります。
- オブジェクト確認（summary を含む）はカーソル下の名前（ドットを含む）をグローバル環境から継承先も含めて検索します。`df$column` や添字式、空白・演算子を含む名前全体は評価せず、`column` 上では独立した名前として検索します。
- 結果のセッション間保存・復元は未対応。出力上限は評価ごとで、全結果の合計容量は制限しません。
- stdout の後に stderr を表示するため、両者の出現順序は保持しません。通知・案内文は英語、R の出力は R 側の言語設定に従います。

## Troubleshooting

- **画像が出ない**：`:checkhealth snacks` で依存とターミナル認識を確認してください。`:echo executable('magick')` または `:echo executable('identify')` が `1` ならコマンドを検出できています。
- **式を実行できない**：R の Tree-sitter パーサーとバッファ内の構文を確認してください。Visual 選択・`:3,5ArfRun` はパーサーなしでも使えます。
- **キーが効かない**：`keys` 設定を追加したこと、バッファの filetype が `r` であること、キー登録前に `maplocalleader` を設定したことを確認してください。
- **計算が終わらない**：`:ArfStop` で自動起動したセッションを終了できます。R の変数は失われます。

## Project philosophy

自分の R 作業のために、AI と vibe coding で作りました。必要な機能は揃ったので、今後も小さく保つ方針です。追加機能が欲しい場合は、気軽に fork して育ててください。

## License

[MIT ライセンス](LICENSE) © 2026 topazape.
