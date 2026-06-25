# Why OrbStack? (vs Docker Desktop, Lima, Vagrant, Multipass, Apple's container)

> If you already use one of these and it works, you don't need
> atelier. If you're starting fresh on macOS Apple Silicon and
> want a dev sandbox, this page is for you.

## TL;DR

| Tool | Apple Silicon perf | Reset in seconds | Shared mounts | SSH access | atelier-friendly? |
|------|--------------------|------------------|---------------|------------|-------------------|
| **OrbStack (atelier's choice)** | excellent | yes | yes (auto) | yes | ✅ ships with `bin/devbox` |
| [Apple's `container`](https://github.com/apple/container) | excellent | yes (per container) | explicit per-container | no | no — wrong mental model (see below) |
| Docker Desktop | good | yes (container) | sometimes | clunky | partial — needs rewrite |
| Lima | good | yes | yes (manual) | yes | needs ~1 day of glue |
| colima | good | yes | yes (manual) | yes | same as Lima |
| Vagrant | poor (VirtualBox) | yes | yes (manual) | yes | possible, not recommended |
| Multipass | good | yes | yes (manual) | yes | possible, not recommended |
| Native Linux dev box | n/a | n/a | n/a | n/a | no — defeats the point |
| WSL2 (Windows) | n/a | n/a | n/a | n/a | not supported on macOS |

## What atelier actually needs from the VM

Before we compare, here's the spec atelier depends on:

1. **A real Linux VM** (not a container pretending to be one) —
   we need apt, systemd, real `/dev`, full POSIX filesystem
2. **Apple Silicon performance** — 4 vCPU / 8 GB should boot in
   <10 s and not thermal-throttle
3. **Auto-shared host filesystem** — `/Users/you/...` on host
   maps to `/mnt/mac/...` in VM, no manual `sshfs` setup
4. **One CLI to drive it** — `orbctl run` / `orbctl shell` /
   `orbctl create` / `orbctl delete`. We wrap this in
   `bin/devbox`
5. **Idempotent provisioning** — we re-run `setup/provision.sh`
   on every `bin/devbox reset` and expect it to converge

OrbStack is the only tool on macOS that gives us all five.

## Tool-by-tool

### OrbStack

What it is: a macOS-native hypervisor using Apple's Virtualization
framework + a Docker shim + Linux VM management. Closed source,
freemium (Pro adds snapshots, multiple VMs at once, custom
resources — none of which atelier needs).

**Strengths:**

- 4-vCPU Ubuntu VM boots in ~4 s, uses ~250 MB RAM idle
- `/Users/you` is auto-shared as `/mnt/mac` — no `sshfs`, no
  `vagrant rsync`
- `orbctl run` / `orbctl shell` is just `ssh` under the hood —
  no daemon, no Docker socket requirement
- Resize disk / CPU / RAM from a UI without re-creating the VM
- Pro: snapshots (we don't ship a wrapper; users who want them
  can use OrbStack's UI directly)

**Weaknesses:**

- macOS-only (uses Apple's Virtualization framework, which is
  macOS-only)
- Closed source — if OrbStack disappears, atelier breaks
- Pro features are paid (we don't use them; free tier is enough)

**Verdict:** This is what atelier is built for. We don't paper
over any rough edges.

### Docker Desktop

What it is: Docker's official macOS client, built on
[Virtualization.framework] (since 4.13) or Apple Hypervisor
framework (since 4.16). Gives you a Linux VM running Docker
daemon.

**Strengths:**

- Most developers already have it
- Excellent Docker ergonomics (Compose, buildx, multi-arch)

**Weaknesses:**

- Optimized for containers, not bare Linux VMs — getting a full
  systemd / apt / non-containerized process tree is awkward
- No `orbctl`-equivalent CLI for "run a non-Docker process in the
  VM" — `docker exec` is the only way
- Heavy when idle (~1.5 GB RAM for the VM, before you run any
  container)
- The `~/.docker/desktop-settings.json` lives on the host —
  violates "host stays inert" promise

**Verdict:** Reasonable if your project is Docker-first. Not
recommended for atelier's "everything is a normal Linux
process" model. The rewrite from `orbctl run` to `docker exec`
is non-trivial — `bin/devbox` doesn't drop in.

### Lima

What it is: a CNCF sandbox project for running Linux VMs on
macOS / Linux. Supports multiple VM backends (QEMU, vz for
Apple Silicon, Hyper-V on Windows).

**Strengths:**

- Open source, CNCF-governed — won't disappear
- Multi-platform (macOS, Linux, Windows via WSL2)
- Standard `lima.yaml` config — easy to share reproducibly

**Weaknesses:**

- The Apple Silicon `vz` driver is less polished than OrbStack
  (slower boot, higher idle RAM, occasional mount staleness)
- File sharing requires explicit `sshfs` or `9p` config — not
  automatic
- No native UI for resource tuning
- Adding a new subcommand to `bin/devbox` for Lima means
  rewriting each function to use `limactl shell atelier` instead
  of `orbctl run -m atelier`

**Verdict:** A principled second choice. Atelier could be
adapted — about a day of work to add a `BACKEND=lima` switch
in `bin/devbox`. We haven't because Lima's ergonomics on Apple
Silicon are a tier below OrbStack today.

### colima

What it is: a Lima wrapper with friendlier defaults and a single
`colima start` command.

**Strengths:**

- Simpler than raw Lima for the common case
- Same underlying VM

**Weaknesses:**

- All of Lima's, plus its own opinions baked in (harder to
  customize)
- No SSH UI; `colima ssh` instead of native SSH

**Verdict:** Same as Lima, slightly worse on customisation.

### Vagrant

What it is: HashiCorp's "write a Ruby file describing your dev
environment, run it on VirtualBox / Parallels / VMware / libvirt
/ Hyper-V".

**Strengths:**

- Cross-platform, well-known
- Vagrantfile is a single source of truth
- Wide provider support

**Weaknesses:**

- The VirtualBox provider is slow on Apple Silicon (no native
  Apple Virtualization)
- No auto-shared filesystem — requires `vagrant rsync` or NFS
  plugin
- The CLI surface is huge (`vagrant up`, `vagrant ssh`,
  `vagrant provision`, `vagrant destroy`, `vagrant reload`,
  `vagrant global-status`, ...) compared to `orbctl run/shell/...`
- Ruby / Chef / Puppet / Ansible as the provisioning language
  adds a layer we don't need
- No `bin/devbox`-style thin wrapper exists; you'd have to
  write one

**Verdict:** Overkill for a 5-minute sandbox. Was the right tool
in 2014.

### Multipass

What it is: Canonical's "Ubuntu VMs on macOS / Windows / Linux".
Built on Apple's Hypervisor framework on macOS.

**Strengths:**

- First-class Ubuntu support
- One CLI: `multipass launch`, `multipass shell`, `multipass exec`
- `multipass mount` for shared files

**Weaknesses:**

- Less polished on Apple Silicon than OrbStack
- `multipass mount` is `sshfs` under the hood — slower than
  OrbStack's auto-share
- Smaller community than OrbStack
- No integration with Docker (so you can't get
  "Docker daemon on a fast VM" with one tool)

**Verdict:** A reasonable second choice if you're already in
the Canonical ecosystem. Same effort as Lima to wrap.

### Apple's `container` (github.com/apple/container)

What it is: Apple's first-party tool (Swift, Apache 2.0) to create
and run Linux **containers** as **lightweight VMs** — one VM per
container, not one shared VM hosting all containers. Uses the same
Apple `Virtualization.framework` underneath that OrbStack uses, so
it's a peer of OrbStack at the syscall level, not a replacement for
it. OCI-compatible (consumes and produces standard container
images). As of 2026-06, pre-1.0; README says "stability only
guaranteed within patch versions."

**Requirements:** macOS 26 for full features, macOS 15 with reduced
networking, Apple Silicon only. No Intel.

**Strengths:**

- First-party from Apple — uses new macOS 26 Virtualization
  enhancements the day they ship
- One VM per container is a stronger isolation story than
  shared-VM (a container escape still doesn't reach the host)
- Memory overhead per container is much lower than a full VM
  (per Apple: 2 GB for a busy app vs ~8 GB for a full VM)
- Open source, Apache 2.0
- OCI images built with `container` run on Docker / Podman / k8s
  and vice versa

**Weaknesses:**

- **Pre-1.0** — no API stability guarantee, can break between
  minor versions
- Apple Silicon only — drops the Intel-Mac cohort entirely
- macOS 26 only for the full networking story; macOS 15 has
  reduced networking (no container-to-container, no multiple
  networks, occasional IP-subnet bugs)
- Memory ballooning is partial: free memory inside a container
  VM doesn't get returned to the host — long-running memory-heavy
  workloads may need periodic restart
- No concept of "one persistent Linux system" — every container
  is its own ephemeral VM. To install Node + Python + Go + Rust +
  starship you'd build a custom OCI image with all of that
  baked in (move the work from `setup/provision.sh` running in a
  live VM to a CI build step)
- No `container shell` equivalent of `orbctl shell` — the
  "drop into the VM and hack" loop doesn't exist
- Host filesystem sharing is explicit per-container, not
  auto-mounted

**Verdict:** Wrong tool for atelier. The architectural mismatch:

- atelier wants **one persistent Linux system** to install tools
  into. apple/container wants **N ephemeral per-container VMs**.
- atelier's `bin/devbox reset` = nuke the VM and re-run
  `setup/provision.sh` (~5 min, idempotent, all tools reinstalled).
  In apple/container, "reset" means delete the container and pull
  the image again — but if your image is the standard Ubuntu one
  with no tools, you've lost Node/Python/Go/etc. unless they were
  baked into the image at build time.
- The "auto-share `/Users/you/...` → `/mnt/mac/...`" UX is
  a core atelier feature. apple/container requires explicit
  per-container mount configuration.

**When would apple/container be the right answer?** If atelier
were a *containerized microservices workbench* — "spin up 12
ephemeral OCI containers for a k8s demo" — the per-container-VM
model would be a perfect fit. For "I want a Linux dev box to live
in", OrbStack is closer to the right model.

**What about supporting both?** `bin/devbox` is small (~250 lines,
8 subcommands mapping to 8 small functions). Adding
`BACKEND=apple-container` is plausible — but only once Apple
container hits 1.0 and stabilises its CLI / image-build workflow.
Until then, building a CI image that bakes in our entire
`setup/provision.sh` is more friction than atelier wants to take
on.

## What if I'm not on macOS?

Atelier doesn't support Linux or Windows hosts. The architecture
("host stays inert, all tools in the VM") only makes sense when
the host is "something else" (a Mac). On a Linux host, your dev
machine *is* the sandbox — you can get most of the safety with
just a tight `~/.bashrc` and a deny-list in your shell init. On
Windows, use WSL2 and a similar wrapper; we have no plans to
ship one.

## Summary

If you're on a recent Mac (Apple Silicon, macOS 13+) and you're
not already committed to one of the alternatives above, **install
OrbStack and use atelier as-is**. The wrapper doesn't paper over
any rough edges because there aren't any.

If you're on an Intel Mac, OrbStack still works but Docker
Desktop is roughly as fast. Pick whichever you prefer; the
migration to atelier is the same effort either way.

If you're on Linux: the architecture reduces to "don't `sudo`"
and a tight deny list. We don't have a tool for that — your
existing shell hygiene is enough.

If you're on Windows: WSL2 + a sibling project; atelier has no
plans to support it.
