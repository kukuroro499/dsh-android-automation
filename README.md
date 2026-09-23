# Android 免 adb 自动化工具集

在**没有 root、没有 adb** 的 Android 设备上做 UI 自动化（含群聊自动应答）。
运行环境：设备上的 PRoot 容器（Ubuntu），通过 Shizuku 以 `shell`(uid 2000) 身份执行命令，
或用 **AutoX.js 的无障碍服务**直读屏幕。

## 实测范围

> **目前只在 QQ 和微信上做过实测**，其余 App **未验证**。

> **全部实测都是在 `dsh` 驱动下完成的** —— `dsh` 是跑在设备 PRoot 容器里的 AI agent：
> 读屏 → 判断 → 组织回复 → 发送 → 校验，整条链路由它调度执行。
> 脚本本身**不绑定 dsh**，任何能执行 shell 的环境都能驱动它们。

| App | 读 | 发 |
|---|---|---|
| **QQ** | ✅ 无障碍直读，节点树完整 | ✅ ADBKeyboard 注入 + 色彩定位发送键 |
| **微信** | ⚠️ 不暴露节点树，只能截图 + 多模态读图 | ✅ 绿色发送键定位 + 绿块归零校验 |
| 其它 App | ❓ 未测试 | ❓ 未测试 |

思路是通用的（**读走无障碍，发走 ADBKeyboard + 颜色/坐标定位**），但每个 App 的
选择器、发送键位置、是否暴露节点树都要**重新实测**，不能直接照搬。
换 App 前建议先跑一次：`uiautomator dump` 看有没有节点树，再截图量发送键。

## 两条通道，各司其职

| | 无障碍直读 | Shizuku（uiautomator / input） |
|---|---|---|
| 读一次 | **瞬时** | dump 约 3.7 秒 |
| 依赖 Shizuku | **否** | 是（且经常掉线） |
| 适用 | **QQ**（节点树完整） | 通用，也是唯一能发中文的路径 |
| 不适用 | **微信**（完全屏蔽节点树） | — |

> **微信一个节点都不给**（`uiautomator dump` 只有 1 个空节点），只能「截图 + 多模态读图」。
> QQ 相反，无障碍读得又快又全。详见 `docs/无障碍通道实现.md`。

## 拿到 root 之后能更进一步

上面所有方案都是**无 root 下的妥协产物**。设备一旦 root，agent 的能力会多一个量级：

| 能力 | 无 root（本仓库现状） | 有 root |
|---|---|---|
| 读聊天内容 | 只能读屏：无障碍节点树 / 截图 + 多模态 | **直接读 App 的 SQLite 数据库**——结构化、全量、不丢消息 |
| 微信 | ❌ 完全屏蔽节点树，只能截图识别 | ✅ 读库即可，**这个问题直接消失** |
| shell 通道 | 依赖 Shizuku，且**经常掉线** | 直接用 root shell，**不需要 Shizuku** |
| 网络 | 无 `net_raw` / `net_admin` | `tcpdump` 抓包、`iptables` 控制 |
| 开机自启 | 非 root 无法自启 Shizuku，每次重启要手动点 | 写 init 脚本，**全自动** |
| 深度集成 | 只能走 UI | Frida / LSPosed 直接 hook 应用逻辑 |
| 系统设置 | `settings put` 常被厂商忽略（实测 MIUI 对通知监听无效） | 直接改，或改数据库 |

**最关键的一条：用「读库」替代「读屏」。**

现在整套方案里最脆的部分——找坐标、色彩定位、无障碍被屏蔽、前台窗口被抢、
键盘弹起导致布局位移——**根源都是"只能从屏幕上把信息抠出来"**。
能读数据库的话，这些统统不需要。

> ⚠️ 代价也要说清：root 会**失去保修、可能影响银行/支付类 App、降低系统安全性**，
> 不同机型 root 难度差异极大。**本仓库不提供 root 方案**，只说明能力边界。
>
> 另外，即使 root，**Keystore 里的密钥仍然拿不到**——这是硬件隔离，不是权限问题。


### 读 / 监听
| 文件 | 说明 |
|---|---|
| `dsh-a11y.js` | **常驻 AutoX 无障碍脚本**。每 800ms 把当前前台 App（QQ/微信）的文本节点按 y 排序写入 bind-mount 文件，并写心跳。纯只读。 |
| `a11y-watch.sh` | 盯无障碍输出文件，内容一变就退出并打印 |
| `a11y-ensure.sh` | 看门狗：心跳 >90s 判定脚本死亡 → 重绑无障碍 + intent 重启 |
| `qq-group-watch.sh` | 盯 QQ 当前群：签名 = 群名 + 聊天区末尾 3 行；每 30 秒检查一次前台，被悬浮面板挤掉就拉回 |
| `qq-watch.py` | 早期版本：轮询屏幕文本（改用无障碍前） |
| `qq-read.sh` | `uiautomator dump` 读 QQ 文本（约 3.7s，作为地面真相复核用） |
| `qq-at-check.py` | 基于**通知**的 @ 检测。命中条件：`[有人@我]` **或** `@昵称`；内容哈希去重 |

### 发
| 文件 | 说明 |
|---|---|
| `qq-fast.sh` | **QQ 发送（推荐）**。ADBKeyboard 注入 + 色彩定位发送键 + 无障碍文件校验，**零 dump**，约 **8~9.5 秒** |
| `qq-fire.sh` | QQ 发送（稳版）。用 `uiautomator dump` 定位发送键，13~16 秒 |
| `qq-send.sh` | 早期版本。收尾会切回讯飞 → 键盘弹起 → 坐标失效，易失败 |
| `wx-fire.sh` | 微信发送。绿色发送键定位 + 绿块归零校验 |
| `wx-send.sh` | 早期微信发送 |
| `shot.sh` | 截图并转 JPG（PNG 843KB → JPG 136KB，多模态成本降约 6 倍） |
| `shz_u2.py` | **uiautomator2 over Shizuku**：u2 客户端直连设备侧 socket，跳过 `adb forward` |

