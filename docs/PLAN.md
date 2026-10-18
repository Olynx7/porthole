# Porthole · 方案（rev.3 / 全屏会话版）

> **porthole**（舷窗）：船壳上开的一个圆窗，只用来望见里面那一小块世界。
> 在一堆 Linux 窗口里开一扇"窗"，看见的是 Windows 里的企业微信——名字就是这个意思。
> 和 `dockur`（docking / 停靠）同属航运隐喻，凑在一起是一个体系。

- **形态**：Podman 容器里的 QEMU/KVM Windows（tiny10）→ FreeRDP **全屏桌面会话** → 企业微信最大化铺满。
- **不是** RemoteApp / RAIL：窗口不是原生窗口，而是"一整块桌面"，里面只跑一个应用。
- 换应用 = 加一个 profile；换 Windows 版本 = 改一行配置。

本文是施工图。已拍板的决策见 §14。

---

## 0. 一句话

```
porthole run
  → 容器起（或从暂停恢复）
  → 等 127.0.0.1:3391
  → xfreerdp +f（无边框全屏，键盘不独占）
  → 屏幕上出现铺满的企业微信
关掉（floatbar ✕ / Ctrl+Alt+Enter→关窗 / porthole stop）
  → podman pause：CPU 0.0%，内存保留
  → 下次 ~1–3s 回到原来界面，登录态还在
```

---

## 1. 三个关键决策（这版和上一版的差别）

| 维度 | 上一版（RAIL / 已废） | **本版（全屏会话）** |
|---|---|---|
| 呈现方式 | RemoteApp 单窗口，`TSAppAllowList` 别名注册 | 普通 RDP 桌面会话，全屏 + 应用最大化 |
| 幽灵窗口 `System32` | **致命**（多出一个假窗口，摘不掉就完蛋） | **降级为可见瑕疵**：真出现了也就是桌面上一个文件夹，关掉即可 |
| Windows 侧复杂度 | 别名注册表 + 会话策略 + 检测回退 | 只做：开 RDP、应用自启、把桌面收拾干净 |
| 其他应用 | 每个都要注册别名、试 RAIL 兼容性 | 改 profile 里的 `exe`，一样全屏跑 |
| 失败概率 | 中（卡在一个查不出属主的窗口上） | 低（RDP 桌面是 Windows 最成熟的功能） |
| 代价 | 有原生窗口边框/任务栏集成 | 没有：看到的是 Windows 桌面（已做观感治理） |

**为什么值得换**：RAIL 的收益（真·单窗口）抵不过它的风险（一个无法归因的幽灵窗口就把项目拖死）。全屏会话用 Windows 最稳的通道实现同一个"看起来像原生应用"的效果，代价只是少了原生窗口边框——反正企业微信本来就是单窗口用的。

---

## 2. 已核实的事实（都在本机验过，不是猜的）

| # | 事实 | 证据 |
|---|---|---|
| 1 | dockur 原生支持 `VERSION=tiny10` | 镜像内 `/run/define.sh:1657` → `https://archive.org/download/tiny-10-23-h2/tiny10 x64 23h2.iso` |
| 2 | ISO：3,839,819,776 B，sha256 `a11116c0…60cc35`，最小磁盘 10G | `/run/define.sh:1658-1660`、`getRequiredDisk` |
| 3 | 可投放自制 ISO：`storage/custom.iso` 会被优先采用 | `/run/install.sh:906` |
| 4 | 首登钩子：`/oem/install.bat` → `C:\OEM\install.bat`，日志 `C:\OEM\install.log` | `/run/answer.sh:1824` |
| 5 | 宿主 `./shared` = Windows 的 `\\host.lan\Data` + `Z:` | `/run/answer.sh:2064-2065`、`/run/batch.sh:12` |
| 6 | FreeRDP 3.32.1 全屏/键盘/浮动条/多屏/驱动器重定向全部可用 | `+f`、`-grab-keyboard`、`/floatbar[:sticky,default,show]`、`/monitors:`、`/drive:`、`/audio-mode:`、`/size:`、`/wm-class:`（`xfreerdp /help` 实测） |
| 7 | 本机已有 dockur 镜像，digest 固定 `sha256:32cc9271…` | `podman images --digests`，**无需重新拉取** |
| 8 | archive.org 单流 0.5–3 MB/s，3 并发 ≈ 10 MB/s | 实测 → 必须 16 并发下载 |
| 9 | 宿主 12 线程 / 60G 内存 / 333G 空闲 / `/dev/kvm` 可用 / podman 5.8.7 rootless | `nproc`、`free`、`df`、`ls /dev/kvm` |
| 10 | `127.0.0.1:7890` 代理可用（下载备线） | `ss -ltnp` |
| 11 | winpodx 残留已清（容器 / 配置 / 日志全删，仅保留 dockur 基础镜像） | 见 §14-5 |

