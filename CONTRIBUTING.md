# Contributing

nimo moves files around on other people's computers and changes their
preferences. That is a lot of trust for a shell script, and it is the reason
for most of the rules below.

## Before you change anything

Read `CLAUDE.md`. It has the seven invariants the project does not break, the
house style, and a list of traps that have already cost time — locale-dependent
sorting, `grep -q` cutting off the command feeding it, `$(printf '\n')`
collapsing to nothing. Every one of them is now a test.

## The bargain

- **Nothing happens without a yes.** Anything that changes something shows what
  it is about to do and waits. `--dry-run` must change nothing at all.
- **Everything is undoable**, except emptying the Trash, which says so.
- **Only inside `$HOME`.** Never route around `nimo_is_protected`.
- **No sudo. No network.**

## Working on it

```bash
bash test/run.sh -q     # everywhere
bash test/macos.sh -q   # the macOS-only parts, against a faked macOS
shellcheck -s bash -S warning -e SC2034 min lib/*.sh test/*.sh
```

Write for **bash 3.2** — the one macOS ships. No `mapfile`, no associative
arrays, no `${var,,}`. CI runs both suites under `/bin/bash` on macOS, so a
bash-4-ism fails there and nowhere else.

A fix and a test that fails without it go in the same commit. If you cannot
write the test, say so in the pull request and we will work it out.

## Commits

Small, and in plain words: what changed and why, not which function moved.
`fix: newest meant newest only in the C locale` is a good one.

## Reporting something

Open an issue with what you typed, what happened, and what you expected.
`min doctor` output helps. If nimo moved something it should not have,
`min undo` first and tell us second.
