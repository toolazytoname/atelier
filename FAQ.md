# Frequently asked questions

> Can't find your question? Open a
> [GitHub Discussion](https://github.com/toolazytoname/atelier/discussions)
> (not an issue — Discussions is for questions, Issues is for bugs).

## Setup

### Do I need OrbStack? Can I use Lima, Docker Desktop, or Multipass?

`bin/devbox` is hard-wired to OrbStack (`orbctl` / `orb` commands). The
VM called `atelier` is a plain Ubuntu 24.04 OrbStack VM — any tool that
can drive OrbStack can drive atelier. In practice this means OrbStack
on macOS.

Docker Desktop and Multipass don't fit because their CLI surface is
different (no `orbctl run`, no native macOS auto-mount). Lima could
work in principle but you'd need to rewrite `bin/devbox` — the
project doesn't ship that adapter. If you want to contribute one,
open a Discussion first so we can agree on the interface. See
[`docs/comparison.md`](docs/comparison.md) for the full comparison.

### Can I run this on Linux or Windows?

No. OrbStack is macOS-only (it uses Apple's Virtualization framework,
which only exists on macOS). On Linux, your dev environment already
*is* a Linux machine, so the architecture reduces to "don't `sudo`"
and the toolchain becomes overkill. On Windows, use WSL2 with a
sibling project — atelier has no plans to support it.

### How long does `make setup` take?

About **5 minutes** the first time on a fast link, mostly downloading
Ubuntu packages, Node 24, Go, Rust, and open-design. On the CN mirror
defaults (TUNA, npmmirror, goproxy.cn, rsproxy.cn, ghfast.top) this
drops to 2–3 minutes inside mainland China. Re-runs are idempotent
and finish in seconds.

### My provision is hanging on a download. What's wrong?

You probably hit the international mirror's rate limiter from a CN
egress. Run `bin/devbox doctor` and look for `setup/provision.sh`
sourcing lines. Switch with `CN_MIRROR=0 ./setup/provision.sh` for
international, or `CN_MIRROR=1 ./setup/provision.sh` to force CN
mirrors. See the README § "Mirrors".

## Architecture

### Should I run Claude Code on the host or in the VM?

**In the VM, via `bin/devbox claude`.** That's the whole point of
atelier — the host Mac stays inert. Running CC on the host works
technically (the project CLAUDE.md is read either way), but it
breaks the "host stays inert" promise because CC will write
`~/.claude/{cache,file-history,session-data}` on the host and any
MCP servers you load will run on the host.

**Trade-off:** VM-CC has roughly 30–80 ms of TUI latency because
output is piped over `orbctl`. For most coding work this is
invisible. For interactive browser-feedback loops (watching
screenshots stream in), the host-CC experience is snappier — at
the cost of breaking the isolation model.

**Recommendation:**

- Default: `bin/devbox claude`
- yolo with `--dangerously-skip-permissions`: `bin/devbox claude`,
  no exceptions
- Quick read-only question while you're not in a session: host CC
  is fine, just don't run a real task from it

### What's the relationship between atelier and open-design?

**open-design is a separate project.** Atelier happens to bundle an
MCP bridge to it (`.mcp.json`), and `bin/devbox claude` / `bin/devbox gui`
will start the open-design daemon if it isn't running. But you can
use atelier without open-design — just delete `.mcp.json` (or leave
it; missing commands degrade gracefully).

The README's "four-pillar" table mentions open-design, lazyweb,
everything-claude-code:frontend-design, etc. These are **recommended
companion tools**, not parts of atelier. If you don't have them,
atelier still works — you just lose the design-aware features.

### Where is my project code?

In **two places at once, kept in sync by OrbStack:**

| Side | Path |
|------|------|
| Host (Mac) | `/Users/lazy/Code/crack/<project>/` |
| VM (Linux) | `/mnt/mac/Users/lazy/Code/crack/<project>/` |

Edit either side — they share the same bytes. **Project files survive
`bin/devbox reset`**. Anything written to VM-only paths (`~/.cargo`,
`/usr/local/bin`, `~/.bashrc`) does not.

### Can two atelier VMs run at the same time?

Yes — pass `VM=m2` (or any name) to the Makefile / `bin/devbox`:

```bash
make setup VM=experiment
make shell  VM=experiment
```

They don't share state and don't conflict. Default name is `atelier`.

## Running things

### I ran `pnpm test` and got `command not found`

You ran it on the host. The host has no pnpm. Use
`bin/devbox run pnpm test`. See the SKILL "atelier" (if installed
in your agent) or CLAUDE.md for the full command matrix.

### Port 8000 is taken on the host. Can I still use it inside the VM?

Yes. The VM has its own network namespace; host port conflicts don't
propagate. Pick any port you like inside the VM.

### How do I get my Anthropic / GitHub token into the VM?

`./setup/host-passthrough.sh` reads `ANTHROPIC_*` and `GITHUB_TOKEN`
from your host shell and writes them to `/etc/environment.d/host-proxy.conf`
inside the VM. Re-run it any time you rotate a token. The
`bin/devbox claude` launcher re-reads these on every invocation.

### The browser tab shows "connection refused" on <http://localhost:7456>

`bin/devbox gui` is not running, or it died. Open a new terminal and
run `bin/devbox gui`. Ctrl-C in that terminal tears down both the
daemon and the SSH tunnel.

## Reset & recovery

### What's the difference between `make reset` and `bin/devbox reset`?

None. The Makefile target is a thin wrapper for the script. Use
whichever you remember.

### Will I lose my code if I reset?

**No.** `bin/devbox reset` only destroys the VM. Your project files
on the host are untouched. The VM is rebuilt from `setup/provision.sh`
in ~5 minutes. Things you will lose:

- Packages installed to the VM (rebuilt from `provision.sh`)
- Files in `~/.bashrc` / `~/.zshrc` inside the VM
- Files in `~/.cargo`, `~/go`, `node_modules` inside the VM
- Anything in `~/.local/share/open-design/` inside the VM

**Mitigation:** anything persistent must live in the project tree
or in `setup/provision.sh`. See CONTRIBUTING.md.

### Can I take a snapshot of the VM before doing something risky?

OrbStack snapshots are a Pro feature and not exposed by `bin/devbox`.
For a poor man's snapshot, copy the VM image out of OrbStack's
storage directory before a risky op. Or, more pragmatically, just
`bin/devbox reset` after — it's fast.

## Contributing

### Where do I report a security issue?

Privately, via [GitHub Security Advisories](https://github.com/toolazytoname/atelier/security/advisories/new).
Public issues tip off attackers before a fix lands. See
[`SECURITY.md`](SECURITY.md) for the full policy.

### I have a question, not a bug — where do I ask?

[GitHub Discussions](https://github.com/toolazytoname/atelier/discussions).
Issues are for actionable bugs / feature requests only.

### Why is the default mirror set to mainland China?

Because the project came out of a Chinese-language workflow and the
default is whichever mode the maintainer dogfoods. If you're outside
CN, run with `CN_MIRROR=0 ./setup/provision.sh` once, then continue
normally. See README § "Mirrors" for the full list of mirrors.
