# Changelog

## 0.30.0

### min startup — what launches when you sign in

The slowest, most cluttered part of a computer is usually the part nobody
looks at: the six things that start themselves every morning.

- Reads four places — the `Run` key and the Startup folder on Windows, login
  items and `~/Library/LaunchAgents` on macOS — and names all of them: the
  ones nimo can turn off, and the ones it will only report, with the reason
  beside each. A count of things you cannot see is not a report
- **Nothing is uninstalled and nothing is deleted.** A registry value is
  written down and removed, a shortcut is moved into `~/.nimo/backups`, a
  login item is deleted through System Events and its path kept. A program you
  stop still starts when you open it yourself
- Anything set for everyone on the machine needs an administrator, so nimo
  lists it and never writes to it
- **One undo covers both halves.** The startup log names the preferences log
  it opened, so `min startup --undo` puts the registry values and the moved
  shortcuts back together — rather than leaving you to know that one of them
  needed `min setup --restore` as well

### The rest

- `min clean` on Windows knows the caches people there actually have: Chrome
  and Edge code caches, Firefox, Brave and Opera, Teams, Slack, VS Code,
  Discord and Spotify, Gradle, Cargo, NuGet and Go build, and the thumbnail
  cache. Three that look exactly like junk and are not — the Package Cache,
  the Visual Studio installer cache and `.nuget/packages` — are named in the
  source with the reason, and left alone
- The `/` list offers `/startup`

## 0.29.0

Found by running every command against a faked Windows and reading the output,
the same way 0.25.0 and 0.26.0 were.

- **Fixed: a count with a newline in the middle of it.** `grep -c .` prints 0
  and exits 1 on an empty file, so `$(grep -c . "$f" || echo 0)` produced "0"
  and then a second "0". It went into the label in `min undo`, the label took
  two rows, and the numbers you were being asked to pick from stopped lining
  up with the things they named
- **Fixed: `min tidy` narrated what it would not be doing.** It ran every step
  and let the ones this machine cannot carry out print an apology — so on
  Windows it was partly a list of refusals, and it called the result "a
  minimal mac" either way
- **Fixed: the arrow menu offered a wallpaper on Linux** and a dock to thin
  out, neither of which is there
- A log a command opened and never wrote to is no longer offered in `min undo`
  — reversing it would put nothing back
- `min clear` says "all of it can be undone, except taking the rubbish out"
  rather than claiming the whole list is reversible with the bin sitting in it

## 0.28.0

The list you get for `/`, and the last of what Windows could not do.

### The prompt

- **The `/` list is built, not written out.** It is grouped by what you came
  to do — clear something, make it yours, get the disk back, and back again —
  it counts what is actually lying about before you have chosen anything, and
  it only offers what this computer can carry out. A Windows machine was being
  handed a dock and a menu bar it does not have

### Windows

- **`min empty` empties the Recycle Bin.** nimo never reaches into it — that
  is files plus an index, and removing one without the other leaves Windows
  confused about what it still holds. It asks Windows what is in there, shows
  you, and asks Windows to empty it
- **`min apps` lists what is installed**, longest-installed first, with sizes
  and dates. Windows records no equivalent of "last opened", so it says which
  question it is answering instead of implying the other. Read only, as on
  macOS
- **`min hide` makes the taskbar slide away.** One bit inside `StuckRects3`,
  which the taskbar reads when Explorer starts and at no other time — so this
  is the only command in nimo that restarts Explorer, it asks separately
  before doing it, and it says plainly that nothing is lost by it
- **`min doctor` reads the battery and the memory**, so it says the same
  things on both systems
- `min clear` offers the Bin now that there is something behind it, and the
  panel no longer claims everything in the list can be undone while the
  rubbish is sitting in it

The Windows suite is 116 checks, up from 27 three versions ago.

## 0.27.0

Two things, both asked for: it must not be able to delete your computer, and
it has to actually do something on Windows.

### The guard that keeps nimo in your home folder

- **Fixed: three spellings walked straight around it.** The guard compared the
  path it was handed against `$HOME` as text, and a glob does not know that
  `$HOME/.` is `$HOME` — so that spelling read as "somewhere under your home"
  and passed. What runs next deletes every child of what it is given: the home
  folder, emptied, by the one command whose whole promise is that it will not.
  `$HOME//` and `$HOME/./` did the same. Every path is reduced to one spelling
  first now
