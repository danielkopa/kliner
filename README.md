```
   ███╗   ██╗██╗███╗   ███╗ ██████╗
   ████╗  ██║██║████╗ ████║██╔═══██╗
   ██╔██╗ ██║██║██╔████╔██║██║   ██║
   ██║╚██╗██║██║██║╚██╔╝██║██║   ██║
   ██║ ╚████║██║██║ ╚═╝ ██║╚██████╔╝
   ╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝ ╚═════╝

   make your computer feel better
```

[![ci](https://github.com/danielkopa/nimo/actions/workflows/ci.yml/badge.svg)](https://github.com/danielkopa/nimo/actions/workflows/ci.yml)

**[nimo.sh →](https://danielkopa.github.io/nimo/)** — the page, if you would rather look than read.

**nimo** makes a Mac feel minimal again. A desktop with nothing on it. A dock
with only the apps you actually open. A calm wallpaper. Sane preferences. And,
once all that is true, a disk without fifteen gigabytes of cache on it.

One command does the whole thing:

```bash
min tidy
```

Four steps, each one asks before it does anything, and each one can be undone.

It is one bash script and eleven small libraries. No dependencies, no daemon, no
account, nothing running in the background. You can read the whole thing in
fifteen minutes, which is the point: a tool that rearranges your files and your
dock is a tool you should be able to read.

## Install

```bash
git clone git@github.com:danielkopa/nimo.git ~/nimo
cd ~/nimo
./install.sh
```

That puts a `min` symlink on your PATH, so you can run `min` from anywhere.
Later, `min update` pulls the newest version. To remove it: `./uninstall.sh`.

## The way in

`min` on its own is a prompt. Type what you want:

```
   ███╗   ██╗██╗███╗   ███╗ ██████╗
   ████╗  ██║██║████╗ ████║██╔═══██╗
   ██╔██╗ ██║██║██╔████╔██║██║   ██║
   ██║╚██╗██║██║██║╚██╔╝██║██║   ██║
   ██║ ╚████║██║██║ ╚═╝ ██║╚██████╔╝
   ╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝ ╚═════╝

   make your computer feel better

  type a command, or / to see them all. ctrl-d to leave.

  nimo › /clear
  nimo › /wallpaper
  nimo › /undo
```

`/clear` asks what should be clear — desktop, downloads, screenshots, dock,
disk — and you pick with the arrow keys. Say it outright if you prefer:
`/clear desktop`, or `/cleardesktop`.

The slash is optional, the spaces are optional, and so is remembering the exact
word: `/desktop`, `/cleardesktop`, `/clear desktop`, `/clearfiles` and
`/sort desktop` all mean the same thing. Typos are caught
by shared prefix rather than substring, so `/wallpapr` and even
`/clean deskopt` are understood — nimo says what it thinks you meant and waits
rather than guessing on your behalf.

Flags work at the prompt too: `/clean --only trash`, `/desktop --undo`.
`/menu` switches to picking with the arrow keys, and `min --menu` starts there.

Piped into anything, `min` prints the help it always did.

Piped into anything, or in a terminal that cannot do it, the same `min` prints
the help it always did.

## A minimal mac

### `min desktop`

Everything on your desktop moves into `Desktop/Tidy/`, sorted by what it is —
Screenshots, Images, Documents, Video, Audio, Archives, Code, Folders, Other.

```
  ╭─ your desktop ────────────────────────────────────

     Screenshots                     23 items
     Images                          11 items
     Documents                        8 items
     Archives                         3 items
     Folders                          2 items

     ─────────────────────────────────────────
     On your desktop                 47 items

  ╰────────────────────────────────────────────────────

  everything moves into  Desktop/Tidy/<kind>/
  nothing is deleted, nothing is renamed
```

Nothing is deleted. Nothing is renamed — if a name is already taken, the new
file becomes `invoice 2.pdf`. Hidden files are left alone. Every single move is
written down in `~/.nimo/undo/`, so:

```bash
min desktop --undo
```

puts all forty-seven back exactly where they were, down to the folder.

### `min downloads` · `min screenshots`

`min downloads` is the same sorter pointed at `~/Downloads` — the folder that
quietly reaches three hundred items while you are not looking. Same rules, same
undo log, same `--undo`.

`min screenshots` gathers every loose screenshot out of your desktop, downloads
and documents into `~/Pictures/Screenshots`. It only touches files it
recognises as screenshots, by name, and puts them all back with
`min screenshots --undo`.

### `min dark` · `min hide`

Two switches, both preferences, both written down before they are touched and
both reversible with `min setup --restore`. `min dark` flips the appearance
(`min light` flips it back); `min hide` lets the menu bar slide away until you
reach for it.

### `min duplicates`

The same file, kept in three places. nimo groups by size first — two files of
different sizes cannot be the same file — and only reads the handful of
candidates left over. It reports them and stops there: it cannot know which
copy you meant to keep, so it does not choose.

### `min zen`

The fastest calm desktop there is: Finder stops drawing icons on it. Nothing
moves, nothing is deleted, everything is still in `~/Desktop` and still in
Finder. `min zen --restore` brings the icons back.

### `min dock`

nimo lists what is in your dock, marks the ones Apple put there, and asks which
numbers should go. It never decides for you.

```
  ╭─ your dock ───────────────────────────────────────

      1  Finder
      2  Safari
      3  Mail
      4  Freeform                  came with macOS
      5  TV                        came with macOS
      6  Terminal

  ╰────────────────────────────────────────────────────

  Numbers to remove, separated by spaces (enter keeps everything):
```

In a real terminal that list is a picker: **↑↓** to move, **space** to tick,
**a** for all, **n** for none, **enter** to confirm, **q** to cancel. Piped
into a script, or in a terminal that cannot do it, the exact same question is
asked by typing numbers instead. Nothing ever becomes impossible, only less
pleasant.

The apps stay installed — only the icons go. Your whole dock is exported first,
so `min dock --restore` brings back exactly what you had.

### `min wallpaper`

The wallpapers macOS already ships with, listed, with nimo's own pick marked.
Nothing is downloaded. `--random` if you cannot decide, `--restore` to go back.

### `min undo`

Everything nimo has ever done, in one list, newest first. Pick a line and that
change is reversed — that desktop tidy, that dock, that wallpaper. Nothing else
is touched.

```
  ╭─ what nimo has done ──────────────────────────────

   ▸ cleared your desktop   26.08.2026 16:44   47 files
     rebuilt your dock      26.08.2026 16:41
     changed your wallpaper                    back to Sonoma

  ╰────────────────────────────────────────────────────

  ↑↓ move   enter reverse   q cancel
```

This is the reason nimo is allowed to touch anything at all.

### `min setup`

Preferences only — `defaults write`, the same thing you would type by hand. No
files touched, no sudo. `min setup --dry-run` shows every command first.

| group | what |
| --- | --- |
| `finder` | show extensions, path bar, list view, folders first |
| `dock` | auto-hide instantly, no recent apps, smaller icons |
| `screenshots` | save to `~/Desktop/Screenshots` as png, no drop shadow |
| `keyboard` | fast key repeat, hold a key to repeat it |
| `dialogs` | always expand save and print panels |

## And then the disk

### `min preview` · `min clean`

```
  ╭─ safe to clean ───────────────────────────────────

     App caches                        4.2 GB  your apps rebuild them
     Xcode derived data                8.7 GB  rebuilt on your next build
     Trash                             1.1 GB  already thrown away
     npm / yarn / pnpm cache           812 MB  download caches

     ─────────────────────────────────────────
     Total                            15.0 GB
     Disk         231 GB free of 494 GB

  ╰────────────────────────────────────────────────────

  ╭─ worth a look ────────────────────────────────────

     nimo never deletes anything in this section

     node_modules folders              6.4 GB  23 items · npm install brings them back
     Old downloads                     2.9 GB  41 items · untouched for a while
     iPhone / iPad backups              11 GB  2 items · losing these loses backups

  ╰────────────────────────────────────────────────────
```

`min preview` cannot delete anything. `min clean` runs the same scan and then
asks. Everything in **safe to clean** is a cache your apps rebuild by
themselves: `user-caches`, `logs`, `crash-reports`, `trash`, `quicklook`,
`mail-downloads`, `xcode`, `homebrew`, `node`, `python`.

Everything in **worth a look** is measured and shown and never touched, not
even with `--yes`: `downloads`, `ios-backups`, `xcode-archives`,
`device-support`, `node-modules`, `big-files`.

### `min top` · `min doctor`

`min top` ranks the biggest folders in your home with bars. `min doctor` puts
disk, uptime, desktop clutter and total junk on one screen. Neither one changes
anything.

## Commands

| Command | What it does |
| --- | --- |
| `min clear` | pick what should be clear — desktop, downloads, screenshots, dock, disk |
| `min tidy` | desktop, dock, wallpaper and preferences, in order |
| `min desktop` | clear your desktop — `--undo` puts it back |
| `min downloads` | the same sorter, pointed at `~/Downloads` |
| `min screenshots` | gather every loose screenshot into `~/Pictures/Screenshots` |
| `min zen` | stop drawing icons on the desktop at all — `--restore` brings them back |
| `min dark` · `min light` | switch appearance |
| `min hide` | let the menu bar slide away — `--restore` brings it back |
| `min duplicates` | the same file, kept more than once — reported, never deleted |
| `min dock` | pick what stays — `--restore` puts it back |
| `min wallpaper` | pick one macOS already has — `--restore` puts it back |
| `min undo` | everything nimo has done, and a way back |
| `min clean` | free up the caches, after asking |
| `min preview` | the same scan, unable to delete |
| `min top` | the biggest folders in your home |
| `min doctor` | how your computer is doing |
| `min setup` | a small, sane set of macOS preferences |
| `min update` | pull the newest nimo |
| `min help` · `min version` | the basics |

## Options

| Option | Meaning |
| --- | --- |
| `-n`, `--dry-run` | show what would happen, change nothing |
| `-y`, `--yes` | skip the confirmation question |
| `--undo` | put your desktop back the way it was |
| `--restore` | put the dock or the wallpaper back |
| `--random` | let nimo pick the wallpaper |
| `--menu` | pick from a list with the arrow keys |
| `--list` | list what a command offers, without asking anything |
| `--only a,b` | limit to certain items or setup groups |
| `--days N` | what counts as an old download (default 30) |
| `--limit N` | how many rows `min top` shows (default 15) |
| `--json` | machine readable output for `clean` and `preview` |
| `--list` | list the setup groups |
| `--no-color` | plain output |
| `-q`, `--quiet` | no banner |

## Rules nimo follows

- **Nothing happens without a yes.** Every command that changes something
  shows you what it is about to do and waits.
- **Everything is undoable.** Desktop moves are logged file by file. The dock
  is exported before it is touched. The old wallpaper is written down.
- **Only inside your home folder.** nimo refuses any path outside `$HOME`, and
  refuses `$HOME` itself, `/`, `/System`, `/Applications` and friends. The
  guard is in `lib/core.sh` and it is four lines long.
- **No sudo. Ever.**
- **Nothing is downloaded.** Wallpapers come from what macOS already ships.
- **The number you see is the number you get.** After cleaning, nimo measures
  again and reports what was actually freed.

## Configuration

Optional. `~/.nimo/config`, one `key = value` per line:

```
days  = 60
limit = 25
jobs  = 8
color = never
tidy  = Desktop Tidy
```

It is **read, not sourced** — nothing in that file can run as code, whatever
ends up in it. Anything typed on the command line still wins.

## Speed

Measuring is almost entirely waiting on the disk, so nimo measures six places
at a time instead of one after another. On a Mac with a large
`~/Library/Caches` and an Xcode folder that is the difference between a scan
you wait for and a scan you do not. `jobs` in the config changes how many.

## Manual page

`./install.sh` puts one where your system keeps them:

```bash
man min
```

## Tests

```bash
bash test/run.sh      # 133 checks — everything that runs anywhere
bash test/macos.sh    # 80 checks — the parts that only run on a Mac

bash test/run.sh -q   # only what went wrong, and the verdict
```

The dock, the wallpaper and the preferences only ever run on a Mac, which used
to make them the parts nobody could test. `test/macos.sh` stands fake
`defaults`, `osascript`, `killall`, `sw_vers`, `pmset`, `sqlite3` and `uname`
in front of the real ones and runs the real nimo code against them — on any
machine, without touching a real dock or a real wallpaper. It checks that the
right apps leave the dock and the rest keep their order, that the backup is
written *before* anything changes, that `--restore` brings all of it back, that
`setup --dry-run` writes nothing at all, that no line anywhere reaches for
sudo, and that the wallpaper falls through to its last resort when macOS
refuses. It has found three real bugs so far. `pmset` says `discharging`, which
contains `charging`, so a battery on its way down was reported as plugged in.
The guard meant to spot a structured preference value used
`"$(printf '\n')"`, which collapses to an empty string — so it matched every
value and nothing was ever recorded. And two runs inside one second produced
the same log name, where the second truncated the first and took the only
record of how to undo it with it.

Every push runs everything on GitHub Actions: ShellCheck, a parse on both bash
3.2 and bash 5, both suites on Linux, **both suites on macOS under
`/bin/bash` — the actual 3.2 that ships with macOS** — and an
install-then-uninstall round trip. The bash 3.2 claim in this README is not a
claim; it is a job that fails if it stops being true.

A hundred and thirty-three checks in `test/run.sh` against a fake computer in `/tmp` with its own fake `HOME`: every
command and flag, the safety guard, the arrow-key picker driven by simulated
keystrokes, the menu, the undo history, the config file, the desktop sorted and then
fully undone, and a complete clean where the promised number is compared
against the freed number. Your real files are never read, never measured, never touched.

## Scripting

```bash
min preview --json | jq '.safe_bytes'
min clean --json --yes | jq '.freed_bytes'
```

## Tab completion

```bash
echo 'source ~/nimo/completions/min.bash' >> ~/.zshrc
```

That is the whole thing — zsh needs `bashcompinit` to run bash completions,
and the file loads it itself. If the shell cannot do completions at all it
does nothing rather than printing an error at you every time you open a
terminal.

## Layout

```
nimo
├── min                    the command itself: flags, dispatch, help
├── install.sh             puts min on your PATH
├── uninstall.sh           takes it off again
├── .github/workflows      shellcheck, bash 3.2, linux, macos, install
├── docs/index.html        the website, in one file
├── completions/min.bash   tab completion
├── man/min.1              the manual page
├── test/run.sh            the suite that runs anywhere
├── test/macos.sh          the macOS parts, against a fake macOS
└── lib
    ├── ui.sh              banner, panels, bars, the way output looks
    ├── core.sh            sizes, disk, config, the safety guard
    ├── pick.sh            choosing things with the arrow keys
    ├── repl.sh            the prompt, and what it understands
    ├── desktop.sh         the sorter behind desktop, downloads and screenshots
    ├── dock.sh            reading and rebuilding the dock
    ├── wall.sh            the wallpaper
    ├── look.sh            appearance and the menu bar
    ├── dupes.sh           the same file, more than once
    ├── undo.sh            the history, and the way back
    ├── scan.sh            every place nimo knows how to look
    ├── clean.sh           scan, report, clean, json
    ├── setup.sh           the macOS preferences
    └── tools.sh           tidy, top, doctor, update
```

Teaching nimo about a new place to scan is one call to `nimo_register` in
`lib/scan.sh`:

```bash
nimo_register slack "Slack cache" contents safe \
    "rebuilt when Slack starts" \
    "$HOME/Library/Application Support/Slack/Cache"
```

## Requirements

macOS with the bash that ships with it (3.2) or anything newer. `min desktop`,
`min clean`, `min top` and `min doctor` also work on Linux; `min dock`,
`min wallpaper` and `min setup` are macOS only. Checked with ShellCheck.

## The website

`docs/index.html` is the whole site: one file, no build step, no dependencies,
no tracking. To put it online, open **Settings → Pages** on GitHub, set the
source to the `main` branch and the folder to `/docs`. It lands at
`danielkopa.github.io/nimo`.

## License

MIT — see [LICENSE](LICENSE).
