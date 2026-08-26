```
   ███╗   ██╗██╗███╗   ███╗ ██████╗
   ████╗  ██║██║████╗ ████║██╔═══██╗
   ██╔██╗ ██║██║██╔████╔██║██║   ██║
   ██║╚██╗██║██║██║╚██╔╝██║██║   ██║
   ██║ ╚████║██║██║ ╚═╝ ██║╚██████╔╝
   ╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝ ╚═════╝

   make your computer feel better
```

**nimo** is a small command line tool for macOS. It looks at the places where
junk quietly piles up, tells you how much space each one is wasting, and — only
after you say yes — cleans them out.

It is one bash script, six small libraries and a test suite. No dependencies,
no daemon, no account, nothing running in the background. You can read the
whole thing in ten minutes, which is the point: a cleaner you cannot read is a
cleaner you should not trust with your disk.

```
$ min preview

  ╭─ safe to clean ───────────────────────────────────

     App caches                        4.2 GB  your apps rebuild them
     Xcode derived data                8.7 GB  rebuilt on your next build
     Trash                             1.1 GB  already thrown away
     npm / yarn / pnpm cache           812 MB  download caches
     Application logs                  143 MB  old log files

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

  preview only — nothing was deleted
```

```
$ min doctor

  ╭─ your computer ───────────────────────────────────

     System       macOS 15.5 (arm64)
     Uptime       4 days, 2 hrs
     Disk         231 GB free of 494 GB  ████████░░░░░░░░

     Desktop      41 items
     Downloads    212 items
     Trash        18 items

     Junk         15.0 GB  → min clean

     nimo         v0.4.0  /usr/local/bin/min

  ╰────────────────────────────────────────────────────
```

## Install

```bash
git clone git@github.com:danielkopa/nimo.git ~/nimo
cd ~/nimo
./install.sh
```

That puts a `min` symlink on your PATH, so you can run `min` from anywhere.
Later, `min update` pulls the newest version — the symlink keeps working.

To remove it again: `./uninstall.sh`. The repository itself is left alone.

## Commands

| Command | What it does |
| --- | --- |
| `min` | shows nimo and the command list |
| `min preview` | scans everything, guaranteed to change nothing |
| `min clean` | the same scan, then offers to free up the safe part |
| `min top` | the biggest folders in your home, with bars |
| `min doctor` | disk, uptime, clutter and junk in one screen |
| `min setup` | applies a small, sane set of macOS preferences |
| `min update` | `git pull` in whichever folder nimo lives in |
| `min help` | the command list |
| `min version` | the version |

## Options

| Option | Meaning |
| --- | --- |
| `-n`, `--dry-run` | show what would happen, change nothing |
| `-y`, `--yes` | skip the confirmation question |
| `--only a,b` | limit to certain items or setup groups |
| `--days N` | what counts as an old download (default 30) |
| `--limit N` | how many rows `min top` shows (default 15) |
| `--json` | machine readable output for `clean` and `preview` |
| `--list` | list the setup groups |
| `--no-color` | plain output |
| `-q`, `--quiet` | no banner |

```bash
min doctor
min top --limit 20
min clean --only trash,user-caches
min clean --days 90
min setup --only dock,finder
min setup --dry-run
```

## What `min clean` touches

Everything nimo knows about falls into one of two groups.

**Safe** — nimo deletes these once you confirm. All of them are caches your
apps rebuild by themselves:

| id | what |
| --- | --- |
| `user-caches` | `~/Library/Caches` |
| `logs` | `~/Library/Logs` |
| `crash-reports` | `~/Library/Logs/DiagnosticReports` |
| `trash` | `~/.Trash` |
| `quicklook` | QuickLook thumbnail cache |
| `mail-downloads` | Mail's copies of opened attachments |
| `xcode` | DerivedData and simulator caches |
| `homebrew` | Homebrew's download cache |
| `node` | npm, yarn and pnpm caches |
| `python` | pip's wheel cache |

**Worth a look** — nimo measures these and shows them to you, and that is all
it ever does with them. It will not delete them, not even with `--yes`:

| id | what |
| --- | --- |
| `downloads` | files in `~/Downloads` older than `--days` |
| `ios-backups` | iPhone and iPad backups |
| `xcode-archives` | your shipped app builds |
| `device-support` | Xcode device support files |
| `node-modules` | `node_modules` folders in your home folder |
| `big-files` | files over 500 MB |

Caches that live inside other caches — Homebrew and pip sit inside
`~/Library/Caches` — are counted once, so the total is the number you actually
get back.

## Rules nimo follows

- **Nothing happens without a yes.** `min clean` scans, shows you the number,
  and waits. `min preview`, `min top` and `min doctor` cannot delete anything
  at all.
- **Only inside your home folder.** nimo refuses any path outside `$HOME`, and
  refuses `$HOME` itself, `/`, `/System`, `/Applications` and friends. The
  guard is in `lib/core.sh` and it is four lines long.
- **No sudo. Ever.** If something needs administrator rights, nimo skips it.
- **Documents are not junk.** nimo has no idea what is in your Documents,
  Desktop or Pictures folders and never looks inside them.
- **The number you see is the number you get.** After cleaning, nimo measures
  again and reports what was actually freed, not what it hoped to free.

## What `min setup` changes

Preferences only — `defaults write`, the same thing you would type by hand. No
files are touched and nothing needs sudo. Run `min setup --dry-run` to see
every command before anything happens.

| group | what |
| --- | --- |
| `finder` | show extensions, path bar, list view, folders first |
| `dock` | auto-hide instantly, no recent apps, smaller icons |
| `screenshots` | save to `~/Desktop/Screenshots` as png, no drop shadow |
| `keyboard` | fast key repeat, hold a key to repeat it |
| `dialogs` | always expand save and print panels |

## Scripting

`--json` turns `clean` and `preview` into something you can pipe. Sizes are in
bytes; nothing is deleted unless you also pass `--yes`.

```bash
min preview --json | jq '.safe_bytes'
min clean --json --yes | jq '.freed_bytes'
```

## Tests

```bash
bash test/run.sh
```

Forty-two checks: every command and flag, the safety guard, and a full clean
of a fake computer — measured, cleaned, measured again, with the promised
number compared against the freed number. It all happens in a throwaway folder
in `/tmp` with its own fake `HOME`. Your real files are never read, never
measured, never touched.

## Tab completion

```bash
echo 'source ~/nimo/completions/min.bash' >> ~/.zshrc
```

zsh needs `autoload -U bashcompinit && bashcompinit` before that line.

## Layout

```
nimo
├── min                    the command itself: flags, dispatch, help
├── install.sh             puts min on your PATH
├── uninstall.sh           takes it off again
├── completions/min.bash   tab completion
├── test/run.sh            the test suite
└── lib
    ├── ui.sh              banner, colors, bars, the way output looks
    ├── core.sh            sizes, disk, confirmation, the safety guard
    ├── scan.sh            every place nimo knows how to look
    ├── clean.sh           scan, report, clean, json
    ├── setup.sh           the macOS preferences
    └── tools.sh           top, doctor, update
```

Teaching nimo about a new place is one call to `nimo_register` in
`lib/scan.sh`:

```bash
nimo_register slack "Slack cache" contents safe \
    "rebuilt when Slack starts" \
    "$HOME/Library/Application Support/Slack/Cache"
```

## Requirements

macOS with the bash that ships with it (3.2) or anything newer. `min clean`,
`min top` and `min doctor` also work on Linux with a smaller set of targets;
`min setup` is macOS only. Checked with ShellCheck, tested with
`test/run.sh`.

## License

MIT — see [LICENSE](LICENSE).
