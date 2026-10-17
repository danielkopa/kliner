# nimo — working notes

nimo makes a Mac feel minimal: a clear desktop, a dock with only what you open,
a calmer wallpaper, sane preferences, and the disk back. One bash script and
thirteen small libraries. No dependencies, no daemon, no network.

The point of the project is the **desktop**, not the disk. Cleaning caches is a
side dish. When in doubt, make the desktop calmer.

```bash
./min                 # the prompt — this is the front door
./min clear desktop   # or say it outright
bash test/run.sh -q   # 649 checks, anywhere
bash test/macos.sh -q # 183 checks, the macOS-only parts, faked
bash test/windows.sh -q # 190 checks, the Windows parts, faked
bash app/build.sh     # Nimo.app — on a Mac only
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
lib/startup.sh         what launches when you sign in
lib/win.sh             the Windows side: registry, PowerShell, recycle bin
lib/blank.sh           the empty-desktop pass
lib/rename.sh          a new name for a file, written down first so undo gives it back
lib/tools.sh           clear, tidy, top, doctor, update, the menu

app/Sources/main.swift the menu bar app — a window on min, not a rewrite
app/Sources/Nearby.swift sending a file to an @username: Macs on the same
                       network, found with Bonjour, no server, the bytes as they are
app/Sources/Cloud.swift the same to an @username anywhere, through kliner.app,
                       encrypted on this Mac first; and the public profiles
app/Sources/Desk.swift the icons on your desktop: what \ writes, straight,
                       without min — both of the Mac's switches, and Finder's
                       older way when the Mac does not take them
server/                Kliner Cloud: a Cloudflare Worker with D1 and R2.
                       SPEC.md is the contract; deploy.sh puts it up
app/Info.plist         __VERSION__ is filled in by build.sh
app/build.sh           swiftc + sips + iconutil + codesign + ditto
app/Resources/         the menu bar glyph, three scales
assets/app/icon-1024.png  the one picture every icon size comes from
docs/index.html        the site, and the Download button
```

The app is not allowed to become a second implementation. It shells out to the
bundled `min` and shows what came back — if a menu item needs new behaviour,
the behaviour goes in a library and the menu names the command. `--yes` is
appended in exactly one place, after a dialog returned yes, and `test/run.sh`
checks that it is never written into an action.

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
- **The Mac's tools are BSD's.** `du -a -d 1` is GNU only: the du on a Mac
  refuses the pair and prints its usage, so `min top` — Kliner's Storage page
  — listed nothing ("nothing in here worth measuring") on every Mac while
  every Linux check passed. Measure children with
  `find DIR -mindepth 1 -maxdepth 1 -exec du -sk {} +`. `test/run.sh` puts a
  du as strict as the Mac's in front of the real one to keep it that way.
- **One space is not a column.** The window splits nimo's lines on two or
  more spaces. `printf '%-28s %s'` pads short names to two spaces and more,
  but a name of 28 characters or longer gets exactly one, and the line stops
  being a label and a value: Startup dropped every agent with a long bundle
  id (it said "5 things" and drew three), and a long wallpaper name lost its
  "on now". Every padded label that is followed by a value is
  `'%-Ns  %s'`, with the two spaces written out.

## The window