**附：RAIL 结论留档（本版不采用，留给以后）**

- `/network:lan` 在 RAIL 会话会导致服务器 reset（`ERRCONNECT_CONNECT_TRANSPORT_FAILED`）→ 本版桌面会话也**不写** `/network:`。
- `/app:program:` 后面放裸路径会被冒号解析拆坏，必须 `||别名`。
- 别名需 `TSAppAllowList\Applications\<alias>` + `fDisabledAllowList=0`。
- `fSingleSessionPerUser=1` + `MaxDisconnectionTime=60000` 可消除"选择要重连的会话"对话框（本版仍然保留这两项）。
- v1 未解决：RAIL 会话里多出一个标题为 `System32` 的窗口，`XUnmapWindow` 能摘掉但会复发，**始终没做"查属主进程"这个决定性实验**。

---

## 3. 目标 / 非目标

**v1.0 目标**
- `porthole run` 一条命令：冷启动 → 容器起 → 装好的 tiny10 → 全屏 → 企业微信最大化，无人工步骤（扫码除外）。
- 关窗即暂停：CPU 0.0%、内存保留、再开秒级恢复、登录态保持。
- 观感治理：没有任务栏、没有桌面图标、没有锁屏、纯色壁纸、鼠标移到底部也不弹任务栏（尽量）。
- 换应用：`profiles/<app>.toml` 改 `exe` / `installer` / `startup` 即可，其余全复用。
- 可清除：`porthole uninstall --purge` 之后磁盘上不留任何东西。

**非目标**
- 不做原生窗口边框、多应用混合、Alt+Tab 里出现单个 Windows 应用（那是 RAIL 的能力，本版放弃）。
- 不做反虚拟机检测、USB 直通、多显示器分别映射。
- 不自动化扫码登录（首次人工，之后持久化）。
- 不回到 libvirt / Boxes / Wine。

---

## 4. 架构

```
┌─ 宿主 Fedora ──────────────────────────────────────────────────┐
│                                                                │
│  porthole (bash CLI)                                           │
│   ├── podman ──► 容器 porthole-wecom ──► QEMU/KVM ──┐          │
│   ├── xfreerdp +f ──► 一块铺满屏幕的 XWayland 窗口    │          │
│   └── 状态: ~/.config/porthole + ~/.local/share/porthole        │
│                                                     │          │
└─────────────────────────────────────────────────────┼──────────┘
                                      127.0.0.1:3391 (RDP/TLS)
                                                     │
┌─ 容器 dockur/windows ───────────────────────────────▼──────────┐
│   QEMU (KVM, 2C / 4G / 64G 稀疏)  ──►  tiny10 x64 23H2          │
│   samba: /shared  ──►  \\host.lan\Data（安装包/脚本交换）        │
│   /oem/install.bat ──►  首登：开 RDP + 静默装企业微信 + 收拾桌面 │
└────────────────────────────────────────────────────────────────┘

容器内桌面（用户看到的就是它）：
  ┌──────────────────────────────────────────────┐
  │  企业微信（最大化，盖住桌面）                    │
  │                                              │
  └──────────────────────────────────────────────┘
  任务栏：自动隐藏 / 纯色壁纸 / 无图标 / 无锁屏
```

**一次装机（只在第一次发生）**

```
porthole provision
  ├─ 并行下载 tiny10 ISO（16 并发 + sha256）→ storage/custom.iso
  ├─ 渲染 compose.yaml + 生成随机密码（0600）
  ├─ 渲染 oem/ ← windows/*.ps1 + installer + wecom.ico
  ├─ podman up → dockur 无人值守安装 tiny10（2C 下约 25–35 min）
  └─ 首登 install.bat 依次执行：
       10-rdp.ps1     开 RDP（TLS）、单会话、断线回收、关电源策略
       20-desktop.ps1 自动隐藏任务栏 / 纯色壁纸 / 隐藏图标 / 关锁屏屏保
       30-app.ps1     静默装企业微信 + 自启快捷方式（最大化）+ 校验
       写 C:\OEM\status.json  ← porthole 靠它判断装机是否完成
```

