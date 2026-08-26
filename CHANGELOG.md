# Changelog

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
