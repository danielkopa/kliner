**What this changes**

**Why**

**Checks**

- [ ] `bash test/run.sh -q` passes
- [ ] `bash test/macos.sh -q` passes
- [ ] `shellcheck -s bash -S warning -e SC2034 min lib/*.sh test/*.sh` is clean
- [ ] bash 3.2 safe — no `mapfile`, no associative arrays, no `${var,,}`
- [ ] a fix comes with a test that fails without it
- [ ] anything that changes something still asks first, and can still be undone
