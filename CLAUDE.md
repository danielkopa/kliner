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

## The wallpaper store

`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, read by
`WallpaperAgent` when it starts. It is tried **first**, and it is the only
route that asks nobody for anything: every AppleScript path needs Automation
permission, and a Mac told "Don't Allow" once answers -1743 for ever without
ever asking again. A real machine turned up in exactly that state.

The file is edited, never generated: read it, swap the image, put it back.
Only the strings that follow a `<key>relative</key>` are touched — nothing
else in that file is a path, and nimo is not going to find out the hard way.
The original is copied to `backups/wallpaper-store.plist` before the first
write.

Two rules for finding the wallpaper in there, and the second is why this
survives Apple: a string right after a `<key>relative</key>` — Sonoma's shape
— **or** any `file://` string that names an image, whatever the key is called.
A folder URL is not an image and is left alone. That is the difference between
editing this file and rewriting it.

`min wallpaper --restore` has two ways back, in this order: set the wallpaper
you had (surgical, leaves your other changes alone), or copy the whole store
file back (exact, and the only thing left when that picture has been deleted).
Both are kept, so there is always an answer; `nimo_wall_forget` clears all
three files afterwards so the next change is a fresh "before".

`plutil` for the conversion, `awk` for the swap. **No `strtonum`** in the URL
decoder: that is a gawk extension and the awk macOS ships is the one Kernighan
wrote. Paths are percent-encoded byte by byte under `LC_ALL=C`, so an accented
name survives.

`test/macos.sh` shims `plutil` as a copy and keeps its fake store as XML, so
the awk that does the real work runs for real. The store is then moved aside
for the rest of the file, because the AppleScript routes still have to work on
the Macs that only have them.

## A tick you can stand behind

Apple has moved the wallpaper three times, and the AppleScript that used to
work still returns success on some systems while changing nothing. `nimo_wall_apply`
therefore **reads the wallpaper back** after every method and only reports
success if it moved. Three outcomes, three different sentences:

- moved → the tick, and `NIMO_WALL_METHOD` remembers which way worked so the
  rest of the session skips the audition
- did not move → say the Mac ignored it, print what osascript actually said,
  and point at `tools/wallcheck.sh`
- cannot read it back at all → that is the Automation permission, and saying
  "could not set it" would send the user looking in the wrong place

`NIMO_WALL_UNSURE` covers the fourth case: told, could not check. It gets a
note, never a tick.

The fake Mac in `test/macos.sh` remembers the wallpaper it was told to set —
a fake that always answers the same thing cannot test a read-back. And
`NIMO_OSA_LIES=1` is Apple's bug itself: every command succeeds and nothing
changes.

## Two memories, not one

`min wallpaper` applies each one as you flip, which means two different things
have to be remembered and they are not the same thing:

- `backups/wallpaper.txt` — what you had **before nimo ever touched it**.
  Written once, by `nimo_wall_keep_original`, and deliberately not overwritten
  while stepping, or `q` would put back the one you saw a second ago.
- `backups/wallpaper-at.txt` — where the flipping is **up to right now**. The
  path, not an index: a list that grows or shrinks between runs would make a
  number point at something else.

`min wallpaper --restore` applies the first and removes both, so the next
change is a fresh "before" and the flipping starts from where you actually
are.

The browser redraws by moving up and back down — relative moves only, for the
same reason the blink does. It also decides *before drawing anything* whether
it is going to browse, because opening a panel it never fills leaves an empty
box on the screen.

## Names people actually have

A file name is not a word. `test/run.sh` makes seventeen of the awkward ones —
quotes, apostrophes, backslashes, a leading dash, globs, `$(whoami)`,
backticks, pipes, semicolons, 180 characters, an emoji — and insists nimo
moves them all and runs none of them.

Two it will not move, on purpose: a newline or a tab in the name. The undo log
is one line per move, and those names are not one line. `find` prints a
newline name as two lines, neither of which is a file, so `nimo_folder_items`
drops anything that is not under the folder it was asked about and does not
exist, and `nimo_unnameable_count` counts the difference so the panel can say
how many were left alone. Sorting fewer things than are in the folder and
saying nothing is the failure mode worth avoiding.

## Forks are the whole cost

nimo is bash, so the only thing that ever makes it slow is starting processes.
`min downloads --dry-run` on two thousand files once took 33 seconds, from
three instances of the same mistake: a `basename`, a `tr` and a `$(printf
'\t')` running once per file, inside a loop that itself ran once per bucket.

The rules that came out of it:

