# nimo — working notes

nimo makes a Mac feel minimal: a clear desktop, a dock with only what you open,
a calmer wallpaper, sane preferences, and the disk back. One bash script and
thirteen small libraries. No dependencies, no daemon, no network.

The point of the project is the **desktop**, not the disk. Cleaning caches is a
side dish. When in doubt, make the desktop calmer.

```bash
./min                 # the prompt — this is the front door
./min clear desktop   # or say it outright
bash test/run.sh -q   # 160 checks, anywhere
bash test/macos.sh -q # 86 checks, the macOS-only parts, faked
```

## Invariants — break these and the project is pointless

1. **Nothing happens without a yes.** Every command that changes something
   shows what it is about to do and waits. `--dry-run` must change nothing at
   all, ever, in any command. `/auto` is the one way to stop the asking, and it
   is itself a deliberate yes: it explains what it covers, asks once, shows in
   the prompt the whole time, and dies with the session.
2. **Everything is undoable.** Desktop moves are logged file by file; the dock
   is exported before it is touched; every preference's old value *and type*
   are written down; the old wallpaper is saved. The single exception is
   `min empty`, because the Trash already was the undo — and it says so.
3. **Only inside `$HOME`.** `nimo_is_protected` in `lib/core.sh` refuses any
   path outside the home folder, and `$HOME` itself, `/`, `/System`,
   `/Applications`. Never route around it.
4. **No sudo. Ever.**
5. **Nothing is downloaded.** Wallpapers come from what macOS ships.
6. **Safe vs. worth-a-look.** `min clean` may delete only caches apps rebuild
   themselves. Downloads, backups and `node_modules` are measured, shown, and
   never touched — not even with `--yes`.
7. **The number you show is the number you deliver.** Measure again after
   cleaning and report what was actually freed.

## Layout

```
min                    flags, dispatch, help. NIMO_SELF points back here.
lib/ui.sh              panels, colours, bars, the face
lib/core.sh            sizes, disk, config, safety guard, nimo_newest
lib/pick.sh            arrow-key picker (NIMO_PICK_FORCE=1 for tests)
lib/repl.sh            the prompt: aliases, typo correction, dispatch
lib/scan.sh            every place min clean knows about
lib/clean.sh           scan, report, clean, --json
lib/desktop.sh         one sorter behind desktop / downloads / screenshots
lib/dock.sh            read and rebuild the dock
lib/wall.sh            wallpaper
lib/look.sh            dark / light / hide (menu bar)
lib/dupes.sh           the same file kept twice — report only
lib/apps.sh            unused apps, and min empty
lib/undo.sh            the history, and the way back
lib/setup.sh           macOS preferences, min zen, and setup --restore
lib/tools.sh           clear, tidy, top, doctor, update, the menu
```

Adding a scan target is one `nimo_register` call in `lib/scan.sh`.
Adding a prompt word is two lines in `lib/repl.sh` (a glued form and a spaced
form). Both are matched: `/cleardesktop` and `/clear desktop` are one command.

## House style

- **bash 3.2** — the one macOS ships. No `mapfile`, no associative arrays, no
  `${var,,}`. Arrays are indexed by a counter (`NIMO_T_N`), never `${#a[@]}`.
- **ShellCheck clean** at `-S warning` with `-e SC2034`. CI enforces it.
- Every user-visible string is plain English, lower-case headings, no jargon,
  no exclamation marks. Say what happened, then how to undo it.
- Comments explain *why*, especially where the code looks odd. Most of the odd
  code below is a bug that was paid for once already.

## Rules of thumb

- A menu that asks you to choose should count what it is offering.
- Never move a file something else is still writing.
- `min doctor` should end with the one thing worth doing next, or nothing.

## Traps that have already bitten, with tests standing on them

- **`ls` sorts by locale.** macOS terminals use `en_US.UTF-8`, where
  `foo_2.tsv` sorts *before* `foo.tsv`; the C locale CI uses sorts it after.
  Picking the newest file by name therefore worked on Linux and silently
  replayed the wrong undo log on a Mac. Use `nimo_newest` (modification time).
- **`grep -q` kills what feeds it.** It exits at the first match and the
  command behind it dies of SIGPIPE — a test that piped a command into
  `grep -q` was ending the command before it did its work. Capture the output
  first when the command must finish.
- **`"$(printf '\n')"` is an empty string.** Command substitution strips
  trailing newlines, so a `case` pattern built that way matches *everything*.
  Use `$'\n'`.
- **`grep -c` prints 0 and exits 1** on empty input, so `$(… || printf 0)`
  quietly yields `"0\n0"`. Use `nimo_line_count`.
- **`min` with no arguments opens the prompt when stdin is a tty**, so the
  suites must give every plain call `</dev/null` or they hang on a real
  terminal.
- **`df` can return nothing**, and every arithmetic test downstream then fails
  with "integer expression expected". Disk helpers always print a number.
- **Two runs in one second** used to land on the same log name and the second
  truncated the first. `nimo_free_file` adds a suffix; `nimo_newest` decides
  which is newest.
- **zsh has no `complete`** until `bashcompinit` is loaded, so
  `completions/min.bash` loads it itself and stays silent if it cannot.

## Testing

`test/run.sh` runs everywhere against a throwaway `$HOME` in `/tmp`.
`test/macos.sh` puts fake `defaults`, `osascript`, `killall`, `sw_vers`,
`pmset`, `mdls`, `sqlite3` and `uname` in front of the real ones and runs the
real code against them, so the dock, wallpaper and preference paths are tested
without a Mac and without touching one. Both take `-q`.

Every push runs both on Linux and on macOS under `/bin/bash` (bash 3.2), plus
ShellCheck and an install/uninstall round trip. See `.github/workflows/ci.yml`.

When a bug is found, the fix and a test that fails without it go in together.

## The repository itself

`assets/nimo-*.svg` is the banner, one variant per GitHub theme, referenced
from the README with `<picture>`. `CONTRIBUTING.md`, `SECURITY.md` and the
`.github` templates exist and are meant to be kept true — if an invariant
changes, they change with it. The badge that claims a test count is a promise
like any other: update it when the suites grow.

## The website

`docs/index.html` is the whole site — one file, no build step. GitHub Pages
serves it from `/docs`.

## Git

The remote is `git@github.com:danielkopa/nimo.git` over SSH. Commits are small
and each one says what changed in plain words.