- **Fixed: an empty `$HOME` opened the whole machine.** `"$HOME"/*` is `/*`,
  which matches every absolute path there is. A `$HOME` that is empty or not an
  absolute path now means nimo deletes nothing rather than everything
- **Fixed: cleaning followed links off the disk.** `find dir/ -mindepth 1`
  walks through a symlink the moment the path ends in a slash, and a cache
  folder moved to another drive is exactly that link. Links are refused
- **Fixed: `min blank` emptied what a link pointed at.** It checked the name
  you typed and truncated the file at the other end
- Twenty-nine new checks, each one a spelling of your own home folder, plus a
  file outside it that has to still be there afterwards

### Windows

- **`min wallpaper` works.** It lists what Windows ships under
  `C:\Windows\Web`, writes the path Windows can read, and asks Windows to
  redraw
- **`min dark` and `min light` work.** Two HKCU values, and nimo reads its own
  change back
- **`min zen` works.** Explorer stops drawing desktop icons; the files are not
  touched either way
- **`min setup` works**, with two groups that fit the machine: Explorer that
  shows extensions, opens to This PC and stops advertising in the sidebar, and
  a taskbar without task view, widgets or a search box
- One undo log serves both systems. A value that was never set is logged as
  `REG_NONE`, so it is unset through the registry and not handed to
  `defaults`, which is not on that machine
- Everything is HKCU: the signed-in user's own settings, never HKLM, never
  anything needing an administrator, never a file. nimo does not restart
  Explorer to make a setting take
- The Windows suite is 80 checks, up from 27 two versions ago

## 0.26.0

The face, the menus and Windows. Found the same way as 0.25.0 — by running
every command against a faked macOS and a faked Windows and reading what came
back — plus one bug reported with a screenshot.

- **Fixed: nimo printed its prompt on top of its own face.** The blink moved
  the cursor up six rows and came back with `\033[u`, which is not the same
  escape on every terminal. On the ones that ignore it the cursor simply stayed
  where it was, and the prompt, the hint and the whole menu landed across the
  face. It moves back down now, relatively, the way every terminal understands
- **Fixed: every menu off a terminal was an unanswerable question.** The
  fallback asked "Which one? (1-7):" and never said what 1 to 7 were. Piped,
  scripted, over ssh with no tty, or on `TERM=dumb`, `min clear` offered a
  choice you could not see. It lists and numbers them now, and takes `all`
- **Fixed: the menu counted screenshots in the wrong desktop.** It read
  `~/Desktop` while `min screenshots` read the real one — OneDrive's, or
  iCloud's. Any signed-in Windows was told it had none, and then shown five
- **The menu only offers what your computer can do.** It was a fixed list of
  seven, so Windows was offered a Dock it does not have and a Recycle Bin nimo
  is not allowed to empty. Rows are built per platform now
- **Windows, spelled the way people say it.** `min doctor` said
  `MINGW64_NT-10.0-22631 3.4.10`; it says `Windows 11 (Git Bash · x86_64)`, and
  names the Recycle Bin instead of counting a Trash folder that is not there
- `--auto` — the flag spelling of `/auto`: yes to everything, in one command
  and in the prompt
- Files still downloading were skipped in silence; the panel says how many and
  why
- ctrl-c during a pick left the terminal with no cursor until the next `reset`
- `min help` listed `min setup` twice, and never mentioned `--color`, `--help`
  or `--version`; the manual was missing eight flags. A new drift test walks
  the flag parser the way the old one walks the dispatcher, so this cannot
  come back
- `tools/screen.py` renders a raw terminal stream the way a terminal would, so
  the suite can check what is on screen and not only which bytes were sent

## 0.25.0

Found by walking every command and reading the output, rather than by waiting
for someone to hit them.

- **Fixed: `min blank` refused every relative path.** The guard that keeps nimo
  inside your home folder compares against `$HOME`, and `Documents/notes.txt`
  never starts with it — so the most natural way to type the command was the
  one way it could not be used. Paths are made absolute first now, including
  a quoted `~`, and shown back relative to home
- **Fixed: duplicates printed the folder, not the file.** Five copies in one
  folder read as five identical lines of "also in Downloads", which tells you
  nothing about which five files they were. Each copy is named in full now, in
  a stable order
- `min clean --only trash` says so in the heading instead of a stray line above
  it