### 文档 / 示例
| 文件 | 说明 |
|---|---|
| `docs/无障碍通道实现.md` | 无障碍通道的启用、设计、四个实测大坑（微信屏蔽 / 面板抢前台 / 空读 / 残缺读） |
| `docs/发送通道与坐标实测.md` | 坐标漂移、色彩定位、三种校验判据的成败、ADBKeyboard 常驻的理由 |
| `docs/uiautomator2接入记录.md` | u2 接入原理与性能对比 |
| `docs/点击流程提速调研.md` | 各项操作成本实测 |
| `examples/qq-persona.md` | 群内人设/规则样例（含注入防护、频率控制） |
| `examples/qq-stickers.md` | 收藏表情格子坐标 + 自动检测方法 |

## 关键实测数据

| 操作 | 传统 shz 路径 | uiautomator2 直连 | 无障碍 |
|---|---|---|---|
| 控件树 | `uiautomator dump` 3731 ms | `dump_hierarchy` 252–339 ms | **瞬时** |
| 截图 | `screencap` 1030 ms | `screenshot` 130–262 ms | — |
| 设备状态 | `dumpsys window` 642 ms | `d.info` 74 ms | — |
| 单次点击 | `input tap` 713 ms | `click` 283 ms | — |
| 一次 `shz` 往返 | 650~713 ms | — | — |
| 完整发一条 QQ 消息 | — | — | **8~9.5 s** |

截图返回 JPEG 而非 PNG，多模态读取成本降至约 1/6。

## 为什么不需要 adb

容器与 Android 宿主**共享网络命名空间**，所以设备侧 server 监听的
`127.0.0.1:PORT` 可被容器直接连接，`adb forward` 那一步整个跳过。
同理，Termux 侧的 broker（`127.0.0.1:8099`）也能被容器直连——这是 `shz` 的工作方式。

设备侧 u2 server 本体就是一条命令：

```sh
CLASSPATH=/data/local/tmp/u2.jar app_process / com.wetest.uia2.Main -p 9008
```

## 用法

```bash
# --- 无障碍通道 ---
SVC=org.autojs.autoxjs.v6/com.stardust.autojs.core.accessibility.AccessibilityService
shz "settings put secure enabled_accessibility_services $SVC; settings put secure accessibility_enabled 1"
shz 'am start -n org.autojs.autoxjs.v6/org.autojs.autojs.external.open.RunIntentActivity \
     -a android.intent.action.VIEW -d file:///sdcard/dsh-shared/dsh-a11y.js -t text/javascript'
./a11y-watch.sh 2 40          # 盯屏（2 秒轮询，最长 40 分钟）

# --- 发送 ---
./qq-fast.sh "消息"           # QQ，约 8 秒
./wx-fire.sh "消息"           # 微信
./shot.sh /tmp/a              # 截图转 JPG
```

```bash
# --- uiautomator2 通道 ---
pip install uiautomator2
python3 shz_u2.py start
python3 shz_u2.py dump --find 'id/input'
python3 shz_u2.py stop
```

## 安全提醒

- `shz_u2.py start` 会在设备上以 `shell` 身份运行一个监听 `127.0.0.1:9008` 的
  固定功能 HTTP 服务（仅暴露 UiAutomator 的 UI 控制接口，无法任意命令执行）。
  但它仍等于把 UI 控制权暴露给本机任意进程，**不用时请 `stop`**。
- ADBKeyboard 常驻会导致**手机无法手动打字**（它没有可视键盘）。恢复：
  `ime set com.iflytek.inputmethod.miui/.FlyIME`。
- `dsh-a11y.js` 是**只读**的；它不含任何发送逻辑。

## 前置条件

- 设备已启动 Shizuku（非 root 无法开机自启，每次重启需手动启动一次）
- 容器内可用 `shz`（Shizuku shell 通道）
- 中文输入需自行安装 ADBKeyboard（<https://github.com/senzhk/ADBKeyBoard>）
- 无障碍通道需安装 AutoX.js 并启用其无障碍服务

## 免责声明

- 本项目**仅供技术学习与研究**。用它自动化微信、QQ 等应用**可能违反其服务条款**，
  账号存在被限制的风险，**后果自负**。
- 代码按「现状」提供，不保证可用性。设备厂商策略、应用版本更新都可能让它失效。
- 仓库内所有群名、昵称、账号均已替换为中性占位（`示例群` / `群友A` / `示例昵称`）。
  使用时请填入你自己的值。
- 请勿用于骚扰、刷屏、爬取他人信息或任何违法用途。

## 许可

本项目代码采用 **MIT License**，见 [LICENSE](LICENSE)。

**第三方组件（本仓库只引用、不打包）：**

| 组件 | 用途 | 许可 |
|---|---|---|
| [uiautomator2](https://github.com/openatx/uiautomator2) / [android-uiautomator-server](https://github.com/openatx/android-uiautomator-server) | 控件树 / 截图 / 点击 | MIT |
| [AutoX.js (Auto.js v6)](https://github.com/automan-bot/AutoX) | 设备端 JS + 无障碍服务 | 见其仓库 |
| [ADBKeyboard](https://github.com/senzhk/ADBKeyBoard) | 中文/emoji 输入注入 | Apache-2.0 |
| [Shizuku](https://github.com/RikkaApps/Shizuku) | 免 root 的 shell 通道 | Apache-2.0 |
