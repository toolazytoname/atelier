# Contributing

Thanks for caring about this project. The whole point of `atelier` is to make
working with Claude Code less painful — so we keep the contributing workflow
itself as low-friction as the tool aims to be.

## Filing issues

Before opening an issue, please:

1. Run `bin/devbox doctor` and paste the output.
2. Include the macOS version (`sw_vers`), OrbStack version (`orb --version` if
   installed), and whether you're behind `CN_MIRROR=1` (the default) or `0`.
3. For network-related bugs, run `./bin/devbox run curl -v <url>` and paste
   the output. The most common failures are Cloudflare rate-limits from CN
   egress — the doctor output makes those easy to spot.

If your issue is "the VM is slow to install X", check
[docs/design.md § Mirror selection](docs/design.md) first. We have a fast path
for most things.

## Setting up for development

The project's own dev environment is the same one it ships: the OrbStack VM.
This is intentional — it lets you dogfood the workflow while you improve it.

```bash
git clone <repo-url>
cd atelier
./setup/install-orbstack.sh       # if you don't have OrbStack
make setup                         # = provision + passthrough
make doctor                        # confirm green
```

You can iterate on any file under `setup/`, `bin/`, or `docs/`, then
`make reset` to throw the VM away and re-test from scratch.

## Code style

- **Bash**: `set -euo pipefail`, no `eval`, prefer `printf` over `echo` for
  non-trivial output. Tests are the script itself running end-to-end inside
  the VM — keep `provision.sh` idempotent.