- **Never `basename` in a loop.** `${path##*/}` is the same answer, for free.
- **Never `tr` to fold case.** `shopt -s nocasematch` is a builtin. bash 3.2
  has no `${var,,}`, which is why the `tr` was there in the first place.
- **Never `$(...)` per item.** Every classifier has two shapes: `nimo_*_set`
  sets a variable, `nimo_*_of` prints it. Hot paths call the setter.
- **Decide once, then count.** Not: for each bucket, for each item, decide.

`--by date` is the one classifier that still costs a process per file, because
nothing in the shell knows a file's mtime.

`test/run.sh` sorts four hundred files and insists it finishes. The limit is
loose on purpose: it catches the shape of the bug, not a slow CI runner.

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

The website counts as documentation. It drifted eleven versions once, and then
eighteen — so the version on it is now a check like any other. Bump it in
`docs/index.html` when you bump `VERSION`, and add a card when you add a
command; the suite will tell you about the first and trust you on the second.

## The Windows side

`lib/win.sh` is the whole of it: a `reg` wrapper, a read that survives the
`ValueName    REG_DWORD    0x1` layout, a write that records the old value
first, and the poke Windows wants afterwards. Everything is HKCU — never HKLM,
never anything needing an administrator, never a file.

One undo log serves both systems. A line whose type starts with `REG_` goes
back through the registry; everything else is a `defaults` line. A value that
was **never set** is logged as `REG_NONE`, not with an empty type — otherwise
the restore hands it to `defaults`, which is not on that machine, and the value
nimo invented stays behind for good.

nimo does not kill Explorer to make a setting take. `nimo_win_refresh` is the
documented poke and the whole of it; anything that still needs a sign-out says
so.

`reg` covers the settings. A few things Windows only tells you through its own
shell, so `nimo_ps` asks PowerShell: what is in the Recycle Bin and to empty
it, what is installed, the battery, total memory, and the one bit inside
`StuckRects3` that makes the taskbar slide away. Both are functions so the
suite can stand fakes in front of them.

`min hide` is the only command that restarts Explorer, and it asks separately
before doing it. The taskbar reads `StuckRects3` when Explorer starts and at no
other time, so there is no other way; everything else uses `nimo_win_refresh`
and says so if a sign-out is still needed. Do not add a second caller.

`min empty` never reaches into the Recycle Bin. That is files plus an index,
and removing one without the other leaves Windows confused about what it still
holds — so nimo asks Windows what is in there and asks Windows to empty it.
`nimo_has_trash` / `nimo_trash_count` / `nimo_trash_kb` / `nimo_trash_empty`
are the four ways to ask, because "is there a trash here" and "where is it"
stopped being the same question the moment Windows was answered properly.

`min apps` is read-only on both. Windows records no equivalent of
`kMDItemLastUsedDate`, so it lists what has been installed longest and says
which question it is answering.

`test/windows.sh` stands a fake `reg` and a fake `powershell.exe` in front of
the real ones, backed by a TSV and a few state files. Two traps in writing that shim, both now commented in it: a registry key
is full of backslashes, so `grep` reads `\S` and `\W` as patterns of its own —
and awk's `-v k="HKCU\S…"` expands the escapes on the way in, so the value has
to arrive through `ENVIRON`.

## What starts when you sign in

`lib/startup.sh` is one command over four sources: the HKCU `Run` key and the
Startup folder on Windows, login items and `~/Library/LaunchAgents` on macOS.
Both lists are **named** — the ones nimo can turn off, and the ones it will
only report, with the reason beside each. A count of things you cannot see is
not a report.

Nothing is uninstalled and nothing is deleted. A registry value is written
down and removed; a shortcut is moved into `~/.nimo/backups/startup/`; a login
item is deleted through System Events and its path kept. HKLM is listed and
never written — that needs an administrator, and nimo does not ask for one.

One undo covers both halves: the startup log names the preferences log it
opened, on a `prefs` line, so `min startup --undo` replays the registry values
and the moved files together. Without that the user has to know to run two
commands, in order.

`nimo_setup_restore` opens a panel of its own, and closing a panel resets
`NIMO_PAD` — so a nested call has to save and restore it. Panels do not nest.

`min dock` on Windows is the taskbar's pinned apps. A pin is two things at
once: a shortcut under `Quick Launch/User Pinned/TaskBar`, and a `Favorites`
blob under `Taskband` that Explorer keeps in step with it. Remove one without
the other and you get a pin that comes back or a gap that does not fill — so
both move together, and the replay is `nimo_startup_undo`, which already knows
how to put a moved file and a recorded registry value back at the same time.
It takes a title and a verb so the dock does not tell you its pins are about
to start themselves.

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
