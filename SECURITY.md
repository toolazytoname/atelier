# Security Policy

## Supported versions

`atelier` is currently in **1.x** development. The latest tagged release
receives security fixes; older versions do not.

| Version | Supported          |
|---------|--------------------|
| latest  | ✅                 |
| < latest | ❌                 |

## Reporting a vulnerability

**Do not file a public issue for security problems.** Public issues make it
trivial for an attacker to exploit the report before a fix is shipped.

Instead, please use **GitHub's private security advisory** flow:

1. Go to <https://github.com/toolazytoname/atelier/security/advisories/new>
2. Fill in the title, affected versions, and a clear description
3. Include:
   - macOS version (`sw_vers`)
   - OrbStack version (`orb --version`)
   - atelier version (`git describe --tags` inside the repo)
   - Output of `bin/devbox doctor`
   - Steps to reproduce
   - Impact assessment (what an attacker could do)
4. Wait for a maintainer acknowledgement (target: 72 hours)
5. Coordinate disclosure timeline (default: 90 days)

For sensitive reports where GitHub advisories are not viable, open a
**draft** GitHub Discussion tagged `security` and a maintainer will move
it to the private advisory channel.

## What counts as a security issue

- **VM escape**: code running inside `atelier` breaks out and affects
  the host Mac
- **Path traversal / symlink escape**: anything under `provision.sh`,
  `bin/devbox`, or `host-passthrough.sh` that lets the VM write outside
  `/mnt/mac`
- **Deny list bypass**: any way to run `sudo`, `rm -rf /`, `curl | bash`,
  or write to `~/.ssh/**`, `~/.aws/**`, `~/.gnupg/**`, `~/.kube/**`,
  `~/.docker/**` while `--dangerously-skip-permissions` is on
- **Token leak**: any condition under which `ANTHROPIC_*` or
  `GITHUB_TOKEN` ends up in a log, error message, or screenshot
- **Privilege escalation** inside the VM (provision script running
  anything as root that isn't strictly required)
- **Supply chain**: compromised dependency in `setup/provision.sh`
  (apt, pip, npm, Go modules, crates, downloaded binaries)

## What is *not* a security issue

- Things that already require explicit user confirmation
  (`bin/devbox reset` asks for `yes`)
- Issues that only affect an already-pwned host (the wall stops at
  the host boundary by design)
- The fact that running Claude Code on the host breaks the
  "host stays inert" promise — this is documented behaviour, not a
  vulnerability. See README § "Should I run Claude Code on the host?"
- Performance / usability issues (file a regular bug)

## Threat model in one paragraph

The trusted boundary is the macOS host filesystem. Everything inside
the OrbStack VM is considered untrusted code (including anything
Claude Code runs, anything `provision.sh` installs, anything an MCP
server does). The wall is built from three layers: (1) the VM
hypervisor (OrbStack on Apple Virtualization), (2) the project-level
`.claude/settings.json` allow/deny list, (3) the `bin/devbox` wrapper
that funnels every host-side invocation through `orbctl`. The
deny list is intentionally short — it covers the "unrecoverable
mistake" class of commands, not the "we don't want this right now"
class. For the full model, see `docs/security-model.md`.

## Acknowledgements

Reporters who follow responsible disclosure will be credited in
the release notes (unless they ask not to be). Thank you for keeping
the community safe.