## 0.24.0

- **Three ways to sort.** `--by kind` is still the default; `--by letter` files
  things under A, B, C and `#` for the rest; `--by date` files them by the
  month they were last touched. Sorting four hundred invoices by kind puts four
  hundred things in one folder — by letter or by month they land somewhere you
  can look
- **A mark for every row** in the menu and the command list, drawn from the box
  characters every terminal already has rather than an icon set with a licence
  attached
- **Fixed: `min undo` listed by kind, not by when.** Every desktop tidy came
  before every emptied file regardless of order, so the newest thing you did
  was rarely the first thing offered — which is the one job that list has
- **"make your workspace clean"** — the line the tool actually stands for, in
  the greeting, the logo, the manual and the demo

## 0.23.0

- **`min blank FILE`** — empties a file the way `> file` does, except a copy of
  the contents goes to `~/.nimo/undo` first, so `min undo` can put them back.
  If the copy cannot be made, the file is not emptied. It refuses folders, and
  it refuses anything outside your home folder
- **`min dock --fast`** — no wait before the dock slides and a quick slide,
  which is the difference between a dock that hides and one that keeps up. Both
  settings are written down first, so `min setup --restore` undoes it
- **Half a word is enough at the prompt.** `/desk` is desktop, `/dup` is
  duplicates. When half a word could be two commands, nimo lists them —
  `"doc" could be /dock or /doctor` — rather than picking one
- **A history that outlives the session**, in `~/.nimo/history`, and **ctrl-c
  cancels the line instead of ending nimo**, the way a shell does

## 0.22.0

- **A test that documentation cannot drift.** Every command nimo can dispatch
  must appear in `min help`, in the tab completions, in the manual, in the
  README and as a word at the prompt — and the version must agree with itself
  in `VERSION`, in `min version` and in this file. It found `min version`
  missing from the manual on its first run, which is exactly the sort of small
  rot it exists to stop
- **The website is the tool again.** It had drifted eleven versions behind: no
  Windows, no `/auto`, no `/clear` menu, none of the newer commands. Rebuilt,
  with the animated demo playing in the page itself rather than a screenshot
  of one

## 0.21.0

- **Windows.** Under Git Bash, MSYS2 or Cygwin, `$HOME` is already
  `C:/Users/<name>` — so the rule that keeps nimo inside your home folder holds
  there untouched. nimo finds the Desktop after Windows has moved it into
  OneDrive (and is not fooled by the empty one left behind), looks for junk
  under `AppData` instead of `~/Library`, and leaves the Recycle Bin alone,
  because it is an index as well as a folder
- **WSL is treated as Linux, on purpose.** Its home is a Linux home; the
  Windows one sits outside it, and reaching there would mean widening the one
  guard that never widens
- `test/windows.sh` — 27 checks against a faked Git Bash, and CI runs both it
  and the main suite on a real Windows machine
- **The menu weighs what it offers.** Counts, a bar apiece drawn against the
  biggest pile, and the total above it — so you can see where the mess is
  before you have chosen anything. The selected row is bold now, not merely
  pointed at

## 0.20.0

- **The face is alive.** It draws itself in a row at a time and blinks once,
  four hundred milliseconds in all — long enough to be a greeting, short enough
  that nobody waiting on a command notices it. Only with a terminal to draw on,
  a shell that can sleep in fractions, and nobody having asked for quiet
- **It blinks in the README too**, inside the animated demo, on its own timer
- `--no-animation` and `animation = off` in `~/.nimo/config` turn it off
- The eyes are their own row in one place, so the blink redraws exactly that
  line and nothing else — and a test checks `assets/demo.svg` is still what
  `tools/make-demo.py` produces, so the demo cannot drift from its source

## 0.19.0

- **The README plays.** An animated SVG of a real session — the prompt, the
  menu counting 296 downloads, the one question, the result. A GIF would be a
  megabyte and blurry on a retina screen; this is twelve kilobytes and sharp at
  any size, and the frames are text in `tools/make-demo.py`, so the demo can be
  corrected in a diff like anything else
- **Every version is a release.** All eighteen are tagged, with the changelog
  entry as the tag message, and `release.yml` cuts a GitHub release from any
  new tag — after checking the tag matches `VERSION` and both suites pass on
  the bash macOS ships. A release that does not run cannot be published
