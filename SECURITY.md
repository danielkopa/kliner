# Security

nimo runs with your user's permissions and moves your files. Please report
anything that could be turned against someone privately, rather than in a
public issue.

**daniel@rlx.sk** — please put "nimo" in the subject.

Include what you typed, what happened, and what an attacker would get out of
it. A reply usually comes within a few days.

## What nimo does and does not do

- It never asks for sudo, and it never runs anything with elevated rights.
- It refuses any path outside `$HOME`, including `$HOME` itself, `/`,
  `/System` and `/Applications`. That guard lives in `nimo_is_protected` in
  `lib/core.sh`.
- It never touches the network. Wallpapers come from what macOS already ships.
- `~/.nimo/config` is **read, not sourced** — nothing in it can run as code.
- Everything it changes it writes down first, in `~/.nimo/`, so it can be
  undone.

If you find a way around any of those five, that is the kind of thing this
page is for.
