# Changelog

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
