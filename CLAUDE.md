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
bash test/windows.sh -q # 27 checks, the Windows parts, faked
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
3. **Only inside `$HOME`.** This is why WSL is treated as Linux and not as
   Windows: the Windows profile lives outside the WSL home, and no feature is
   worth widening this. Under Git Bash `$HOME` *is* `C:/Users/<name>`, so
   Windows support needed no exception at all. `nimo_is_protected` in `lib/core.sh` refuses any
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

- Make every path absolute before the safety guard sees it. The guard compares
  against `$HOME`; a relative path never matches and is refused as "outside
  your home folder", which looks like a bug in the guard and is a bug in the
  caller.

- Marks and glyphs come from the box-drawing block, drawn here. No fetched icon
  sets, no emoji: this is a terminal tool and both age badly in one.

- If a command destroys something, keep a copy first and fail rather than
  proceed when the copy cannot be made (`min blank` is the pattern).

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
`test/windows.sh` does the same with a fake `uname` reporting MINGW, a profile
whose Desktop has moved into OneDrive, and caches under `AppData`.

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

## Releases

Every version is tagged `vX.Y.Z` with its changelog entry as the message.
`release.yml` fires on a tag, refuses to publish if the tag and `VERSION`
disagree or either suite fails on macOS, and writes the release notes out of
`CHANGELOG.md`. So: bump `VERSION` and `NIMO_VERSION` in `min` together, write
the changelog entry, commit, tag, push the tag.

`Formula/nimo.rb` pins the tarball of the newest tag — bump its `url` when
cutting a release.

`assets/demo.svg` is generated: `python3 tools/make-demo.py > assets/demo.svg`.
Edit the frames in the generator, never the SVG — a test diffs the two, so an
edited SVG fails the suite.

The face lives in `nimo_face_rows` with the eye row split out, because two
things draw it: `nimo_face` plain, and `nimo_face_hello` which draws it in and
blinks. Animation is gated on `nimo_can_animate` — a terminal, a shell that can
`sleep 0.01`, and nobody asking for quiet — and never costs more than 400 ms.
`NIMO_ANIMATE_FORCE=1` is the way in for tests, since the suite has no terminal.

Cursor movement is relative, always: `\033[6A` up and `\033[6B` back. `\033[s`
and `\033[u` are not the same escape everywhere, and on the terminals that
ignore them nimo printed its prompt, its hint and its whole menu on top of its
own face. `tools/screen.py` renders a raw stream the way a terminal would, so
the suite can check what is on screen and not only which bytes were sent — a
grep sees a perfectly good face either way.

## Nothing may drift

`test/run.sh` walks `nimo_dispatch` in `min` and insists every command it finds
appears in `min help`, `completions/min.bash`, `man/min.1`, `README.md` and
`lib/repl.sh`, and that `VERSION`, `min version`, `CHANGELOG.md` and the tag in
`Formula/nimo.rb` agree. Add a command and the suite tells you the five places
you forgot. This is cheaper than remembering.

The same walk runs over the flag parser: every long flag `min` accepts has to
turn up in `min help`, `man/min.1` and the completions. That is the quiet half
of drift — not a promise nimo breaks, a feature nobody can find. `--color` sat
there unmentioned for eight versions.

The website counts as documentation. It drifted eleven versions once; do not
let that happen again — `docs/index.html` and the published artifact are the
same file.

## Two platforms, one menu

Nothing is offered that this computer cannot do. `min clear` builds its rows
per platform rather than printing a fixed seven — Windows has no Dock, and no
Recycle Bin nimo is allowed to empty. Both suites check their own side, because
"only offer what it can do" turns into "offer less than it can" the moment only
one of them is tested.

Anything that reads the desktop or the downloads goes through
`nimo_desktop_dir` / `nimo_downloads_dir`, never `$HOME/Desktop`. On a
signed-in Windows, and on a Mac with a synced desktop, those are not the same
folder — the menu once counted one and the command read the other.

## The website

`docs/index.html` is the whole site — one file, no build step. GitHub Pages
serves it from `/docs`.

## Git

The remote is `git@github.com:danielkopa/nimo.git` over SSH. Commits are small
and each one says what changed in plain words.