**日常（99% 的时间）**

```
porthole run → unpause → 等端口 → xfreerdp +f → 关窗 → pause
```

---

## 5. 仓库结构

```
~/Proj/porthole/
├─ VERSION                       # 单一版本源
├─ README.md  LICENSE(MIT)  CHANGELOG.md
├─ Makefile                      # install / uninstall / check / fmt / test
├─ .editorconfig  .gitattributes # LF vs CRLF 强制
├─ bin/porthole                  # 唯一入口（sh 薄壳）
├─ libexec/
│  ├─ porthole                   # 子命令分发、参数、退出码
│  └─ porthole.d/
│     ├─ 00-env.sh               # 路径/配置/日志/flock 单实例
│     ├─ 10-vm.sh                # up / pause / resume / down / reset / status
│     ├─ 20-iso.sh               # 并行下载 + 校验 + custom.iso 投放
│     ├─ 30-provision.sh         # 渲染 compose/oem、读 status.json
│     ├─ 40-rdp.sh               # 等端口、拼参数（含断言）、全屏会话
│     ├─ 50-doctor.sh            # 诊断 + 打包日志
│     └─ 60-uninstall.sh
├─ config/
│  ├─ porthole.conf.example
│  └─ profiles/
│     ├─ wecom.toml
│     └─ notepad.toml            # 冒烟测试用最小 profile
├─ windows/                      # 全部 ASCII + CRLF，CI 强制
│  ├─ install.bat                # 首登入口，幂等，日志 C:\OEM\install.log
│  ├─ 10-rdp.ps1
│  ├─ 20-desktop.ps1
│  ├─ 30-app.ps1
│  └─ lib/common.ps1             # 注册表/重试/日志小工具
├─ assets/
│  ├─ icons/wecom.svg + wecom-{16..256}.png
│  └─ porthole-wecom.desktop.in  # StartupWMClass=porthole
├─ tools/
│  ├─ check-encoding.sh          # ASCII/CRLF/LF/BOM 守卫
│  └─ iso.lock                   # 固定 size + sha256
├─ systemd/porthole-idle.service # 可选：长时间暂停后自动关机
└─ docs/
   ├─ PLAN.md                    # 本文
   ├─ RUNBOOK.md                 # 装机/重装/换版本/排障
   └─ DECISIONS.md               # ADR：为何全屏而非 RAIL、为何 dockur、为何断言
```

**规范**
- 编码：`.bat/.cmd/.ps1/.reg` = **ASCII + CRLF**；`.sh/.py/.toml/.md` = **LF**；全部无 BOM。`make check` 不绿不许装。
- Bash：`set -euo pipefail` + ShellCheck clean；日志进 `$XDG_STATE_HOME/porthole/logs/`。
- PowerShell：PS 5.1 语法（禁用 `??`、三元、`-Parallel`）。
- 版本：`VERSION` 单源，`porthole --version` / CHANGELOG / 镜像 tag 三处一致。

---

## 6. 配置模型

优先级：**命令行 > profile TOML > porthole.conf > 内置默认**

```toml
# config/profiles/wecom.toml
[profile]
id   = "wecom"
name = "企业微信"
icon = "wecom"

[vm]
version      = "tiny10"      # tiny10 | ltsc10 | 10 | 11
image        = "ghcr.io/dockur/windows@sha256:32cc9271..."   # 钉住 digest
cpus         = 2
ram          = "4G"
disk         = "64G"          # 稀疏，实占约 18–22G
language     = "Chinese"
region       = "zh-CN"
keyboard     = "zh-CN"
timezone     = "Asia/Shanghai"
username     = "porthole"
rdp_port     = 3391           # 只绑 127.0.0.1
console_port = 8006           # dockur Web 控制台，只绑 127.0.0.1

[session]
mode          = "fullscreen"  # fullscreen | window
grab_keyboard = false         # false = 让 GNOME 留住 Super/Alt+Tab
floatbar      = true          # 全屏时的浮动小条（带 ✕ 断开）
dpi_scale     = 125           # 0 = 跟随 Windows 默认
monitors      = ""            # 空 = 当前显示器
extra_args    = []            # 逃生口

[app]
alias        = "WeCom"
exe          = 'C:\Program Files\WXWork\WXWork.exe'
installer    = "WeCom_5.0.12.6018.exe"   # 放 ~/Downloads 或 shared/
install_args = ["/S"]
startup      = true           # 登录后自启
maximized    = true           # 自启快捷方式 WindowStyle=3

[rdp]
security = "tls"              # tls | nla | rdp

[lifecycle]
pause_on_close      = true
stop_after_idle_min = 0       # 0 = 永不自动关机
```

