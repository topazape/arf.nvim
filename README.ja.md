# arf.nvim

<p align="center">
  <img src="assets/logo.png" alt="arf.nvim logo" width="560">
</p>

[English](README.md) | 日本語

**R のコードと実行結果を、Neovim の同じバッファで。**

[arf](https://github.com/eitsupi/arf) をバックエンドに使う Neovim プラグインです。
`.R` ファイルから式を実行し、テキストとプロットをコード直下に表示します。ソースコードには出力を書き込みません。

[Features](#features) · [Requirements](#requirements) · [Installation](#installation) · [Usage](#usage) · [Configuration](#configuration) · [API](#api) · [Highlights](#highlights) · [Limitations](#limitations) · [Troubleshooting](#troubleshooting)

<p align="center">
  <img src="assets/screenshot.png" alt="arf.nvim で R コード、tibble の出力、ggplot の散布図を Neovim 内に表示" width="720">
</p>

## Features

- **式単位・バッファ全体を実行** — Tree-sitter でパイプ・ggplot・関数定義の範囲を判定。Visual 選択・行範囲にも対応。
- **インライン出力** — テキストとプロットをコード直下に表示。複数の画像は生成順に縦に並べ、別の範囲の結果も保持。
- **継続する R セッション** — 初回実行で自動起動。代入したオブジェクトを次の実行で利用。
- **長い出力を読み返す** — コードの横では短く表示し、続きを `ArfOutput` で検索・コピー。tibble の出力行数も設定可能。
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
  version = "*",
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

model <- lm(mpg ~ wt, data = x)
plot(model)
```

代入だけの式は通常テキストを出力しません。まず `x <- mtcars` を実行し、続いて `head(x)` や `plot(...)` を実行します。
`x` にカーソルを置いて `<LocalLeader>fk` を押すと summary が開き、`q` で閉じられます。
`model <- ...` を実行してから `plot(model)` を実行すると、4 枚の診断プロットが縦に並びます。

`pid` で外部セッションを指定しなければ、`arf headless` は最初の実行時に自動起動します。手動起動は不要です。バッファ全体を実行する場合は `<LocalLeader>fR` または `:ArfRunAll` を使います。

### Read longer output

実行した範囲にカーソルを置き、`<LocalLeader>fo` または `:ArfOutput` で保存済みテキストを開きます。再計算せずに、`/` で検索、`y` でコピー、`zl` / `zh` で横スクロール、`q` で閉じられます。

R 自身が省略した行・列や保存容量を超えた部分は読めません。[出力設定](#output-and-floats)を変更して再実行してください。

`:ArfClear` は表示だけを消し、R の変数を残します。変数も含めてやり直す場合は `:ArfStop` で自動起動したセッションを終了し、必要な式を再実行してください。外部セッションは別途終了します。

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
| `:ArfSummary` | `<LocalLeader>fk` | カーソル下のオブジェクトに `base::summary()` を実行してフロート表示。 |
| `:ArfOutput` | `<LocalLeader>fo` | カーソルを含む実行範囲の保存済み出力を開く。R は再実行しません。 |
| `:ArfStop` | `<LocalLeader>fs` | 自動起動した arf を実行中でも終了し、全バッファの結果・サインを削除。次の実行は新しいセッションになります。`pid` 指定時は何も変更せず警告します。 |

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

先に対象オブジェクトを作る式を実行してから、その名前にカーソルを置いてください。

オブジェクト確認（summary を含む）はカーソル下の名前（ドットを含む）をグローバル環境から継承先も含めて検索します。`df$column` や添字式、空白・演算子を含む名前全体は評価せず、`column` 上では独立した名前として検索します。

`inspect(fn, opts)` には ASCII の R 関数名、または公開された `package::function` を指定します。R コードは `{ r = [[ ... ]] }` で明示的に指定できます。パッケージは事前にインストールしてください。`library()` は不要です。画像は表示しません。

`title` は省略可能で、既定は `関数名(オブジェクト名)` です。`base::summary` の場合は `summary(オブジェクト名)` になります。

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

`{ r = ... }` の既定タイトルは `inspect(オブジェクト名)` です。文字列には信頼できる R コードを指定してください。既存の R セッションで定義した関数も `inspect("inspect_ci")` のように使えます。

### Execution and sessions

- 式の自動判定にはバッファ全体の構文が完全である必要があります。関数・ループ内では定義・ループ全体を選び、同じ行の複数式はカーソル位置で選びます。式の外の空行・コメントは実行対象外です。
- `ArfRunAll` は既存セッションで上から逐次実行し、最初の R エラー・IPC 失敗で停止します。完了済み・未到達の既存結果は残ります。`:%ArfRun` は全体を一つの範囲として評価し、結果を末尾にまとめます。
- 結果は実行範囲の直下に表示します。コードを編集しても直前の結果を薄い色で保持し、実行済みサインを外します。再実行すると結果を置き換え、範囲全体を削除すると結果も削除します。他の範囲の結果は自動更新しないため、元データや変数を変えたら依存する式も再実行してください。
- 評価待ちに実行元バッファを編集・クリア・破棄すると、進行中の結果を破棄し、後続の実行を打ち切ります。R の評価自体は中断しません。
- 同じ Neovim 内の全バッファは、一つの R セッションを共有します。自動起動時の作業ディレクトリは最初の評価時の `:pwd` で、後の `:cd` は反映しません。外部セッションは既存の作業ディレクトリを使います。Neovim 終了時は自動起動したセッションだけを停止します。

## Configuration

変更したい項目だけ `opts` に指定してください。`signs` の内部も項目単位で変更できます。
`setup()` を再度呼ぶ場合は、それまでの設定に指定項目をマージします。

<details>
<summary>全設定と既定値</summary>

```lua
require("arf").setup({
  theme = "default",         -- "default", "auto", or "neon"

  -- arf / R session
  executable = "arf",        -- Command name or executable path
  pid = nil,                 -- nil: start a session; number: use an existing session
  startup_timeout = 10000,    -- Session startup timeout in milliseconds
  eval_timeout = 300000,       -- IPC response timeout in milliseconds

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
  float_width = "80%",       -- "auto", positive integer, or "1%" to "100%"
  float_max_height = 30,     -- Maximum rows; shrinks for short output

  -- Execution signs
  signs = {
    enabled = true,           -- Set false to hide all execution signs
    priority = 5,             -- Higher values take precedence
    range = { text = "│", hl = "ArfSignRange" },
    success = { text = "", hl = "ArfSignSuccess" },
    error = { text = "", hl = "ArfSignError" },
    running = {
      text = "…",            -- Initial symbol; also used when animation is disabled
      hl = "ArfSignRunning",
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
      interval = 80,          -- Frame interval in milliseconds
    },
  },
})
```

</details>

### Session

- `executable`：コマンド名または実行ファイルのパス。起動済みセッションの実行ファイルを変える場合は `ArfStop` 後に再実行します。
- `pid`：省略時は自動起動。既存セッションを使う場合は `arf ipc list` で調べた PID を数値で指定します。外部セッションの起動・終了・作業ディレクトリは別途管理してください。`ArfStop` は停止も結果のクリアも行いません。
- `startup_timeout`：起動待機時間。起動失敗・タイムアウト後は次の実行で再試行します。
- `eval_timeout`：各評価の IPC 応答の待機時間。`ArfRunAll` 全体の制限時間ではありません。タイムアウトだけでは R の計算は止まりません。所有するセッションを止める場合は `ArfStop` を使ってください。外部セッションの評価は別途停止してください。

### Plots

画像は生成順に縦に表示します。`image_max_width` / `image_max_height` は画像ごとの表示上限（セル）、`plot_width_px` / `plot_height_px` / `plot_dpi` は生成 PNG の幅・高さ（px）・解像度（dpi）です。表示サイズはウィンドウにも制限されます。

PNG 設定は正の整数で指定し、変更後は再実行してください。ピクセル数と DPI を同じ比率で増やすと、文字や線の表示サイズを保ったまま画質を上げられる場合があります。

### 設定名の変更

既存の設定は以下の名前に変更してください。

- `output_max_lines` → `inline_max_lines`
- `output_width` / `inspect_width` → `float_width`
- `output_max_height` / `inspect_max_height` → `float_max_height`
- `image_width` / `image_height` → `image_max_width` / `image_max_height`
- `plot_width` / `plot_height` / `plot_res` → `plot_width_px` / `plot_height_px` / `plot_dpi`
- `timeout` → `eval_timeout`
- `tibble_width = math.huge` → `tibble_width = "all"`

旧設定名を指定すると、移行先を示すエラーになります。tibble の幅は既定で `"auto"`、フロートの幅は `"80%"`、両フロートの最大高さは共通で30行です。行数設定は tibble にのみ適用されます。有限の幅を指定すると R の `width` も一時設定するため、通常の data.frame などの出力幅にも影響します。

### Output and floats

lazy.nvim の `opts` で、R が生成する行数とインラインの表示行数を別々に設定できます。

```lua
opts = {
  tibble_max_rows = 100,
  tibble_width = "auto",
  inline_max_lines = 20,
}
```

この例では tibble を最大 100 行分出力し、先頭 20 行をインラインに表示します。続きは `:ArfOutput` で読めます。

- `inline_max_lines`：インラインの本文行数。区切り線・省略案内・画像は含みません。
- `tibble_max_rows`：tibble の最大出力行数。既定の `false` は R 側の設定を維持します。個別に指定するなら `print(df, n = 100)`、列の省略も避けるなら `print(df, n = 100, width = Inf)` を使います。明示的な `n` が優先されます。
- `output_max_bytes`：評価ごとの保存容量（既定 1 MiB）。stdout・stderr・エラー本文が対象で、画像は含みません。保存容量超過の案内が出たら、増やして再実行してください。R のメモリ使用量は制限しません。
- `tibble_width`：`false` は R 側の設定を維持、`"auto"` は実行開始時のソースウィンドウの本文幅（行番号などを除く）、正の整数は文字幅の指定、`"all"` は全列出力です。有限の幅では一段で表示し、収まらない列は省略します。`"all"` は tibble によって複数段に分かれる場合があります。明示的な `print(..., width = ...)` が優先されます。ウィンドウ幅を変更した場合は再実行が必要です。
- `float_width` / `float_max_height`：保存済み出力・summary などのオブジェクト確認に共通のフロートサイズ。`float_width = "auto"` は開く時点のエディタ幅から枠と余白を引いた幅、正の整数は文字幅、`"90%"` などの文字列はエディタ全体の幅に対する割合（整数の1〜100%）の指定です。割合は開くたびに計算し、小数点以下を切り捨てます。画面内に収まり、短い出力では高さが縮みます。画像はインラインだけに表示します。

数値は正の整数で指定します。`inline_max_lines` は次の表示更新、フロートのサイズは開き直したときに反映されます。`tibble_max_rows`・`tibble_width`・`output_max_bytes` の変更には再実行が必要です。

`tibble_max_rows` と `tibble_width` はオブジェクト確認にも適用されます。評価中は `pillar.print_max` / `pillar.print_min` / `pillar.width`（有限の幅では R の `width` も）を一時設定し、評価後に元の値へ戻します。R コード内で変更した場合も同様です。

### Signs

記号は `signs.range.text` / `signs.success.text` / `signs.error.text` / `signs.running.text` で指定できます。既定の成功・エラー記号には Nerd Font が必要です。

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

スピナーは実行中の最終行に表示します。`signs.running.text = ""` で非表示にできます。設定変更は次の実行から反映されます。サインが見えない場合は `:set signcolumn=yes` を確認してください。

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

出力・フロート・サインの既定配色は `theme` で選択できます。

- `"default"`（既定）：グレーを基調に、控えめな状態色を使う配色。
- `"auto"`：現在のカラースキームに合わせる配色。
- `"neon"`：紫の背景と鮮やかな文字・状態色を使う配色。

`default` と `neon` は `background` に応じてダーク・ライトを切り替えます。変更するのは arf のハイライトだけです。

```lua
require("arf").setup({ theme = "default" })
-- カラースキームに合わせるなら "auto"、ネオン配色なら "neon"。
```

`setup()` で即座に切り替わり、`ColorScheme` / `background` 変更時にも再適用します。独自の `Arf*` 設定は保持します。個別の色は setup 後に `nvim_set_hl()` で変更してください。以下は `"auto"` の既定値です。

| グループ | 用途 | auto の既定 |
| --- | --- | --- |
| `ArfOutput` | 通常出力 | `Normal` の文字色に背景色を 15% ブレンドした色 |
| `ArfOutputStale` | コード編集後の通常出力 | `Normal` の文字色に背景色を 50% ブレンド（未定義時は `Comment`） |
| `ArfSeparator` | インライン出力の前の表示幅いっぱいの罫線 | `Normal` の文字色に背景色を 75% ブレンドした色 |
| `ArfMessage` | `message()` やパッケージ起動時のメッセージ | `DiagnosticInfo` |
| `ArfStderr` | その他の stderr（警告や stderr への直接出力） | `DiagnosticWarn` |
| `ArfFloatNormal` | 確認用・出力フロートの本文と背景 | `NormalFloat` |
| `ArfFloatOutput` | フロート内の通常出力 | フロートの文字色に背景色を 5% ブレンドした色 |
| `ArfFloatOutputStale` | コード編集後のフロート内の通常出力 | フロートの文字色に背景色を 50% ブレンド（未定義時は `Comment`） |
| `ArfFloatMessage` | フロート内のメッセージ | `ArfMessage` |
| `ArfFloatStderr` | フロート内の stderr | `ArfStderr` |
| `ArfFloatError` | フロート内のエラー | `ArfError` |
| `ArfFloatWarning` | フロート内の案内 | `ArfWarning` |
| `ArfFloatEmpty` | 出力がない場合の表示 | `ArfFloatOutput` |
| `ArfFloatBorder` | 確認用・出力フロートの枠 | `FloatBorder` |
| `ArfFloatTitle` | 確認用・出力フロートのタイトル | `FloatTitle` |
| `ArfSignRunning` | 実行中のマーク | `DiagnosticInfo` |
| `ArfError` | 実行エラー | `DiagnosticError` |
| `ArfWarning` | 画像表示などの案内 | `DiagnosticWarn` |
| `ArfSignRange` | 実行範囲の `│` | `ArfSeparator` |
| `ArfSignSuccess` | 実行成功のマーク | `DiagnosticOk` |
| `ArfSignError` | 実行エラーのマーク | `DiagnosticError` |

`"auto"` の配色はカラースキームの標準グループから取得します。RGB の文字色や背景色が未定義の場合、出力は元のグループ、区切り線は `NonText` にリンクします。

独自の色を設定する例：

```lua
local function arf_colors()
  vim.api.nvim_set_hl(0, "ArfOutput", { fg = "#a6adc8" })
  vim.api.nvim_set_hl(0, "ArfSignSuccess", { fg = "#a6e3a1" })
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = arf_colors })
arf_colors()
```

画像のプレースホルダーの配色は Snacks が管理します。

## Limitations

- 評価は一度に一つです。`ArfRunAll` 全体を通して追加実行・オブジェクト確認を拒否します。出力は各評価の完了後に表示し、逐次表示・中断後の再開には対応しません。
- 結果は行範囲ごとに管理します。同じ行にある別の式を実行しても、以前の結果を置き換えます。
- 結果のセッション間保存・復元は未対応です。テキストの保持上限は評価ごとで、全結果の合計容量・画像枚数・画像の合計容量には上限を設けていません。
- stdout の後に stderr を表示するため、両者の出現順序は保持しません。

## Troubleshooting

- **画像が出ない**：`:checkhealth snacks` で依存とターミナル認識を確認してください。`:echo executable('magick')` または `:echo executable('identify')` が `1` ならコマンドを検出できています。
- **式を実行できない**：R の Tree-sitter パーサーとバッファ内の構文を確認してください。Visual 選択・`:3,5ArfRun` はパーサーなしでも使えます。
- **キーが効かない**：`keys` 設定を追加したこと、バッファの filetype が `r` であること、キー登録前に `maplocalleader` を設定したことを確認してください。
- **出力の続きが見えない**：実行したコードの範囲にカーソルを置いて `:ArfOutput` を開いてください。tibble 自身の省略や保存容量の超過は、[出力設定](#output-and-floats)を変更して再実行する必要があります。
- **`object not found` と出る**：変数を作る式を先に実行してください。`:ArfStop` 後のセッションには以前の変数がありません。
- **相対パスでファイルが見つからない**：R で `getwd()` を実行して確認してください。起動後の Neovim の `:cd` は R に反映されないため、R 側で `setwd()` するか、自動起動したセッションを `:ArfStop` して作業ディレクトリを変更後に再実行します。
- **計算が終わらない**：`:ArfStop` で自動起動したセッションを終了できます。R の変数は失われます。`pid` 指定の外部セッションは、そのセッション側で停止してください。

## Project philosophy

自分の R 作業のために、AI と vibe coding で作りました。必要な機能は揃ったので、今後も小さく保つ方針です。追加機能が欲しい場合は、気軽に fork して育ててください。

## License

[MIT ライセンス](LICENSE) © 2026 topazape.