Kliner follows the Mac, and since v18 its window is the Claude app's way,
which Dan asked for by name after the preview film ("clean, in the fonts you
have"): warm paper by day (`#faf9f5` the page, `#f3f1ea` the side) and warm
charcoal by night (`#262624`, `#1f1e1d`), and fewer boxes. The type is Geist,
one face for everything (`--font`, bundled in `app/Resources/fonts`), the
titles and the big figures in its semibold, set tight: a serif for the titles,
the way Claude has it, was tried first (Newsreader with Figtree), and Dan
called those fonts awful and picked Geist alone out of four. The Swift side is
set in the same face (`Words.face`) and painted in the same colours (`Paint`).
The shape is still the one v17 took from Efferd's dashboard. The sidebar (256
points, `.sb`, drawn once in `drawFrame`) is the window's glass (`html.glass`:
the sidebar material behind the page, under a thin veil of the side's own
paper, `--veil`, 34% of it: enough to keep the words on it readable and the
wallpaper's colour quiet, not enough to hide that it is glass — v18's veil was
86%, which made the glass paper, and Dan asked for it back, "100%", with his
pictures 1, 2 and 3), and since v20 the page floats on that glass again: inset
8 points from the window's edge, 14-point corners, a hairline and a soft
shadow under it (`.main`, `--page-lift`). The pane on Send is the same glass.
In the sidebar: Kliner's mark and ⌘B on the lights' line (the top strip is the
title bar's: 13 points down, the lights end at x = 72), the search field with
its ⌘ K keys, then six names, not fifteen — Home, Send, and one line for each
place (`placeSpot`), each with what is waiting in it (`tally`), and one light
(`#railmark`, inside `.sb-places`, moved by `lightSide`) that slides to the
place you are in. A place's pages are the tabs along the top in the bar
(`drawWhere`), folded or open. At the foot Help, Settings and you (`youRow`:
your picture, name and @username), which opens Settings at your profile.
Folded (⌘B, remembered as `frame = rail`; open is the default) it is the same
list as pictures, 76 points wide for the lights, and the bar gets search of
its own. The bar says where you are and, on the right, what Kliner is doing
(`paintState`).

**A card is one surface with its name inside it.** Efferd's tray with a
sheet laid in it is gone: `.ef-tray` is the card (white on the paper,
`#30302e` on the charcoal, a hairline, a 16-point corner) with its name
along the top in the sans and a small picture, and on the right one small
button for what goes with it; `.ef-sheet` is only the part of it you click.
The four figures on Home are one card, four cells with a hairline between
them. Every other page's blocks are the same cards with CSS alone: the panel
is the card, its `.cap` the name along the top. Charts are warm grey, never
coloured: soft solid bars with round tops, the series in three greys, the
third hatched so the three read apart without a colour; the disk is a gauge
of thirty-two ticks with how full it is in the middle.

**Every surface is a token.** The v18 block at the end of style.css sets
Efferd's names (`--e-*`), the window's older ones (`--bg`, `--ink`, `--muted`,
`--line`, …) and the card's (`--c-card`, `--c-line`) to the same values, light
in `:root` and dark in one `@media (prefers-color-scheme: dark)` after it — so
a new colour goes in both, and a literal written into a rule is the bug. Green
for done and for a figure that moved the right way, red for what did not;
everything else is a warm grey. Nothing in Swift pins an appearance:
`Web.ground` is the duo the window is painted before the page loads, and both
the window and the ⌘K panel take the system's. The pane on the right
(`inspFrame`, `paintInsp`, 372 points) is Send's alone now (`paneHere`): the
file on its way and the box you send from. A window under 1180 points wide
keeps it behind the button at the right of the bar.

Class names that were already taken, so the new ones are not: `.chip` is the
label over a chart (Efferd's charts draw it as `#chip.ef`), `.person` the old
row of names, `.who`/`.pp` too (the people are `.sp`), `.todo`, `.done`,
`.mac`, `.files`, `.quick`, `.dash` and `.live`. `.dt` is a tile in the
small Dock and nothing else: a table class of the same name with negative
margins once piled the starter's Dock up on itself, which was the "broken
Dock" Dan saw. v19 added its own, all free before it: `.rd`/`.rd-s` a
rolling digit, `[data-fig]` a figure that can roll, `.ef-viz` a figure's
small picture, `.sg` a switch's light, `.fglide` ⌘K's, `.isl` the island,
`.glt` the greeting's letters, and `.seg` is also a bar segment
(`.stack .seg`) and an SVG arc (`svg.ring .seg`), so the switch is `div.seg`.

Layout follows the room the page has, not the window (`container-type` on
`.page` and `.ef-home`, `@container` rules): four figures go to two, the
three trays to one column.

The first minute (`INTRO`) lands rather than appears: the eyes drop in, the
words come one after another, then what Kliner does and the key (↵). Steps
move like pages, forward from the right and back from the left, with one
segment per step filling in. The small Mac stands in the light of its own
wallpaper (`glowFrom` on the picture; `--glow-1` and `--glow-2` are
registered with `@property`, so a new wallpaper eases the light to its
colour). Both Docks answer the pointer the way the real one does
(`magnify`: the icon under it grows, its neighbours less, out to two and a
half icons, the row opening up round it) and an icon you click hops
(`hop`).

Your account is one step since v21 (`account` in `INTRO`; Dan: "and you did
not make the login better either"): what were two steps — your name and email,
then your @username — is one form laid the way an app's sign-up is
(`accountStage`): Name, Email (kept on this Mac) and Username, three boxes the
same size with their names over them, and Open Kliner when you log in under
them. Beside the form your card (`idCard`, painted by `userPaint` as you
type): your wallpaper across its top, your picture over it — click it for
another — your name, your @username, its address and what kliner.app said
about it as a pill. One button, Create account (`introAccount`): the email
first, then it claims the name (`introClaim`), throws a handful of grey paper
(`burst`) and goes on by itself a moment later. Skip the username
(`introSkipName`) still asks for the email. With a name already yours the step
says Your Kliner account and the button Continue. Under the username box the
address it will have and what kliner.app said; when a name is taken,
`offerIdeas` asks kliner.app about a few close to it (`nameIdeas`) and offers
only the ones that came back free; a name held on kliner.app opens the box for
its code (`#ucode`). Each answer is kept a minute (`NAMES_SEEN`).

## Home

Home is a dashboard in the Claude app's manner (`drawHome`), every figure on
it read from this Mac. The greeting is its title (`greeting`, from `dayPart`),
with Clean all on the right when there is more than one thing it would do
(`cleanSweep`); how old the reading is and Refresh are in the bar (`#refresh`,
shown only on Home). Then four figures in one card (`homeKpis`, `kpiTray`):
Free, Can be freed, Desktop and Downloads — the number with its unit smaller
and grey, a small picture of it on the right (a donut of the disk for Free and
for Can be freed, `donutViz`, every part in its own grey with a gap between:
what is used is the dark part and what is free the light gap, with what
cleaning would free between them in a middle grey — one short dark arc on a
pale ring, the free part drawn, read as loading twice; for Desktop and
Downloads a line of what landed each day of the last two weeks, `sparkViz`,
drawn once the folder has been read, `paintSparks`), and under it how far it
moved since the reading the window opened on
(`K.base`, the last reading Kliner kept, `lastLook`; `moved`: a round arrow
and the amount, green the way you want, red not, then since when) or, when it
did not move, one line about it. The button in a cell's top does the thing
(Clean, Tidy); the rest of the cell opens its page.

Under the figures, since v20 (Dan: "add the sender too, and the rest, so Home
is not so empty"), two cards side by side (`homeToday`). Send a file is the
one send box (`#snd`) moved in from Send's pane while Home is up
(`homeSender`; `drawPage` puts it back with `parkSender` before every page, so
the name you typed and the file you chose go with it and every part of it
keeps its one id — never draw a second box), and under it the last three files
on their way or arrived (`paintHomeTx`, `txRow`), or before there are any the
people, Macs nearby first (`personRow`; Home watches for them the way Send
does). A quiet redraw while you type keeps the focus and the caret in the box.
Quick actions (`quickTray`) are what the figures over it do not offer already:
the desktop's icons, the next wallpaper, Documents when there is something
loose in it, the Dock and what starts with the Mac. Under Your folders two
more (`homeLater`): Done lately, what Kliner did this session and then its
log, each with Undo (`doneTray`, `paintHomeDone`), and This Mac in five lines
(`macTray`: the system, the memory, the battery drawn, how long it has been
up, the Trash).

Then Your folders, with
14, 30 or 90 days to look back over (`HOME_VIEW`, `.ef-seg`): what landed in
Downloads, Desktop and Documents a bar a day (`paintLanded`, from each
folder's `listing`, stacked in three greys with the totals across the top, a
scale up the right whose every line names a value the chart reaches
(`niceScale`), the busiest day named over its bar with a dashed line across at
its height that goes to whichever day you point at, a label over a bar with its
day, and what Kliner tidied away in the same days from the undo log,
`HOME_LOG`); your disk (`diskTray`, `gaugeViz`: thirty-two ticks round half a
circle, as many lit as the share used, the share in the middle, then used and
capacity side by side); and the hours your downloads arrive in (`paintHours`:
a bar an hour, each in its own grey track, the busiest two lit, four hours
named under them, and what share of Downloads came in them). A block with nothing to say says so. While Home is
read the first time, `homeSkeleton` draws the same cards in grey.

**Settings** is the menu Dan drew (`drawSettings`): down the left you at the
top — your picture, name and @username — then Profile, Public page, General
and Permissions, a line, Help and About (`SET_TABS`, `SET.tab`,
`openSettings`); on the right the part you picked, one row per thing (`srow`):
its name and a line about it on the left, the thing itself on the right.
Profile is you and only you (`profilePart`; Dan, v20: "the profile is too
chaotic"): a cover of your wallpaper with you in front of it (`profileCover`),
your name, your @username as the address it lives at with a tick once it is
yours there (`usernameField`, `.ugroup`), your email (kept on this Mac), your
picture, one row for your page (Set up, or Edit page), and Delete my
kliner.app account in words at the foot (`accountLeave`). The page has a part
of its own (`publicPart`): Show my page, then Your words — the name over your
@username, a line about you, what you do and where (`.prof-two`), the things
you made and your links, one row at a time (`growing`: the rows with something
in them and one empty one, then Add another; four empty rows of four boxes
were most of what made it look busy) — then Besides your words (Picture, This
Mac, Setup), and Publish or Save hidden with Open the page. General is how
Kliner behaves on this Mac (`generalPart`), Permissions what macOS lets it see
(`accessPart`), Help the keys, one cap a key (`keyCaps`), and What is where
(`showMap`, `tourSteps`). Help is its own page (`HELP()`, `?`) drawn in the
same layout, so the light in the sidebar stays true.

Send is a page of its own (`drawShare`, `SHARE()`), the line after Home in
the sidebar: the people — the Macs nearby, live, with a green dot, then
whoever you sent to before (`recentNames`, kept as `sent` in ~/.nimo/config
by the app) — each a row with Send (`sendTo`), and every transfer since
Kliner opened (`paintTransfers`, one row redrawn a frame at a time while it
moves, `paintTx`), with Stop, Answer and Show; a click on one shows it in the
pane. The box you send from is at the foot of the pane (`paintComposer`):
the @username, checked with kliner.app as you stop typing, the line that
says who that is once there is a name, the file (`paintFile`: chosen, or
dropped anywhere on the window), two of the people as round chips
(`paintChips`), and one round button that sends. A file on its way is the
pane's top while it goes (`jobDetail`, `jobState`); the sheet that asks you
about a file coming to you is the same card. With the pane beside the page,
you are in the pane (`inspSend`); without it, on the page (`addressCard`).
Nearby is looked for only while the page is open (`watchNearby`). A file on
its way to you still asks first, over everything (`nextIncoming`). Dropping
a file on the window is `Canvas` in Web.swift: only Finder files are taken,
held like a chosen one (`Nearby.hold`), and the page is told `drag` and
`dropped`.

How a page arrives is one system (`stagger` in app.js, the motion section of
style.css): every card and tray gets its moment in `--d`, two columns are
read across row by row, and what is inside a card — bars, rows, the meter —
follows on from its card. One curve for arriving (`--arrive`), one for
gliding (`--glide`), a small spring for answering a press (`--spring`).

v19 is the motion Dan asked for after kravio's dashboard and seven libraries
of moving parts ("all of it, here, now"); none of them is loaded, each piece
is Kliner's own. Figures roll rather than count (`rollFigure`): each digit a
strip of nought to nine slid into place behind a window one digit tall, the
left one first, plain text again once it lands. A page arriving rolls them up
from nought as their card lands (`runCounts`); a redraw that only refreshes
the figures keeps still, all but the figures that changed, which roll from
what they said (`snapFigures`, `rollChanged`, keyed by card and place in
`figureKey`) — the junk figure once it is measured, the sidebar's counts
(`tally`), the legend's totals when the span changes — and a small picture
that was not there before draws itself in. A switch has one light that slides
to the button you press (`segGlide`), ⌘K one under the row you are on
(`.fglide`) with its rows arriving one after another; a sheet and a toast
leave the way they came (`leave`: `.ksheet` becomes `.ksheet-out` at once, so
whatever asks whether a sheet is open hears no while it fades; `openSheet`
puts a new one in its place at once, `closeSheet(true)`); the first greeting
of a session arrives a letter at a time (`letters`, carrying on where it was
if Home is drawn again on the way); a bar that is filling has a light running
along it that carries on across redraws (`sheenAt`); waits shimmer. A file on
its way is the island in the middle of the bar, on every page but Send, whose
pane shows it already (`islandEl`, `drawIsland`, `islandJob`), and on Home
only while the send card's row for it is out of sight (`homeSaysIt`, painted
again as Home scrolls): a ring filling, its name and how far, then Delivered
or Received for a moment (`job.doneAt`), and a click opens Send on it, or the
question for a file coming to you. It is a hole in the drag strip and only
ever as wide as the room between the bar's two sides: off the middle when the
tabs need it, then without its words, then not at all. Every one of these
stops for reduced motion. One name per `@keyframes`: two of one name are one
keyframe, the last; v19's all start with `mo`.

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

Tags v0.46.0 to v0.61.0 were made along the way while `VERSION` stayed
0.45.0, so the release after 0.45.0 is 0.62.0, and every new one goes above
the highest tag. The repository is private, so a GitHub release is not a
download anybody else can reach: what anyone can have is what
`server/deploy.sh` puts up at `<server>/download` — the disk image
`app/build.sh` makes (`app/build/Kliner-<version>.dmg`: Kliner.app and a link
to Applications, made with `hdiutil`), saved as `Kliner-<version>.dmg`, with
the zip kept beside it for the links already out there. The checks that read the art
need Pillow (`tools/glance.py`); a runner without it fails them.

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

## AppKit first

`nimo_wall_appkit_set` is tried **first**: `NSWorkspace
setDesktopImageURL:forScreen:` for every screen, through `osascript -l
JavaScript`. It is what System Settings itself does. It asks no other app for
anything, so it needs no Automation permission, and it is the one route
`WallpaperAgent` keeps: a wallpaper set by editing the store was put back by
the agent a while later, because the agent holds its own state and writes it
over the file. The picture goes to the script in `NIMO_WALL_PIC`, so no quote
in a file name can end the script. `nimo_wall_appkit_read` asks the same way,
so the read-back right after a change is not a store the agent has not
written yet.

`test/macos.sh` keeps this route off unless `NIMO_JXA_OK=1`, so the rest of
the file still tests the Macs it does not work on.

## `\` writes it straight

The app is a window on `min`, and everything it changes it changes by running
`min`. There is one exception, in `app/Sources/Desk.swift`: `\`, the key that
takes the icons off your desktop. A key you press to see your desktop cannot
spend a fifth of a second starting bash, sourcing nineteen files and drawing a
panel nobody will read, so Kliner writes the same two settings itself, through
`CFPreferences`, in about a millisecond. `min zen` is unchanged and still owns
it from a terminal: `min zen --restore` puts the icons back whether it was the
key or the command that took them away.

Two settings, not one. Desktop & Dock › Show Items has a switch for the plain
desktop (`StandardHideDesktopIcons`) and another for Stage Manager
(`HideDesktop`), and macOS reads whichever matches the mode the Mac is in.
Both Kliner and `min` write **both**. One on and the other off is how this
ends up looking broken — every press flips the one nobody is reading, and the
icons never move — and it is what `\` not working turned out to be.

Which way round the key goes is decided on the Swift side, from
`Desk.onScreen()`, not from what the page last remembered. That read has three
answers: yes, no, and `nil` for a window list that cannot say, which must
never be read as "no icons". When the switches have not taken a moment later,
`Desk.finderWay` is Finder's older way — `CreateDesktop` and a restart —
slower and certain.

## The wallpaper store

`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, read by
`WallpaperAgent` when it starts. It is the second route, and like the first
it asks nobody for anything: every AppleScript path needs Automation
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

## It fits the window it is in

`nimo_measure_width` runs once at startup and sets five numbers: the panel,
the label column, the rule, and two bar widths. They move together, so a
narrow window loses label room rather than alignment. Never hard-code a width
in a `printf` again — 52 was a constant for thirty versions and it was wrong
on every terminal that was not full width.

Prose may wrap; tables may not. `nimo_room_for_note` decides on `NIMO_COLS` —
the **window**, not the panel — because a 52-column panel still writes a
68-column line once a note is on the end of it.

Measuring this in a test needs python, not awk: a box-drawing character is
three bytes, and awk under the wrong locale will tell you a 55-column rule is
160 wide.

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

## Kliner Cloud

nimo — `min` and its libraries — still never touches the network, and the
"nimo never reaches the network" check still stands. The app is the one part
that does, and only for @usernames: a name that is not on the same network
and public profiles at kliner.app/@name go through kliner.app
(`app/Sources/Cloud.swift`, the server in `server/`). There is no beta gate:
the app opens straight away, and the server's beta endpoints are unused.

- A name a Mac in sight answers to still goes straight across (Nearby). Only
  other names go through kliner.app, and only once this Mac has a name there.
- A file is encrypted on the sending Mac before it leaves: a fresh key per
  file, ChaChaPoly in 8 MiB pieces, the key sealed to the receiver's X25519
  key. kliner.app keeps only ciphertext, for seven days at most.
- Every request is signed with the Mac's Ed25519 key. The keys live in
  `~/Library/Application Support/Kliner` (0600), not the Keychain: the app is
  signed again on every build and the Keychain would ask each time.
- Only kliner.app's own answers count. The Worker marks every response
  `X-Kliner: 1`, and the app treats one without it as no answer at all: the
  domain does not point at the Worker yet, and whatever answers there instead
  must not be read as a name being taken or free.
- The public page at `/@name` is one 715-point column held between two rules
  that run the whole height of the page, in black and white, so the only
  colour on it is their own app icons. **Every rule on it crosses the whole
  window, not the column**: the one under the top strip, the 24-point band
  of diagonal hatch that parts one section from the next, and the one under
  a section's name. That frame is Dan's pick (sahilcodex.vercel.app) and is
  what the page is for — a quiet column with its edges drawn.
  In it: their bio across a field of dots, then their picture in a 1px frame
  with their name at 30 points, then their screen — and that screen is
  **the one the app draws on Home, to the figure**. The page's `cqw` is
  that page's `em` (a hundredth of the screen's width), so every number in
  `.mac`, `.mac-bar` and `.mac-dock` was copied straight over: the .6em
  black bezel ring, the 2.5em menu bar, the Dock's 4.2em tiles, .45em gap
  and 1.6em corner, and the app's own blue when there is no wallpaper. Do
  not let the two drift — a Dock on the profile that is not the Dock in the
  window is the thing Dan sent back twice. The icons are the apps' real
  ones, drawn square and whole (`object-fit:contain`, no radius): macOS
  already cut them, and rounding them again is what made the first draft
  look wrong. The Dock ends the way a Mac's does, with the line and the bin.

  **The pictures have to be the real ones.** Swift hands the page a 1400
  wallpaper, 128-point icons and the bin (`wallBig`, `dockApps`); for a
  while `profileGather` threw all three away — a 480-point wallpaper on a
  675-point screen at twice the pixels, 64-point icons, and in the end no
  icons at all — and the page looked exactly as made up as it was. It now
  publishes them at the size they arrive, against `PROFILE_ROOM` (760 000
  characters of JSON, under the 800 KB the server takes), icons last and
  the bin after them, because they are the part worth dropping. If the
  Dock on a live profile is a row of letters, that is this, not the page.

  **It is a page about a person, not a report about a computer.** All three
  pages Dan picked (sahilcodex, mukundkapoor, rahulgg) are built the same
  way: who they are, what they have made as dated rows that go somewhere,
  where to find them — short, and dense with links. Four drafts of this page
  opened on a spec sheet of a Mac and he sent back every one of them. So
  Work and Links come first (`role`, `place`, `work`, filled in Settings),
  and the Mac follows. Do not put the machine back on top.

  **A page with a quarter of the content reads as a template, however
  exactly the frame is copied.** Dan's reference is 6662 points tall with
  eleven sections; the first four drafts of this page were 1744 with four,
  and every round of fixing the frame changed nothing, because the frame
  was never the problem. So the page carries everything Kliner honestly
  knows about their Mac: the screen, the wallpapers they keep (`setup.walls`,
  the one in use ringed), this Mac, what it has freed and tidied, and what
  it has done here (`done`, the lines `min undo --list` printed, as it
  printed them). Nothing on it is worked out by the page. Add to this list
  before touching the layout again.

  Every fact after that is the same cell — a mark, what it is, what it says under it —
  in a row that wraps, each cell 200 points at least and free to grow, so
  the last row fills and nothing is ever left standing beside an empty box.
  The type is one scale measured off Dan's reference, written down in
  `server/SPEC.md`; four greys and no more. The CSP allows no script and no
  fetched font, so Geist rides along in the page as a `data:` URL
  (`server/src/geist.js`, a 34 KB subset: Latin, Slovak and Czech, weights
  400–600, SIL OFL).
- **One @username is one person, and a name let go is not up for grabs at
  once.** `holds` (server/schema.sql) keeps a name for somebody for a while,
  two kinds of it. `renamed`: the name a Mac gave up, kept for that Mac's key
  for seven days. `POST /v1/users/me/name`, signed as the old name, moves the
  profile and every file on its way to or from it to the new name in one
  batch, three times a day at most; changing back in that week is the same
  call, and nobody else can take the old name meanwhile, so nobody can pose as
  you to the friends who still send to it. `claimed`: a name held on
  kliner.app before there is a Mac to put Kliner on (`POST /v1/claims`, open
  to pages, three an hour and six a day from one address), kept thirty days
  for whoever has the code it showed once (XXXXX-XXXXX from 31 letters and
  digits that cannot be misread, kept only as its SHA-256). Taking or changing
  to a claimed name needs that code (`claim` in the body; a wrong one is
  `wrong_code`), a name kept for somebody else is `held`, and a key that has a
  name already is `has_name` (it changes its name instead). Asking about a
  name (`/v1/names/:name`) says `held` or `claimed` with `until`; asking for a
  renamed name, or sending to it, answers `renamed` — "@x changed their
  username. Ask them for the new one." In the app, `Cloud.rename` does the
  change (`claim` hands over to it when this Mac already has another name) and
  `renamed(from:to:)` puts the new name everywhere the old one was: the keys'
  file, `user`, the files still on their way, Nearby. `userWas` and
  `userWasUntil` in ~/.nimo/config are the name still kept for you and until
  when; Settings says so under your name, with Change back (`usernameField`),
  and the starter takes a code too (`userClaimLine`, `#ucode`).
- **kliner.app/@name is where a name lives, profile or not** (v21). Dan opened
  kliner.app/@a-free-name, found "No profile here" and nothing to do. Now a
  name with no public profile gets a page about the name in the same frame
  (`namePage`): free — "@name is free." and one button, Hold @name for 30
  days, a plain form (`POST /@name`, no script; this page alone has
  `form-action 'self'` in its CSP); somebody's, page not public — how to send
  them a file, and where the owner turns the page on; held — until when, and
  that the code goes into Kliner; changed — "Ask them for the new one", never
  the new name. The form only counts from its own page (`fromItsPage`:
  `Sec-Fetch-Site`, then `Origin`) and carries a nonce the page drew; the code
  is drawn from that nonce (`codeFrom`), so the same form sent twice — a
  double click, a reload — gets the same code again instead of a name held
  with a code nobody saw. `holdName` is the one way a name is held, for this
  page and for `POST /v1/claims` alike.
- `server/SPEC.md` is the contract both sides are tested against.
- Deploying the server is the owner's step, from his own Cloudflare login:
  `bash server/deploy.sh` opens the browser to log in the first time, and
  writes `cloud = <address>` into `~/.nimo/config` and `server/cloud.url` so
  the app finds it. `app/build.sh` writes that address into the app it
  builds (`KlinerCloud` in Info.plist: `KLINER_CLOUD`, else the `cloud =`
  line, read and never sourced, else `server/cloud.url`), so a copy opened on
  another Mac talks to the same server. Cloud.swift asks `~/.nimo/config`
  first, then the address built in, then kliner.app's own.
- `GET /download` (302) hands out the disk image deploy.sh put up (R2
  `releases/Kliner.dmg`) as `Kliner-<version>.dmg`, the version read from the
  note it puts up beside it (`releases/latest.json`), and the zip when there
  is no image yet; `GET /download/Kliner.app.zip` is still the zip.
  `GET /v1/release` says which version is up, how big and its checksum, for
  any page (CORS); the site's Download line reads it. Nothing about who
  downloads anything is kept.

## The website

`docs/index.html` is the whole site — one file, no build step, the app icon
inlined. GitHub Pages serves it from `/docs`. **It is not kliner.app's front
page**: kliner.app/ is a landing page kept outside this repository ("Make your
workspace cleaner", Join), and only `kliner.app/@*` is the Worker's. So a
change here is not live on kliner.app — anything that must be there goes in
the Worker's name pages. `docs/site.html` is the older full site, kept and
still version-checked; `docs/join.html` is the list. Download points at
`<server>/download`, the address in `server/cloud.url` (a test holds both
pages to it); under the button the version, and once `/v1/release` answers,
the disk image's name and size (`data-dl-v`, `data-dl-f`: the page's own words
stand when it does not). The page says what macOS does the first time: Privacy
& Security, Open Anyway.

Under the profile card, `#claim` holds a name for thirty days for somebody who
has no Kliner yet: as they type it asks `/v1/names/` (after the same rules the
server has, checked on the page first, and in this page's own words for a name
that is held: there is nowhere here to type a code), and Hold it for 30 days
posts `/v1/claims` and shows the code once, with Copy the code. The links
along the top have Your name for it.

Everything the page says Kliner does, Kliner does today, in the words the
app and `min` use: the terminal on it is `min`'s own output, the profile
card has the three ticks Settings has (Picture, This Mac, Setup), and the
wallpapers are the Mac's and the ones in Pictures/Kliner Wallpapers — Kliner
ships none of its own. The pictures are drawn in the page with example
figures, never somebody's real Mac. A feature that changes changes here too.

## Git

The remote is `git@github.com:danielkopa/nimo.git` over SSH. Commits are small
and each one says what changed in plain words.
