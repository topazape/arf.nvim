# arf.nvim

<p align="center">
  <img src="assets/logo.png" alt="arf.nvim logo" width="560">
</p>

English | [日本語](README.ja.md)

**R code and results, together in Neovim.**

A Neovim plugin powered by [arf](https://github.com/eitsupi/arf). Run expressions from `.R` files and view text and plots directly below your code, without writing output into the source file.

[Features](#features) · [Requirements](#requirements) · [Installation](#installation) · [Usage](#usage) · [Configuration](#configuration) · [API](#api) · [Highlights](#highlights) · [Limitations](#limitations) · [Troubleshooting](#troubleshooting)

## Features

- **Run expressions or the whole buffer** — Tree-sitter identifies pipelines, ggplot expressions, function definitions, and more. Visual selections and explicit line ranges work too.
- **Inline results** — Display text and plots below the code, stacking multiple images in generation order and keeping results from other ranges.
- **Persistent R session** — Start a session automatically on first execution and reuse objects across runs.
- **Inspect saved output** — Open output and errors in a searchable, copyable floating window.
- **Object inspection** — Call `summary()` or another R function on the object under the cursor.
- **Execution signs** — An animated spinner, success and error icons, and configurable symbols and colors.

## Requirements

- **Neovim 0.12+**
- **R and [arf](https://github.com/eitsupi/arf)** — Follow arf's installation instructions and put `arf` on your PATH, or configure its executable path. Tested with arf 0.6.0.
- **R Tree-sitter parser** — Required for `ArfRun` expression detection in Normal mode and for `ArfRunAll`. Install `r` using your parser manager. Visual selections and explicit line ranges do not require the parser.
- **Nerd Font** — Used by the default success and error icons. Optional if you replace them with ordinary Unicode characters; see [Signs](#signs).

Inline plots additionally require:

- [snacks.nvim](https://github.com/folke/snacks.nvim) with `image` enabled. Tested with the placement API in version 2.31.0.
- **A compatible terminal**, such as Ghostty or Kitty, supporting inline images through the Kitty Graphics Protocol.
- **ImageMagick** — The tested Snacks implementation uses `magick identify` or `identify`, including for PNG files.

## Installation

### lazy.nvim

Add this spec to your lazy.nvim configuration:

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

If you already configure Snacks, add `image = { enabled = true }` to its options. You can omit `dependencies` when using text output only.

With the spec above, lazy.nvim loads the plugin and registers the configured keys when you open an R file.

## Usage

1. Start Neovim in your R project's working directory and open an `.R` file.
2. Place the cursor in an expression and press `<LocalLeader>fr`.
3. Read the results below the code. To run selected lines instead, make a Visual selection and press the same keys.

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

Run `x <- mtcars` first, then `head(x)` or `plot(...)`. Place the cursor on `x` and press `<LocalLeader>fk` to open its summary; press `q` to close the float.

Run `model <- ...` followed by `plot(model)` to display four diagnostic plots vertically.

Unless `pid` selects an external session, `arf headless` starts automatically on the first evaluation; no manual session startup is needed. To run the whole buffer, press `<LocalLeader>fR` or use `:ArfRunAll`.

### Keymaps

The plugin does not register R buffer keymaps automatically. The Installation example registers keys through lazy.nvim; see [Commands](#commands) for their actions.

`<LocalLeader>` follows `vim.g.maplocalleader` and defaults to backslash: `\fr` to run and `\fc` to clear. To use a comma, set it before the plugin loads:

```lua
vim.g.maplocalleader = "," -- ,fr to run, ,fc to clear
```

Customize the lazy.nvim `keys` entries in Installation or use `vim.keymap.set()`. The Visual mapping uses `:ArfRun<CR>` to pass complete selected lines. Press `q` to close a float.

### Commands

These commands are available directly; the keys shown are configured by the Installation example:

| Command | Example key | Action |
| --- | --- | --- |
| `:ArfRun` | `<LocalLeader>fr` | Run the current expression in Normal mode or complete selected lines in Visual mode. Use `:3,5ArfRun` to run complete lines in an explicit range. |
| `:ArfRunAll` | `<LocalLeader>fR` | Run every top-level expression in the current buffer in order, displaying results below each expression. |
| `:ArfClear` | `<LocalLeader>fc` | Remove output, images, and signs from the current buffer. |
| `:ArfSummary` | `<LocalLeader>fk` | Call `base::summary()` on the object under the cursor and show it in a float. |
| `:ArfOutput` | `<LocalLeader>fo` | Open saved output for the execution range under the cursor without evaluating R again. Search with `/` and copy with `y`. |
| `:ArfStop` | `<LocalLeader>fs` | Terminate the automatically started arf session, even during execution, and clear results and signs in all buffers. The next evaluation starts a fresh session. |

### Object inspection

To call an R function on the object under the cursor and show its text output in a float, add a callback to your keymaps:

```lua
-- Add this entry to the lazy.nvim `keys` table above.
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

Object inspection (including summary) resolves the name under the cursor (including dots) in the global environment and inherited environments. It does not evaluate member/index expressions or whole names containing spaces/operators: on `column` in `df$column`, it looks up a separate object named `column`.

`inspect(fn, opts)` accepts an ASCII R function name or an exported `package::function`; R code can be supplied explicitly with `{ r = [[ ... ]] }`. Install the package before using a namespace-qualified function; `library()` is unnecessary. Plots are not displayed.

`title` is optional and defaults to `function(object)` (or `summary(object)` for `base::summary`).

The function receives one argument: the object under the cursor. Embed an anonymous R function in Lua to supply extra arguments. It is evaluated in the R session on each call, without prior registration. Syntax and runtime errors appear in the float.

```lua
require("arf").inspect({
  r = [[
    function(x) {
      stats::confint(x, level = 0.90)
    }
  ]],
}, { title = "90% confidence interval" })
```

The default title for `{ r = ... }` is `inspect(object)`. Supply trusted R code. Functions already defined in the R session remain usable as `inspect("inspect_ci")`.

### Execution and sessions

- Automatic selection requires a syntactically complete buffer. Inside a function or loop, it selects the whole definition or loop; expressions sharing a line are selected by cursor position. Blank lines and comments outside expressions have nothing to run.
- `ArfRunAll` runs top-level expressions in the existing session, stopping at the first R error or IPC failure. Completed results and existing results not reached remain. `:%ArfRun` evaluates the buffer as one range, with combined output at the end.
- Results appear below the executed range. Overlapping runs replace results; edits inside a completed range remove them.
- Editing, clearing, or unloading the source buffer while evaluation is pending discards its result and stops subsequent expressions, without interrupting R.
- All buffers in a Neovim instance share one R session. Automatically started sessions use `:pwd` at the first evaluation; later `:cd` changes do not affect R. External sessions retain their existing working directory. Neovim exits stop only automatically started sessions.

## Configuration

Set only the options you want to change, using `opts` in your lazy.nvim spec. Nested `signs` options merge individually. Repeated calls to `setup()` merge the supplied options into the current configuration.

<details>
<summary>All options and defaults</summary>

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
  inspect_width = 120,        -- Columns, including for short output
  inspect_max_height = 20,    -- Maximum rows; shrinks for short output

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

- `executable`: command name or executable path. To change the executable for a running session, use `ArfStop` and evaluate again.
- `pid`: omitted by default for automatic startup. To use an existing session, obtain its PID with `arf ipc list` and supply it as a number. Manage its lifecycle and working directory separately. `ArfStop` does not stop an external session or clear its results.
- `startup_timeout`: startup wait time. Failed or timed-out startup is retried on the next evaluation.
- `timeout`: IPC response wait time for each evaluation, not for the entire `ArfRunAll` sequence. A timeout alone does not stop R computation; use `ArfStop` to terminate the owned session. Stop evaluations in an external session separately.

### Plots

All plots from an evaluation are displayed vertically in generation order (for example, `plot(lm(mpg ~ wt, data = mtcars))`). Each image uses the configured size limits.

`image_width` / `image_height` cap display size in cells; `plot_width` / `plot_height` / `plot_res` set PNG dimensions in pixels and resolution in dpi. Window size also constrains placement.

PNG settings must be positive integers; re-run after changing them. `plot_res` affects text and line sizes. Increasing pixels and DPI proportionally may improve sharpness without enlarging the display.

### Output and floats

| Option | Description |
| --- | --- |
| `output_max_lines` | maximum inline body lines; defaults to 20. An omission notice indicates remaining lines. Notices, the separator, and images do not count toward this limit. |
| `output_max_bytes` | total retained stdout, stderr, and error text per run; defaults to 1 MiB. Excess text is discarded with a notice. Images do not count toward this limit. |
| `output_width` / `output_max_height` | saved-output float width and maximum height. |
| `inspect_width` / `inspect_max_height` | width and maximum height for all inspection floats, including summary. |

Use positive integers. Floats fit the screen and shrink vertically for short output. `:ArfOutput` shows all retained text; images appear only inline.

Notifications and omission notices are in English; R output follows R's language settings.

- `output_max_lines` applies on the next refresh; `output_max_bytes` requires re-evaluation; float dimensions require reopening.
- Retention limits apply to each run-all expression and each inspection. Inspection floats include truncation notices.
- Discarded text and removed results cannot be recovered. Limits do not cap R computation, memory, or temporary capture files.

### Signs

Defaults are `│` for the range, `` for success, and `` for errors. Configure your terminal to use a Nerd Font. No `nvim-web-devicons` dependency is needed.

Set each symbol directly through `signs.range.text`, `signs.success.text`, `signs.error.text`, or `signs.running.text`.

| Option | Description |
| --- | --- |
| `signs.enabled = false` | hide all execution signs. |
| `signs.range.text = ""` | hide range markers and keep only the final-line status. |
| Each `text` | a symbol occupying 1–2 display cells, or an empty string to hide it. |
| Each `hl` | a highlight group name; see [Highlights](#highlights). |
| `signs.priority` | a non-negative integer; higher values take precedence. Defaults to 5. |
| `signs.running.frames` | animation frames, each 1–2 display cells wide. Two or more frames enable animation; an empty list `{}` or a single frame uses the static `running.text` instead. |
| `signs.running.interval` | a positive frame interval in milliseconds; defaults to 80. |

To use ordinary Unicode symbols without a Nerd Font:

```lua
require("arf").setup({
  signs = {
    range = { text = "│" },
    success = { text = "✓" },
    error = { text = "✗" },
  },
})
```

The spinner uses standard Unicode characters and updates only the last line of the running range. Its timer stops on completion, error, stop, clear, edits inside the range, or buffer deletion. Set `running.text = ""` to hide the final-line sign and disable its animation.

Range markers use `signs.running.hl` during execution. Configuration changes apply to subsequent runs. If signs are hidden, check `:set signcolumn=yes`.

## API

Commands and custom keymaps can use the same Lua API:

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

R evaluation through `run`, `run_all`, `inspect`, and the `summary` shorthand is asynchronous. See [Object inspection](#object-inspection) for custom keymaps and title options.

`clear` does not interrupt running R code. Use `stop` to terminate the owned session. See [Configuration](#configuration) for `setup(opts)` options and defaults.

## Highlights

Output, floats, and signs use dedicated highlight groups. Customize colors with Neovim's `nvim_set_hl()`, rather than plugin options.

| Group | Purpose | Default |
| --- | --- | --- |
| `ArfOutput` | normal output | The `Normal` foreground with each RGB component darkened by 15% |
| `ArfSeparator` | full-width line between source and inline output | `NonText` |
| `ArfMessage` | `message()` and package startup messages | `DiagnosticInfo` |
| `ArfStderr` | other stderr, including warnings and direct writes | `DiagnosticWarn` |
| `ArfFloatNormal` | inspection and output float text and background | `NormalFloat` |
| `ArfFloatBorder` | float borders | `FloatBorder` |
| `ArfFloatTitle` | float titles | `FloatTitle` |
| `ArfSignRunning` | running execution range | `DiagnosticInfo` |
| `ArfError` | execution errors | `DiagnosticError` |
| `ArfWarning` | notices, including image display warnings | `DiagnosticWarn` |
| `ArfSignRange` | the `│` range marker | `ArfOutput` |
| `ArfSignSuccess` | success sign | `DiagnosticOk` |
| `ArfSignError` | error sign | `DiagnosticError` |

Defaults are reapplied on colorscheme changes without overwriting existing definitions. To set your own colors:

```lua
local function arf_colors()
  vim.api.nvim_set_hl(0, "ArfOutput", { fg = "#a6adc8" })
  vim.api.nvim_set_hl(0, "ArfSignSuccess", { fg = "#a6e3a1" })
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = arf_colors })
arf_colors()
```

Image placeholders use colors managed by Snacks. arf float colors apply only to those floats through `winhighlight`.

## Limitations

- One evaluation at a time; additional runs and inspections are rejected throughout `ArfRunAll`. Output appears after each evaluation, without streaming or resuming interrupted computations.
- Results are tracked by line range. Running another expression on the same line replaces the previous result.
- Results cannot be saved/restored across sessions. Text retention limits apply per evaluation; there is no total limit across results or limit on image count or total image size.
- stdout precedes stderr, losing their interleaving.

## Troubleshooting

- **No image appears:** run `:checkhealth snacks` to check dependencies and terminal detection. `:echo executable('magick')` or `:echo executable('identify')` returns `1` when the command is available.
- **An expression will not run:** check the R Tree-sitter parser and buffer syntax. Visual selections and `:3,5ArfRun` work without a parser.
- **Keymaps do not work:** check that you added the `keys` configuration, that the buffer filetype is `r`, and that `maplocalleader` is set before the keymaps are registered.
- **A computation will not finish:** `:ArfStop` terminates the automatically started session. Its R objects will be lost.

## Project philosophy

Built with AI-assisted “vibe coding” for my own R workflow. It already does what I need, so I’m keeping the scope small. If you’d like additional features, feel free to fork it and make it your own.

## Development

Run all 16 test suites from the repository root:

```sh
nvim --headless -u NONE -l tests/run.lua
```

Each suite runs in a separate Neovim process. Tests cover configuration, commands,
expression selection, execution, saved output and floats, signs, buffer edits,
resource cleanup, multiple plots, and the Snacks grid renderer. The real arf test
starts its own headless session, checks persistent R objects and error recovery,
captures PNGs, and verifies shutdown and restart. It stops only its own session.

R, Rscript, arf, the R Tree-sitter parser, and Snacks are required for all
integration checks. Locally, unavailable optional dependencies are reported as
skipped. To require every integration check:

```sh
ARF_TEST_STRICT=1 ARF_TEST_SNACKS=/path/to/snacks.nvim \
  nvim --headless -u NONE -l tests/run.lua
```

GitHub Actions runs this strict mode on Linux and macOS, with Neovim 0.12.6,
R 4.6.1, arf 0.6.0, Snacks 2.31.0, and a fixed R parser revision. Dependency
installation and the parser build are defined in `.github/workflows/ci.yml`.
The parser installer uses a C compiler and does not require a parser manager.
Terminal image transport still requires a manual check in a supported terminal;
the automated tests verify PNG capture, placement integration, and placeholder grids.

## License

[MIT](LICENSE) © 2026 topazape.