---

## 7. 运行时布局

```
~/.local/share/porthole/wecom/
├─ storage/          # → /storage（disk.img 稀疏 64G）
├─ shared/           # → /shared → \\host.lan\Data
├─ oem/              # 装机期快照（由 windows/ 渲染）
└─ state.json        # 阶段、完成时间、镜像 digest、装了什么

~/.config/porthole/
├─ porthole.conf
├─ compose.yaml      # 渲染产物，不手改
├─ secrets/wecom.env # 0600，WINDOWS_PASSWORD=…
└─ profiles/wecom.toml
```

---

## 8. 关键实现决策

### 8.1 RDP 参数模板

```sh
exec xfreerdp \
  /v:127.0.0.1:3391 /u:porthole /p:"$WINDOWS_PASSWORD" /cert:ignore /sec:tls \
  /f -grab-keyboard \
  /floatbar:sticky:off,default:hidden,show:fullscreen \
  /sound /clipboard \
  /drive:shared,"$HOME/.local/share/porthole/wecom/shared" \
  /kbd:lang:0x804 \
  /wm-class:porthole \
  /dynamic-resolution \
  /log-level:WARN
```

| 参数 | 为什么 |
|---|---|
| `/f` | 全屏；`Ctrl+Alt+Enter` 可切回窗口 |
| `-grab-keyboard` | 不让 RDP 独占键盘 → `Super` / `Alt+Tab` 仍归 GNOME |
| `/floatbar` | 全屏下唯一的退出入口（✕ = 断开 → 触发 pause） |
| `/cert:ignore` + `/sec:tls` | 自签证书；TLS 不依赖 NLA，兼容性最好 |
| `/drive:shared` | 把宿主目录挂进 Windows 的"网络位置"，发文件用 |
| `/wm-class:porthole` | 与 `.desktop` 关联（图标、任务栏分组） |
| `/dynamic-resolution` | 改分辨率/缩放时窗口跟着变 |
| **不写 `/network:`** | RAIL 时代它导致过 reset；本版也没必要 |

**断言（写进 `40-rdp.sh`）**
- 拼完参数后 `grep -q '/network:'` → 命中即 `die`。
- 端口必须 `127.0.0.1`。
- 密码不能出现在 `ps` 可见的 argv：v1.0 用临时 args 文件 + `/args-from:file:`。

### 8.2 桌面观感治理（`20-desktop.ps1`）

目标：让用户只看到企业微信，看不到"这是一个 Windows"。

| 项 | 做法 |
|---|---|
| 任务栏 | `StuckRects3\Settings` 的 byte[8] 改 `0x03`（自动隐藏），然后重启 explorer |
| 桌面图标 | `HKCU\…\Explorer\Advanced\HideIcons = 1` |
| 壁纸 | 纯色 `Control Panel\Colors\Background = "0 0 0"`、`Desktop\Wallpaper = ""` |
| 锁屏/屏保 | `NoLockScreen=1`、`ScreenSaveActive=0`、`ScreenSaverIsSecure=0` |
| 睡眠 | `powercfg /change monitor-timeout-ac 0` / `standby-timeout-ac 0` / `hibernate-timeout-ac 0` |
| 搜索框/组件 | `Search\SearchboxTaskbarMode=0`、`TaskbarGlomLevel=2` |
| 其他 | 不折腾右键菜单、不删系统组件 |

> 原则：**只改观感，不改系统行为**；每一项独立可回滚，`--no-desktop-tweaks` 可整体关闭。

### 8.3 会话卫生

- `fSingleSessionPerUser=1` + `MaxDisconnectionTime=60000` → 断开的会话 60s 内回收，不会出现"选择要重连的会话"。
- `MaxIdleTime=0`、其余超时全关 → 不会话到一半被踢。
- 关机用 `podman stop`（2 min 宽限 → ACPI 关机），不用 `kill`，避免 NTFS 脏位。
- 暂停恢复后可能出现时钟跳变导致锁屏：已由 §8.2 兜住。

### 8.4 生命周期