- **`brew install danielkopa/tap/nimo`** — a Homebrew formula that installs the
  tree, links `min`, and ships the man page and completions
- No `curl … | bash` line, on purpose: the argument for nimo is that you can
  read it before you run it

## 0.18.0

- **The repository looks like a project now.** A real logo — an SVG banner
  with a light and a dark variant, so it reads on both GitHub themes — the
  tagline, a row of links, and badges for CI, bash 3.2, the test count, the
  dependency count and the licence
- README rebuilt in the order people actually read: what it is, one screen of
  it working, one command to get it, and why you would trust it
- **CONTRIBUTING.md** — the invariants, bash 3.2, both suites, and the rule
  that a fix arrives with a test that fails without it
- **SECURITY.md** — where to send something privately, and the five promises
  worth trying to break
- Issue and pull request templates that ask for `min doctor` and remind people
  that `min undo` comes before the bug report

## 0.17.0

- **`/auto` — say yes once, for the whole session.** Every command asking every
  time is right at first and wearing by the twentieth. Turning it on explains
  exactly what it covers and asks once; after that nothing asks. The prompt
  reads `nimo auto ›` for as long as it lasts, so the mode is never a surprise,
  and it is off again next time you start
- `/auto off` puts the questions back. `NIMO_AUTO=1 min` starts in it.
  `/yolo` is the same thing for people who type that
- Undo still covers everything it covered before. The trash is the one
  exception and says so on the way in

## 0.16.0

- **The `/clear` menu counts what it is offering.** Desktop 85 items,
  Downloads 296 items, 12 screenshots loose — choosing is much easier when the
  menu already shows where the mess is. The Trash is one of the choices now
- **`min tidy` covers downloads and screenshots too.** It was walking past the
  folder that fills up fastest
- **Anything still arriving is left alone.** `.download`, `.crdownload`,
  `.part`, `.partial` and friends are files a browser is still writing; moving
  one breaks the download and leaves half a file under a name nobody
  recognises
- **`min doctor` says what to do next** — one line, only when there is
  something worth doing
- Sorting a few hundred files now says how far along it is

## 0.15.0

- **The frames are back.** Taking them off made nimo look like every other
  script; they were the thing that made it look like nimo. Reverted
- **A better face.** Rounded, symmetrical, and drawn so every line is the same
  width
- **`min apps`** — asks macOS when you last opened each app and lists what you
  have not touched in six months, biggest first. It reports and stops:
  uninstalling is not a decision a script should make
- **`min empty`** — takes the trash out, and tells you what that was worth.
  The one command with no undo, because the Trash already was the undo
- **Fixed: a test was killing the thing it was testing.** Piping straight into
  `grep -q` ends the pipeline at the first match, and the command behind it
  dies of SIGPIPE — so the appearance switch never got as far as switching
- Untangled two aliases: `/apps` is the app list, `/cleartrash` empties the bin

## 0.14.0

- **The frames are gone.** Every screen was sitting in a drawn box that was
  taking more attention than the thing inside it. A quiet title, room around
  it, content indented underneath — a tool for a clear desktop should not hand
  you a cluttered screen
- **`min dark` / `min light`** — switch the appearance. Asked of the system
  directly so it happens at once, with the old setting written down first
- **`min hide`** — the menu bar slides away until you reach for it.
  `--restore` brings it back
- **`min duplicates`** — the same file kept in several places. Sizes are
  grouped first, because two files of different sizes cannot be the same file,
  so only a handful are ever read. Reported and never deleted: nimo cannot know
  which copy you meant
- Restored a ShellCheck directive the zsh fix had quietly dropped

## 0.13.0

nimo is for one thing: a clean desktop. The prompt says so now.

- **`/clear`** — one word for what nimo is actually for. On its own it asks
  what should be clear and you pick: desktop, downloads, screenshots, dock,
  disk, or all of it. `/clear desktop` and `/cleardesktop` skip the asking
- The prompt lists four things — `/clear`, `/wallpaper`, `/setup`, `/undo` —
  and puts everything else on one quiet line underneath. Nothing was removed;
  it is simply no longer in the way
- `min clear desktop` works from the shell too: a command can take a second
  word now

## 0.12.2

