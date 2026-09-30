# A VS Code extension that shows remaining Claude usage in the editor

## Context

howmuchleft is a Claude Code statusline: Claude Code spawns the binary on every
render, pipes a JSON status object to it, and the binary prints three gradient
bars (context window, 5-hour limit, and weekly limit) and exits. Usage comes
from the OAuth credentials Claude Code already stores in the profile directory
(`<claude-dir>/.credentials.json`, with a macOS Keychain fallback), is fetched
from the usage API by `internal/cache`, and is cached in
`<claude-dir>/.statusline-cache.json` with a TTL, error backoff, and a
stale-data fallback. `howmuchleft profile list [--live]` renders every
discovered profile side by side (`internal/dashboard`).

All of this output is terminal output. A developer who works in VS Code, or in
a VS Code derivative such as VSCodium or Cursor, and runs Claude Code in the
integrated terminal or through its editor integration, sees the bars only while
the Claude Code terminal is visible, and never sees the other profiles unless
they run the dashboard by hand. The idea: an editor extension that shows how
much usage is left, permanently, in the editor's own status bar.

## The problem

1. The 5-hour and weekly limits are account-wide, not per-session, yet the only
   place they show is inside one Claude Code session's statusline.
2. The data needed is already computed and cached by howmuchleft, but only in a
   terminal rendering (ANSI-escaped text). There is no machine-readable output
   an extension could consume: `profile list` prints ANSI rows, and the cache
   file is an internal format with no stability promise.
3. Several profiles can exist (discovered from the config's `profiles` list,
   claudewheel's `~/.claudewheel/options.json`, and `~/.claude-*` directories
   holding credentials). An extension must know which one to show; the editor
   has no notion of "the current profile".

## Proposed extension

A TypeScript extension that shells out to the howmuchleft binary for its data
and renders it with native VS Code UI. The Go code stays the single
implementation of discovery, credentials, the usage API, and caching; the
extension only displays.

### Features

- **Status bar item** (`vscode.window.createStatusBarItem`): the chosen
  profile's 5-hour and weekly remaining percentages with time until reset, for
  example a compact `5h 62% | wk 81%` text. `backgroundColor` switches to the
  theme's `statusBarItem.warningBackground` and `statusBarItem.errorBackground`
  colors at thresholds taken from howmuchleft's own config, so the thresholds
  are not declared twice. Stale data (the cache's last-known-good fallback) is
  marked the way the terminal output marks it, with a `~` prefix.
- **Rich tooltip** (`vscode.MarkdownString` on the status bar item): every
  window with its reset time, the extra-usage figure when enabled, the
  subscription tier, and when the data was fetched.
- **Profiles tree view** (`vscode.window.createTreeView` with a
  `TreeDataProvider`, in its own view container): one node per discovered
  profile with its windows as children, the same content as `profile list`.
- **Commands** (`vscode.commands.registerCommand`, listed in the command
  palette): refresh now, choose the profile shown in the status bar (a
  `vscode.window.showQuickPick` over discovered profiles), and open the
  howmuchleft config file.
- **Refresh**: a timer no faster than the cache TTL, so the extension never
  causes more usage-API calls than a statusline render does. Refreshing through
  the binary means the existing file cache and error backoff apply unchanged.
- **Settings** (`contributes.configuration`): the path to the howmuchleft
  binary and the profile directory to show. Per the family's rule against
  implicit choices where more than one target could be meant, the extension
  does not guess a profile when several exist: it shows a status bar prompt to
  choose one until a profile is set.

### The CLI side this needs

- A machine-readable usage output from howmuchleft, for example a JSON mode of
  `profile list`, or a dedicated read-only command printing one profile's usage
  windows, reset times, tier, staleness, and fetch time as JSON. If strictcli's
  framework-owned machine-output support fits, that is the natural route; the
  shape to be decided when the work starts. The cache file format is not the
  contract.
- The JSON schema for that output committed alongside the code, so the
  extension's TypeScript types can be generated from it or checked against it.

## Solutions considered

| Approach | Pros | Cons |
|---|---|---|
| Extension runs the binary and reads a JSON output (recommended) | One implementation of credentials, API, and cache; the extension is a thin display; behavior matches the statusline | Needs the binary installed and a new JSON surface in howmuchleft; a process start per refresh (cheap at a TTL-bounded rate) |
| Extension reads `.statusline-cache.json` directly | No new CLI surface; no process start | Couples the extension to an internal file; shows nothing until a Claude Code session has rendered once; stale-data and backoff logic would be reimplemented in TypeScript |
| Extension reimplements the usage API call in TypeScript | No binary needed | Duplicates OAuth refresh, credential lookup (including Keychain), and caching in a second language; two implementations drift |
| Bundle per-platform howmuchleft binaries inside the extension (platform-specific VSIX packages) | Works without a separate install | Larger packages, one VSIX per platform, and a second channel whose howmuchleft version can disagree with the one Claude Code runs |

For the binary dependency, the extension would refuse with a clear error naming
the install command when the configured binary is missing or too old to offer
the JSON output, rather than degrading silently.

## Distribution

- An extension is TypeScript/JavaScript packaged as a VSIX with `vsce`.
- Publish to both the Visual Studio Marketplace and Open VSX (the open registry
  VSCodium, Cursor, and other VS Code derivatives install from), with `ovsx` for
  the latter. Each registry needs its own publisher namespace and token.
- howmuchleft is released with rlsbl, which has no VS Code extension publishing
  target. Either rlsbl gains one (a VSIX build plus both registry uploads, driven
  by the release like the other pipelines), or the extension is published by a
  separate workflow. The rlsbl target is the consistent choice, since every
  other artifact of this repository ships through a release.
- The extension's name, publisher ID, and package name are to be chosen.

## Affected files and new components

- `internal/cli/root.go`: the new JSON output (a flag on `profile list` or a new
  command), classified read-only.
- `internal/dashboard/dashboard.go` and `internal/cache/cache.go`: expose the
  per-profile usage result as a serializable structure rather than only a
  rendered string.
- A new directory for the extension (its location in the repository to be
  decided; it has its own `package.json`, `tsconfig.json`, and test setup, and
  must stay outside `go test ./...`).
- README and docs: an editor section once the extension exists.

## Effort estimate

- JSON output in howmuchleft, with tests: about half a day.
- Extension (status bar item, tooltip, tree view, commands, settings, tests with
  `@vscode/test-electron`): two to three days.
- Publishing setup for both registries, plus the rlsbl target if that route is
  chosen: one day for a workflow, more if rlsbl gains a target.
