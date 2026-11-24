# plugin-antigravity

Pohunek runtime plugin for Google [Antigravity CLI](https://antigravity.google/docs/cli/reference) (`agy`), detection-only (`v0.1.0`).

| | |
|---|---|
| Repository | `pohunekd/plugin-antigravity` |
| Package id | `pohunek.runtime.agy` |
| Runtime id (`--agent`) | `agy` |
| Upstream | Antigravity CLI release pinned in `compat/RELEASE` (`1.5.16`, verified on `1.5.13` and `1.5.16`) |
| Status | **detection-only**: OSC 7501 program-status + screen detection, no resume |

Install by id (after admission): `pohunek plugin install pohunek.runtime.agy`.

## Scope of v0.1.0

- **Detection-only**: `[resume] supported = false` and `[native_reference] strategy = "none"`.
  Antigravity CLI generates its own conversation UUIDs (an unknown `--conversation <uuid>`
  warns and opens a fresh conversation), so native resume awaits a core hook integration
  handler.
- **Native OSC 7501 program status**: Antigravity CLI (`1.4.0+`, with background-task fix in
  `1.5.x`) emits OSC 7501 records with `app=antigravity` once the session worker answers its
  `ESC ] 7501 ; ? ST` startup probe (`blocked:kind=auth`, `blocked:kind=question`,
  `blocked:kind=permission`, `error`, `working`, `idle`, `done`). Screen rules in
  `package/detect.toml` backstop OSC 7501 with `visible_blocker = true` on every dialog and
  startup gate and drive `detect-check` corpus replay.
- **`prompt_arg = false`**: `agy` rejects bare positional prompt arguments (exit 2), so initial
  prompts travel as bracketed-paste terminal input once the idle composer renders
  (`ready = "screen_idle"`).
- **Auto-update disabled**: `[launch_env]` sets `AGY_CLI_DISABLE_AUTO_UPDATE = "true"` so a
  pinned upstream binary is not replaced in the background under a running host.
- **In-process placement**: `[placement] mode = "in_process"` (`agy` runs in-process without a
  detached daemon surviving session stop).
- **Blocked input refusal**: `refuse_while_blocked = true` prevents `pohunek session input`
  from accidentally answering sign-in, onboarding, trust, permission, or question dialogs;
  operators answer dialogs via `pohunek attach`.
- **Workspace trust**: `agy` has no CLI flag to pre-trust a workspace; trust is persisted in
  `~/.gemini/antigravity-cli/settings.json` (`trustedWorkspaces`) or confirmed interactively
  through `pohunek attach`.

## Detection anchors

Every blocked and working rule in `package/detect.toml` is an ordered multi-line regex over
its rendered frame, anchored to the bottom of its region (`\z`) so transcript quotes of dialog
text or `detect.toml` never false-positive:

- **Command approval** (`after_last_horizontal_rule`, `blocked`, `visible_blocker`):
  `Run this command?`, `1. Yes, run command`, `No, cancel`, `↑/↓ Navigate`, and `esc to cancel`
  at screen end.
- **File create / edit approval** (`after_last_horizontal_rule`, `blocked`, `visible_blocker`):
  `Allow ...?` or `Accept ...?`, `1. Yes,`, `2. No,`, `↑/↓ Navigate`, and `esc to cancel` at
  screen end.
- **Question dialog** (`after_last_horizontal_rule`, `blocked`, `visible_blocker`):
  `Question <n>/<m>:`, numbered options starting at `1.`, `Write-in...`, `↑/↓ Navigate ... esc Skip`,
  and `esc to cancel` at screen end (covers both single-select and multi-select).
- **Workspace trust** (`whole_recent`, `blocked`, `visible_blocker`, composer absent):
  `Do you trust the contents of this project?`, `Yes, I trust this folder`, `No, exit`,
  `↑/↓ Navigate · enter Confirm`.
- **Settings error** (`whole_recent`, `blocked`, `visible_blocker`, composer absent):
  `Settings Error`, `Exit and fix manually`, `Continue with defaults this session`,
  `enter Confirm · esc Exit`.
- **Sign-in & onboarding** (`whole_recent`, `blocked`, `visible_blocker`, composer absent):
  unauthenticated login menu and Google Cloud submenu (`login_method`), remote SSH OAuth code
  screen (`login_oauth_url`), color scheme picker (`onboarding_color_scheme`), and Terms of
  Service & Data Use screen (`onboarding_tos`).
- **Working** (`bottom_non_empty_lines(16)`, `working`, priority 700): live composer rules
  (`─{10,}\n>...\n─{10,}`) followed directly by `esc to cancel` on the footer line.
- **Idle** (`bottom_non_empty_lines(16)`, `idle`, priority 300): live composer rules followed
  by `? for shortcuts` (both inline single-line and alt-screen two-line layouts) or the model
  status row when draft text is present, excluding `esc to cancel`.

## Measurements behind the descriptor

- `agy --version` prints bare `1.5.16` (and `1.5.13`), exit 0, ~102–145 ms across 5 runs.
- Cold start to `state=idle:app=antigravity` and rendered composer: ~0.14–0.27 s in a
  pre-onboarded workspace; `startup_grace_ms = 20000` provides ample margin on slow hosts.
- Bracketed paste (`?2004h`) is enabled before the composer draws (including on sign-in and
  onboarding screens), requiring `input.ready = "screen_idle"`.
- `submit_delay_ms = 150` gives lossless paste + Enter submission.

## Local checks

Run these from the repository root (a checkout of the core tag under `../core` provides the
kit and the daemon binaries the smoke reads; build them first, as CI does):

```sh
(cd ../core && cargo build --locked -p pohunek-plugin-kit --features daemon)
(cd ../core && cargo build --locked -p pohunek-cli -p pohunek-daemon -p pohunek-session-worker)
export UPSTREAM_BIN="$PWD/upstream-bin"
bash scripts/install-upstream.sh
../core/target/debug/pohunek-plugin-kit lint --dir package
rm -rf build-one build-two dist release-dir
mkdir -p build-one build-two dist
../core/target/debug/pohunek-plugin-kit build --dir package --output-dir build-one
../core/target/debug/pohunek-plugin-kit build --dir package --output-dir build-two
cmp build-one/*.tar.zst build-two/*.tar.zst
cp build-one/*.tar.zst dist/
archive="$(echo dist/*.tar.zst)"
../core/target/debug/pohunek-plugin-kit verify --dir package --archive "$archive" \
  --sha256 "sha256:$(shasum -a 256 "$archive" | cut -d' ' -f1)"
../core/target/debug/pohunek-plugin-kit detect-check --dir package --corpus corpus
python3 -I -B scripts/path-check.py --generic-only
mkdir -p release-dir
cp ../core/target/debug/pohunek ../core/target/debug/pohunekd \
  ../core/target/debug/pohunek-sessiond release-dir/
../core/target/debug/pohunek-plugin-kit smoke --dir package --release-dir release-dir \
  --upstream "$UPSTREAM_BIN" --script scripts/smoke-agy.sh --json
```