- **Fixed: `min desktop --undo` reversed the wrong run.** The three sorters
  keep their logs in one folder, named by kind and then by time, and the newest
  was taken from the end of a glob across all of them — so `screenshots-…`
  always came out last, because s sorts after d, and the desktop's own log was
  never the one replayed. Each command now undoes its own kind, with a test
  that runs all three sorters and checks the other two are left alone
- Both suites take `-q`: only what went wrong, and the verdict

## 0.12.1

- **Fixed: sourcing the completion file in zsh printed an error on every new
  terminal.** `complete` is a bash builtin that zsh does not have until
  `bashcompinit` is loaded — so the file loads it itself now, and if the shell
  still cannot do completions it quietly does nothing instead of greeting you
  with `command not found: complete`

## 0.12.0

- **nimo has a face again.** The sketch from the very first version is what
  greets you at the prompt
- **Spaces are optional.** `/cleardesktop`, `/clear desktop`, `/clearfiles`,
  `/cleandock`, `/cleardownloads` — everything is matched twice, as typed and
  with the spaces removed, so nobody has to remember which form nimo wanted
- **`min downloads`** — the desktop sorter, pointed at `~/Downloads`
- **`min screenshots`** — gathers loose screenshots out of the desktop,
  downloads and documents into `~/Pictures/Screenshots`
- **`min zen`** — Finder stops drawing icons on the desktop. Nothing moves,
  nothing is deleted, `--restore` brings them back
- One sorter now serves desktop, downloads and screenshots, so they share the
  same rules, the same undo log and the same guarantees
- **Fixed: the prompt did not hand its flags down.** A session started with
  `-y` or `--no-color` launched its commands with neither, so a confirmation
  that had already been answered sat there waiting
- 178 checks across the two suites

## 0.11.0

- **`min` on its own is a prompt now.** Type `/clean desktop`, `/wallpaper`,
  `/undo` — the slash is optional, and so is the exact wording: `/desktop`,
  `clean desktop` and `clear desktop` all land in the same place
- Typos are matched on shared prefix, not substring, because `wallpapr`
  neither contains nor is contained by `wallpaper`. Whole lines are corrected
  too, so `/clean deskopt` comes back as "did you mean /clean desktop?" — and
  nimo suggests rather than guessing on your behalf
- Flags pass straight through: `/clean --only trash`, `/desktop --undo`
- Each command runs as its own nimo, so nothing one does leaks into the next
- `/menu` and `min --menu` still give the arrow-key list
- **Fixed: `df` returning nothing made every disk figure blow up.** On a home
  directory it cannot stat, `min doctor` printed
  `[: : integer expression expected` in the middle of the panel
- 158 checks across the two suites

## 0.10.0

nimo said everything was undoable. `min setup` was the exception. It is not
any more.

- **`min setup --restore`.** Before changing a key, nimo reads its value and
  its type and writes both down; keys that had never been set are recorded as
  never set. Restoring replays that exactly — old values with the type they
  had, never-set keys unset again rather than left at nimo's opinion. Values
  that are whole structures are marked and skipped rather than flattened
- `min undo` lists preference changes alongside desktop tidies, dock rebuilds
  and wallpapers
- **Fixed: two runs inside the same second overwrote each other's undo record.**
  Both logs are kept now, and the extra one is named so it still sorts last —
  `_2`, not `-2`, because `-` sorts before `.` and the newest would have come
  out first
- **Fixed: the guard for structured preference values matched everything.**
  `"$(printf '\n')"` looks like a newline but command substitution strips it,
  leaving an empty string that matches any value at all
- 143 checks across the two suites, all of it in CI

## 0.9.0

- **`test/macos.sh`** — 45 checks for the parts that only ever run on a Mac.
  Fake `defaults`, `osascript`, `killall`, `sw_vers`, `pmset`, `sqlite3` and
  `uname` stand in front of the real ones, and the real nimo code runs against
  them on any machine. The dock is read, rewritten, backed up and restored; the
  wallpaper is listed, set, backed up, restored and pushed through its last
  resort; every setup group is checked for the keys it writes and for the ones
  it must not
- **Fixed: a discharging battery was reported as plugged in.** `pmset` prints
  `discharging`, which contains `charging`, and the glob matched it. Found by
  the new suite on its first run, and now pinned down by one test per state
- CI runs both suites, on Linux and on macOS under bash 3.2

## 0.8.0

- **A website.** `docs/index.html` — one file, no build step, no dependencies,
  no tracking, and a theme toggle that remembers. Point GitHub Pages at
  `/docs` and it is live
