# 为什么选 OrbStack？（vs Docker Desktop、Lima、Vagrant、Multipass、Apple container）

> 如果你已经在用其中某一个而且它能用，就不需要 atelier。
> 如果你刚上 macOS Apple Silicon，想要一个开发沙箱，这一页就是给你的。

## TL;DR

| 工具 | Apple Silicon 性能 | 几秒内 reset | 自动共享目录 | SSH 访问 | 适合 atelier 吗？ |
|------|--------------------|---------------|--------------|----------|-------------------|
| **OrbStack（atelier 的选择）** | 极好 | 可以 | 可以（自动） | 可以 | ✅ 自带 `bin/devbox` |
| [Apple `container`](https://github.com/apple/container) | 极好 | 可以（按 container） | 显式按 container | 不可以 | ❌ 心智模型对不上（见下） |
| Docker Desktop | 好 | 可以（容器） | 有时可以 | 难用 | 部分可以 —— 需要重写 |
| Lima | 好 | 可以 | 可以（手动） | 可以 | 需要 ~1 天胶水代码 |
| colima | 好 | 可以 | 可以（手动） | 可以 | 同 Lima |
| Vagrant | 差（VirtualBox） | 可以 | 可以（手动） | 可以 | 能用，但不推荐 |
| Multipass | 好 | 可以 | 可以（手动） | 可以 | 能用，但不推荐 |
| 原生 Linux 开发机 | n/a | n/a | n/a | n/a | 不行 —— 违背初衷 |
| WSL2（Windows） | n/a | n/a | n/a | n/a | macOS 不支持 |

## atelier 对 VM 的硬需求

比之前先列出 atelier 依赖的 spec：

1. **真正的 Linux VM**（不是假装成 VM 的容器）—— 我们需要 apt、systemd、
   真正的 `/dev`、完整的 POSIX 文件系统
2. **Apple Silicon 性能** —— 4 vCPU / 8 GB 启动 <10s 且不降频
3. **自动共享宿主文件系统** —— 宿主上的 `/Users/lazy/...` 自动映射到 VM 的
   `/mnt/mac/...`，不用手动 `sshfs`
4. **一个 CLI 驱动它** —— `orbctl run` / `orbctl shell` / `orbctl create` /
   `orbctl delete`。我们包成 `bin/devbox`
5. **对 VM 的 SSH 访问** —— 给 GUI 隧道用
   （`ssh -L 7456:127.0.0.1:7456 ...`）
6. **幂等的 provisioning** —— 每次 `bin/devbox reset` 都重跑 `setup/provision.sh`，
   期望它收敛

在 macOS 上 OrbStack 是唯一把这六样都给齐的工具。

## 一家一家比

### OrbStack

是什么：用 Apple Virtualization framework 的 macOS 原生 hypervisor，外加 Docker shim
和 Linux VM 管理。闭源，免费增值（Pro 加快照、多 VM 同时跑、自定义资源——
atelier 一样都用不上）。

**优点：**

- 4-vCPU Ubuntu VM ~4s 启动，闲置 ~250 MB RAM
- `/Users/lazy` 自动共享为 `/mnt/mac` —— 不用 `sshfs`、不用 `vagrant rsync`
- `orbctl run` / `orbctl shell` 底层就是 `ssh` —— 没有 daemon、没有 Docker socket 依赖
- 在 UI 里就能改磁盘 / CPU / RAM，不用重建 VM
- Pro 版：快照（我们没包 wrapper；想用的用户直接用 OrbStack UI）

**缺点：**

- 仅 macOS（用 Apple Virtualization framework，macOS only）
- 闭源 —— OrbStack 如果没了，atelier 就废
- Pro 功能付费（我们不用；免费版就够了）

**结论：** atelier 就是为它造的。我们不糊弄任何粗糙的边角。

### Docker Desktop

是什么：Docker 官方的 macOS 客户端，基于 [Virtualization.framework]（4.13 起）
或 Apple Hypervisor framework（4.16 起）。给你一个跑着 Docker daemon 的 Linux VM。

**优点：**

- 大部分开发者已经装了
- Docker 体验出色（Compose、buildx、多架构）

**缺点：**

- 为容器优化，不是裸 Linux VM —— 想拿完整的 systemd / apt / 非容器化的进程树很别扭
- 没有 `orbctl` 等价的 CLI 用来"在 VM 里跑非 Docker 进程" —— 只有 `docker exec` 一条路
- 闲置时重（~1.5 GB RAM 的 VM 占用，还没跑任何容器）
- `~/.docker/desktop-settings.json` 放在宿主上 —— 违背"宿主保持惰性"的承诺

**结论：** 如果你的项目是 Docker-first，那它合理。不推荐给 atelier 这种
"一切都是普通 Linux 进程"的模型。从 `orbctl run` 改写成 `docker exec` 不小，
`bin/devbox` 不是直接换皮。

### Lima

是什么：CNCF sandbox 项目，在 macOS / Linux 上跑 Linux VM。支持多种 VM 后端
（QEMU、Apple Silicon 的 vz、Windows 的 Hyper-V）。

**优点：**

- 开源，CNCF 治理 —— 不会消失
- 跨平台（macOS、Linux、Windows 通过 WSL2）
- 标准 `lima.yaml` 配置 —— 容易共享、易复现

**缺点：**

- Apple Silicon 的 `vz` 驱动比 OrbStack 粗糙（启动慢、闲置 RAM 高、偶发挂载卡顿）
- 文件共享需要显式 `sshfs` 或 `9p` 配置 —— 不是自动的
- 没有调资源的原生 UI
- 在 `bin/devbox` 加 Lima 支持意味着把每个函数改写成
  `limactl shell atelier` 而不是 `orbctl run -m atelier`

**结论：** 原则上的第二选择。atelier 能适配——差不多 1 天在 `bin/devbox` 里
加一个 `BACKEND=lima` 开关。我们没做，是因为 Lima 在 Apple Silicon 上的体验
今天比 OrbStack 低一档。

### colima

是什么：Lima 的封装，默认更友好，单个 `colima start` 就能开跑。

**优点：**

- 比裸 Lima 在常见场景下更简单
- 底层 VM 一样

**缺点：**

- Lima 的所有缺点，加上 colima 自己的固执（更难定制）
- 没有 SSH UI；是 `colima ssh` 而不是原生 SSH

**结论：** 同 Lima，在定制性上略差一点。

### Vagrant

是什么：HashiCorp 的"写个 Ruby 文件描述你的开发环境，VirtualBox / Parallels /
VMware / libvirt / Hyper-V 上跑"。

**优点：**

- 跨平台，大家都知道
- Vagrantfile 是唯一真相之源
- provider 覆盖广

**缺点：**

- VirtualBox provider 在 Apple Silicon 上慢（没有原生 Apple Virtualization）
- 没有自动共享文件系统 —— 要 `vagrant rsync` 或 NFS 插件
- CLI 表面巨大（`vagrant up`、`vagrant ssh`、`vagrant provision`、
  `vagrant destroy`、`vagrant reload`、`vagrant global-status`，...）
  比 `orbctl run/shell/...` 多一大截
- Ruby / Chef / Puppet / Ansible 作为 provisioning 语言加了一层我们不需要的抽象
- 没有 `bin/devbox` 这种薄 wrapper；想用就得自己写一个

**结论：** 对一个 5 分钟的沙箱来说大材小用。2014 年它是对的。

### Multipass

是什么：Canonical 的"在 macOS / Windows / Linux 上跑 Ubuntu VM"。在 macOS 上
基于 Apple Hypervisor framework。

**优点：**

- Ubuntu 支持一流
- 一个 CLI：`multipass launch`、`multipass shell`、`multipass exec`
- `multipass mount` 共享文件

**缺点：**

- 在 Apple Silicon 上不如 OrbStack 精细
- `multipass mount` 底层是 `sshfs` —— 比 OrbStack 的自动共享慢
- 社区比 OrbStack 小
- 跟 Docker 没集成（所以"用一个工具拿到 Docker daemon 在快 VM 上"做不到）

**结论：** 如果你已经在 Canonical 生态里了，是合理的第二选择。
包起来的功夫跟 Lima 一样。

### Apple 的 `container`（github.com/apple/container）

是什么：Apple 官方的 Swift 工具（Apache 2.0），把 Linux **container** 跑成
**轻量 VM** —— 一个 container 一个 VM，不是一个共享 VM 装所有 container。
底层也是 Apple `Virtualization.framework`（跟 OrbStack 一套），所以
syscall 层是平级关系，不是"换掉 OrbStack"的关系。OCI 兼容（吃和吐标准
container image）。截至 2026-06 还是 pre-1.0；README 自己说
"stability only guaranteed within patch versions"。

**要求：** macOS 26 全功能，macOS 15 网络受限，**只支持 Apple Silicon**。
Intel 不支持。

**优点：**

- Apple 亲儿子 —— macOS 26 新的 Virtualization 增强一发布就用上
- 每个 container 独立 VM，比共享 VM 的隔离更强（container 逃逸也碰不到宿主）
- 单 container 内存开销比完整 VM 小（Apple 自述：2 GB 跑 busy app vs 完整 VM 约 8 GB）
- 开源，Apache 2.0
- `container` 构出来的 OCI image 跑在 Docker / Podman / k8s 上，反之亦然

**缺点：**

- **Pre-1.0** —— API 稳定性没保证，minor 版本之间可能 break
- **只支持 Apple Silicon** —— Intel Mac 整个 cohort 被砍
- macOS 26 才完整网络能力；macOS 15 网络受限（不能 container-to-container、
  不能多 network、IP 子网偶发 bug）
- 内存 ballooning 只支持一半：container VM 里释放的内存不真还回宿主
  —— 长时间跑大内存负载可能需要定期重启
- **没有"一个持久的 Linux 系统"的概念** —— 每个 container 都是临时的独立
  VM。要装 Node + Python + Go + Rust + starship 得打成一个
  自定义 OCI image 把这些全 bake 进去（工作从 `setup/provision.sh`
  在活 VM 里跑移到 CI build 步骤）
- 没有 `container shell` 等价于 `orbctl shell` —— "进 VM 里随手改"
  这个循环没了
- 宿主文件系统共享是**显式 per-container mount**，不是自动挂

**结论：** atelier 选错了工具。架构对不上：

- atelier 要**一个持久的 Linux 系统**把工具装进去。apple/container 要 **N 个
  临时的每 container 一个 VM**。
- atelier 的 `bin/devbox reset` = nuke VM 重跑 `setup/provision.sh`
  （~5 分钟、幂等、所有工具重装）。apple/container 里，"reset" = 删
  container 重拉 image —— 但如果你 image 是裸 Ubuntu 啥都没装，Node/Python/Go
  之类就丢了，除非你 build 时就 bake 进 image。
- atelier 需要 SSH 进 VM（`ssh -L 7456:127.0.0.1:7456 ...` 把
  open-design web UI 隧道出来）。apple/container 没 SSH 故事，daemon
  得换方式暴露。
- "自动共享 `/Users/lazy/...` → `/mnt/mac/...`" 是 atelier 的核心
  UX。apple/container 要求每 container 显式 mount 配置。

**什么时候 apple/container 是对的？** 如果 atelier 是个 *container 化微服务
工作台* —— "为 k8s demo 拉 12 个临时 OCI container" —— per-container-VM 模型
正合适。对于"我要个 Linux 开发机长住"这件事，OrbStack 的模型更对。

**两边都支持呢？** `bin/devbox` 很小（~250 行，8 个子命令对应 8 个小函数）。
加 `BACKEND=apple-container` 在工程上能做 —— 但要等 Apple container 到 1.0、
CLI / image build 流程稳定了再说。在那之前，把整套 `setup/provision.sh`
 烤进 CI image 的摩擦比 atelier 想承担的大。

## 如果我不是 macOS？

atelier 不支持 Linux 或 Windows 宿主。架构（"宿主保持惰性，所有工具在 VM 里"）
只在宿主是"别的东西"（一台 Mac）时才有意义。在 Linux 宿主上，你自己的开发机
**就是**沙箱——一个紧的 `~/.bashrc` 加 shell init 里的 deny 名单就能拿到大部分
安全性。Windows 上，用 WSL2 + 一个类似 wrapper；我们没有计划 ship 一个。

## 总结

如果你在最近的 Mac（Apple Silicon、macOS 13+）上，又没有绑死在上面某个替代品上，
**装 OrbStack、直接用 atelier 即可**。wrapper 不用糊任何粗糙的边角，因为根本
没有。

如果你是 Intel Mac，OrbStack 仍然能跑，Docker Desktop 速度也差不多。挑一个喜欢的；
迁移到 atelier 的工作量两边一样。

如果你在 Linux 上：架构退化成"别 `sudo`"加一个紧的 deny 名单。我们没有工具做这个——
你现有的 shell 卫生就够了。

如果你在 Windows 上：WSL2 + 一个兄弟项目；atelier 没计划支持。