| 事件 | 动作 | 代价 |
|---|---|---|
| 关窗（floatbar ✕ / 关窗口） | `podman pause` | CPU 0.0%，内存仍占 4G |
| 再 `porthole run` | `unpause` → 等端口 → 连接 | 1–3s |
| `porthole down` | `podman stop`（ACPI 关机） | 30–60s；冷启 60–90s（2C 偏慢） |
| 暂停超时 | systemd 定时器 → `down` | 释放 4G 内存 |
| 重复启动 | `flock $XDG_RUNTIME_DIR/porthole/wecom.lock` | 第二个实例直接退出 |

### 8.5 ISO 获取

- 16 并发 range 下载 + 断点续传 + `sha256sum -c`（`tools/iso.lock` 固定 size/sum）。
- 回退顺序：直连 → `127.0.0.1:7890` 代理 → 手动下载后 `porthole iso --import <file>`。

### 8.6 分辨率与缩放

- 全屏尺寸由 FreeRDP 按当前显示器决定，`/dynamic-resolution` 跟随变化。
- Windows 侧 `dpi_scale`（默认 125）写 `Control Panel\Desktop\LogPixels = 120` + `Win8DpiScaling=1`。
- 字偏小/偏大：`--dpi 100|125|150` 直接试，不用重装。

### 8.7 输入法 / 剪贴板 / 声音 / 文件

| 通道 | 方案 | 验证 |
|---|---|---|
| 中文输入 | 用**客机内**微软拼音（`zh-CN` 已装），不指望客户端 IME 透传 | 在企业微信里打一段中文 |
| 剪贴板 | `/clipboard`，文本 + 图片双向 | 两边各复制一次 |
| 声音 | `/sound` → PipeWire | 播一条语音消息 |
| 文件 | `/drive:shared` + `\\host.lan\Data` | 从 Linux 发一张图 |

### 8.8 Windows 侧脚本规范

- 全 ASCII + CRLF、PS 5.1 语法。
- `install.bat` **幂等**：`C:\OEM\.done-*` 标记跳过；每步最多重试 3 次、间隔 5s。
- 装企业微信前轮询 `Test-Path \\host.lan\Data` 最多 120s（首登时 SMB 可能还没起）。
- 全程日志 `C:\OEM\install.log`；结果写 `C:\OEM\status.json`。

---

## 9. 里程碑

| # | 内容 | 产物 | 验收 | 回滚 | 估时 |
|---|---|---|---|---|---|
| **M0** | 骨架 + 编码守卫 + CLI 壳（`status/logs/doctor` 可跑） | repo，`make check` 绿 | `porthole --version && make check` | `rm -rf ~/Proj/porthole` | 1h |
| **M1** | ISO 并行下载 + 校验 + 投放 | `storage/custom.iso` | `porthole iso --verify` 通过 | 删 iso 重下 | 0.2h |
| **M2** | 容器起 + tiny10 无人值守装完 + RDP 可连 | 运行中的 `porthole-wecom` | `porthole status` 显示 RDP ready；`porthole shell` 能进桌面 | `porthole reset` | 2h（多为等待） |
| **M3** | Windows 侧配置 + 企业微信静默装 + 能启动 | `C:\OEM\status.json` ok | 桌面里企业微信跑到扫码页 | `porthole provision --force` | 1.5h |
| **M4** | 全屏会话成型 + 观感治理 + 验收 | `porthole run` 出全屏企业微信 | 看不到任务栏/图标/锁屏；`Ctrl+Alt+Enter` 能切窗口 | 关 `--no-desktop-tweaks` | 1.5h |
| **M5** | 宿主集成：图标、desktop entry、剪贴板/输入法/声音/文件四项实测 | `.desktop` + 图标 | 应用菜单点开即用；四项全通 | 删 entry | 1.5h |
| **M6** | 生命周期 + doctor + RUNBOOK + 1.0 tag | 文档、诊断包 | 关窗 CPU 0%；再开 <5s | — | 2h |

合计 **约 10 小时**。M4 从"高风险闸门"变成"收尾工作"——这就是换方案换来的。

---

## 10. 风险登记表