- The page leads with the terminal, because that is what nimo is: the menu,
  the desktop and dock pickers, `min tidy` mid-run, and the clean report

## 0.7.0

- **`min` on its own is now a menu.** Arrow through the commands and press
  enter. Piped or on a dumb terminal it prints the help exactly as before
- **Continuous integration.** Every push runs ShellCheck, parses on bash 3.2
  and bash 5, runs the suite on Linux and on macOS under the `/bin/bash` that
  macOS actually ships, and installs then uninstalls. The bash 3.2 promise is
  now a job that fails if it stops being true
- `install.sh` refuses to finish if the thing it just linked does not run
- `uninstall.sh` also removes the man page, and says where `~/.nimo` is

## 0.6.0

- **Arrow keys.** `min dock`, `min wallpaper` and `min undo` are now proper
  pickers: ↑↓ to move, space to tick, a for all, n for none, enter, q. Pure
  bash, no curses, no dependencies. A pipe or a dumb terminal falls back to
  typing numbers, so nothing ever becomes impossible
- **`min undo`** — everything nimo has ever done in one list, newest first.
  Pick a line and that change is reversed
- **Six times faster scanning.** Measuring is waiting on the disk, so targets
  are measured six at a time. `jobs` in the config changes how many
- **`~/.nimo/config`** — `days`, `limit`, `jobs`, `color`, `tidy`. Read, never
  sourced: nothing in it can run as code
- **`man min`**, installed by `install.sh`
- `min doctor` also reports memory and battery
- The test suite drives the picker with simulated keystrokes — 76 checks

## 0.5.0

nimo stops being a disk cleaner and becomes what it was always meant to be:
a way to make a Mac feel minimal.

- `min tidy` — desktop, dock, wallpaper and preferences in one pass, each step
  asking first
- `min desktop` — everything on your desktop moves into `Desktop/Tidy/`, sorted
  by what it is. Nothing deleted, nothing renamed, hidden files left alone, and
  every move logged so `min desktop --undo` puts all of it back exactly where
  it was
- `min dock` — lists your dock, marks what Apple put there, removes only the
  numbers you name. Exports the whole dock first, so `min dock --restore` works
- `min wallpaper` — the wallpapers macOS already ships with, nimo's pick
  marked, `--random` and `--restore`
- Fixed a counting bug where an empty list read as "not empty", which made
  `min desktop` write an empty undo log instead of saying there was nothing
  to do

## 0.4.0

- A real wordmark instead of the placeholder sketch, and it steps aside: the
  full logo shows for `min` and `min help`, everything else gets one quiet
  line so the output you asked for stays on screen
- Narrow terminals fall back to the short header automatically
- Panelled output: every screen sits in a titled frame, sizes over a gigabyte
  colour themselves, and nothing wraps at eighty columns any more
- A file that is already counted as junk no longer shows up a second time
  under "files over 500 MB"
- `test/run.sh` — 42 checks against a fake computer in `/tmp`, including a
  full clean that compares the promised number against the freed number

## 0.3.0

- `min top` — the biggest folders in your home, with proportional bars
- `min doctor` — system, uptime, disk, clutter and total junk on one screen
- `min update` — pulls the newest nimo into whichever folder it lives in
- `--json` — machine readable output for `clean` and `preview`
- `--limit N` for `min top`
- Free disk space is shown in the report and again after cleaning
- Tab completion for bash and zsh
- Caches nested inside other caches are no longer counted twice
- Empty directories no longer show up as a few stray kilobytes

## 0.2.0

The first version that actually does something.

- `min clean` — real scanner across 16 targets, split into *safe* (nimo may
  delete after you confirm) and *worth a look* (nimo only ever reports)
- `min preview` — the same scan with deletion made impossible
- `min setup` — five groups of macOS preferences, each applicable on its own
- `min help`, `min version`
- Flags: `--dry-run`, `--yes`, `--only`, `--days`, `--list`, `--no-color`, `--quiet`
- Safety guard that refuses any path outside `$HOME`
- `install.sh` / `uninstall.sh`
- Split into `lib/ui.sh`, `lib/core.sh`, `lib/scan.sh`, `lib/clean.sh`, `lib/setup.sh`

## 0.1.0

- The Nimo startup screen and the command skeleton