- **Markdown**: keep EN and ZH files in sync. Add the same section to both
  `README.md` and `README.zh-CN.md` (and to `CLAUDE.md` / `CLAUDE.zh-CN.md`
  if it's about Claude Code behavior).
- **English first**: write the English version, then mirror. The Chinese
  audience is the primary one (this project came out of a Chinese-language
  workflow), but English is the lingua franca for the rest of the world.

## Mirror selection

`provision.sh` has a single env var, `CN_MIRROR`, that switches between
mainland-China mirrors and international sources. Default is `1` (CN). If
you change a default URL, update both branches — and test the international
branch with `CN_MIRROR=0 ./setup/provision.sh` before sending a PR. CI
covers both branches (`.github/workflows/test-mirrors.yml`).

## Project layout conventions

```
bin/         host-side wrappers (run on the Mac)
setup/       one-shot VM bootstrap + passthrough + uninstall scripts
docs/        design rationale, longer-form notes (EN + .zh-CN.md mirror)
assets/      logo.svg / banner.svg / social-card.svg
examples/    minimal runnable demos (currently: harness-demo)
.claude/     project-level settings.json (allow + deny list)
.mcp.json    open-design MCP bridge config (consumed by CC inside the VM)
.github/     workflows/, ISSUE_TEMPLATE/, PULL_REQUEST_TEMPLATE.md
TASKS.md     persistent task checklist (survives /clear)
README.md    English, top-level
CLAUDE.md    English, instructions for Claude Code in this project
README.zh-CN.md / CLAUDE.zh-CN.md   Chinese mirrors
```

Anything run **inside** the VM goes in `setup/` (it has to land on the
host filesystem first). Anything run **on the host** goes in `bin/`. Never
mix the two.

When adding a new feature that ships in both languages, add a file under
`docs/` (or update an existing one) **and** its `*.zh-CN.md` mirror in
the same PR. The README's file-layout block must list both.

The `TASKS.md` file is the persistent task tracker — it survives
`/clear` and lives in git. When you pick up work after a session break,
read it first. The in-session TaskCreate / TaskList tools die on `/clear`;
`TASKS.md` doesn't.

## Asking questions

Open a GitHub Discussion rather than an issue for design questions. The
maintainers are also active in the issue tracker, so don't worry about
"is this too small to file" — small + concrete is best.

---

## 贡献指南

感谢你关注这个项目。`atelier` 的整个目标就是让用 Claude Code 干活不那么痛苦——
所以贡献流程本身也跟工具的定位一样轻量。

## 提 issue 之前

1. 跑 `bin/devbox doctor` 并把输出贴上来。
2. 注明 macOS 版本（`sw_vers`）、OrbStack 版本（如果装了，跑 `orb --version`），
   以及你走的是 `CN_MIRROR=1`（默认）还是 `0`。
3. 跟网络相关的问题，跑 `./bin/devbox run curl -v <url>` 并贴输出。最常见的失败
   就是国内出口被 Cloudflare 限速——doctor 输出能直接看出来。

如果问题是"VM 装 X 慢"，先看 [docs/design.md § 镜像选择](docs/design.md)。
大部分东西我们都有快速路径。

## 准备开发环境

项目自己的开发环境就是它交付的那个 OrbStack VM。这是故意的——让你在改进工具的时候
顺便用一遍这个工作流。

```bash
git clone <repo-url>
cd atelier
./setup/install-orbstack.sh       # 如果还没装 OrbStack
make setup                         # = provision + passthrough
make doctor                        # 确认全绿
```

你可以改 `setup/`、`bin/`、`docs/` 下任何文件，然后 `make reset` 推倒 VM 重测。

## 代码风格

- **Bash**：`set -euo pipefail`、不用 `eval`、复杂输出优先 `printf` 不用 `echo`。
  测试就是脚本本身在 VM 里端到端跑——保持 `provision.sh` 幂等。
- **Markdown**：EN 和 ZH 保持同步。给 `README.md` 加段落的同一时间也加到
  `README.zh-CN.md`（如果是讲 Claude Code 行为的，再加到 `CLAUDE.md` /
  `CLAUDE.zh-CN.md`）。
- **英文优先**：先写英文版，再镜像成中文。中文受众是主要的（这个项目是从中文工作流
  里长出来的），但英文是世界通用语。

## 镜像选择

`provision.sh` 只有一个环境变量 `CN_MIRROR`，在国内/国际镜像间切换。默认是 `1`（国内）。
如果你改了默认 URL，两个分支都要改——并且发 PR 之前用 `CN_MIRROR=0 ./setup/provision.sh`
测过国际分支。CI 已经覆盖两个分支（见 `.github/workflows/test-mirrors.yml`）。

## 目录约定

```
bin/         宿主端包装器（在 Mac 上跑）
setup/       一次性 VM 引导 + env 透传 + 卸载脚本
docs/        设计理由、长篇说明（EN + .zh-CN.md 镜像）
assets/      logo.svg / banner.svg / social-card.svg
examples/    最小可运行 demo（目前：harness-demo）
.claude/     项目级 settings.json（白名单 + deny 名单）
.mcp.json    open-design MCP 桥（VM 里的 CC 消费）
.github/     workflows/、ISSUE_TEMPLATE/、PULL_REQUEST_TEMPLATE.md
TASKS.md     持久化任务清单（跨 /clear 还在）
README.md    英文，总览
CLAUDE.md    英文，给 Claude Code 的指令
README.zh-CN.md / CLAUDE.zh-CN.md   中文镜像
```

**在 VM 里跑的**东西放 `setup/`（得先落到宿主文件系统）。**在宿主跑的**东西放 `bin/`。
不要混。

加新功能（双语上线）时，`docs/` 里加文件**同时**加 `*.zh-CN.md` 镜像，**同一个 PR**。
README 的 file-layout 块要把两者都列上。

`TASKS.md` 是持久化任务清单——跨 `/clear` 还在、跟 git 走。session 中断后接着干，
先读它。session 内的 TaskCreate / TaskList 工具 `/clear` 一按就清，`TASKS.md` 不会。

## 问问题

设计类问题开 GitHub Discussion 而不是 issue。维护者在 issue 区也活跃，所以别担心
"这个问题太小不好发"——小 + 具体最好。