| 风险 | 概率 | 影响 | 早期信号 | 对策 |
|---|---|---|---|---|
| tiny10 精简掉了 RDP | 中 | 高 | 3391 不通 / 3389 未监听 | `10-rdp.ps1` 强制开服务+防火墙；仍不行换 `ltsc10`（一行） |
| tiny10 缺组件（语音/视频/文件对话框） | 中 | 中 | 语音放不出、通话失败 | `ltsc10` 兜底 |
| **4G 内存偏紧** | 中 | 中 | 卡顿、页面文件狂读 | `ram = "6G"` 一行改 |
| 2C 装机/冷启慢 | 高 | 低 | 冷启 90s+ | 接受；日常靠 pause 避免冷启 |
| 任务栏隐藏后被鼠标唤出 | 中 | 低 | 鼠标到底部弹出 | 纯色壁纸 + 精简任务栏；仍烦就上 §11 的 Kiosk 外壳 |
| DPI 不对 → 字发虚/过小 | 中 | 中 | 目测 | `--dpi 100/125/150` 直接试 |
| 键盘不独占导致部分 Win 快捷键失效 | 中 | 低 | `Win+E` 不开资源管理器 | `--grab-keyboard` 临时开 |
| OOBE 卡住（tiny10 改过镜像） | 低中 | 高 | 30 min 无 RDP | `podman logs` / 8006 控制台；对照 `VERSION=10` |
| archive.org 慢 | 中 | 中 | < 1 MB/s | 16 并发 + 代理 + 手工导入 |
| 暂停后恢复蓝屏/花屏 | 低 | 中 | unpause 后黑屏 | 降级为 stop/start（`pause_on_close=false`） |

---

## 11. 观感上限：还能再进一步吗

全屏会话的天花板是"看得见 Windows 桌面"。想更彻底，有一条**不用 RAIL** 的路：

**Kiosk 外壳（可选，v1.1）**：把该用户的 `Winlogon\Shell` 设成企业微信（或 `cmd /c start /max WXWork.exe`）。
登录后没有 explorer、没有任务栏、没有桌面，屏幕上只有企业微信，RDP 只是个显示器。

- 收益：彻底没有"Windows 感"，不用打自动隐藏这种补丁。
- 风险：没有 explorer 就没有托盘、没有"打开文件夹"，某些系统对话框可能异常。
- 结论：**v1.0 不做**，预留 `session.shell = "explorer" | "app"` 开关；M4 之后你觉得任务栏碍事，再单独试一天。

---

## 12. 验收清单（v1.0 DoD）

- [ ] 冷启动机器上 `porthole run` 一条命令到全屏企业微信，除扫码外零人工
- [ ] 关窗 3s 内 CPU ≤ 0.5%，`podman ps` 显示 `(Paused)`
- [ ] 再开 < 5s，回到原界面，登录态还在
- [ ] 看不到：Windows 任务栏 / 桌面图标 / 锁屏 / 屏保
- [ ] 中文输入、双向粘贴（文本+图片）、声音、从 Linux 发文件，四项实测通过
- [ ] `Super` / `Alt+Tab` 能切回 Linux 应用；`Ctrl+Alt+Enter` 能退出全屏
- [ ] `porthole doctor --bundle` 生成可直接贴 issue 的诊断包
- [ ] `porthole uninstall --purge` 后：数据目录、容器、镜像、卷、desktop entry 全无
- [ ] `make check` 绿；RUNBOOK 覆盖装机/重装/换版本/RDP 不通/内存不够

---

## 13. 资源预算

| 项 | 值 | 说明 |
|---|---|---|
| 磁盘峰值 | ~23 GB | ISO 3.6G（装完可删）+ disk.img 实占 ~18G |
| 内存 | **4 GB**（VM） | 暂停期间仍占用；不够改一行到 6G |
| CPU | **2 核** | 空闲时 QEMU ≈ 0% |
| 端口 | 3391 / 8006 | 均只绑 `127.0.0.1` |

---

## 14. 已拍板 + 待定

**已定**
1. 名字：**porthole**（备选 oriel / casement / sill 未采用）。
2. 资源：**2 核 / 4G / 64G 稀疏磁盘**。
3. 登录：首次人工扫码，之后持久化。
4. 会话形态：**全屏桌面会话**（不用 RAIL），后续其他应用同样处理。
5. winpodx：容器 + 配置 + 日志已全删；**只保留 dockur 基础镜像**（正是本方案要用的，重拉反而慢且 digest 会漂）。

**还需你一句话确认（不影响开工）**
- 磁盘 **64G 稀疏**（实占 ~18G）可以吗？
- 任务栏：先按"自动隐藏"做（§8.2），还是直接一步到位试 **Kiosk 外壳**（§11，企业微信当 shell、没有任务栏）？我建议前者，后者留 v1.1。

给我一个"开工"，我就从 M0 往下推；M2 装系统那 30 分钟挂着跑，期间顺手把 M5 的桌面集成写好。
