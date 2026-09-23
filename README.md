# Android 免 adb 自动化工具集

在**没有 root、没有 adb** 的 Android 设备上做 UI 自动化（含群聊自动应答）。
运行环境：设备上的 PRoot 容器（Ubuntu），通过 Shizuku 以 `shell`(uid 2000) 身份执行命令，
或用 **AutoX.js 的无障碍服务**直读屏幕。

## 两条通道，各司其职

| | 无障碍直读 | Shizuku（uiautomator / input） |
|---|---|---|
| 读一次 | **瞬时** | dump 约 3.7 秒 |
| 依赖 Shizuku | **否** | 是（且经常掉线） |
| 适用 | **QQ**（节点树完整） | 通用，也是唯一能发中文的路径 |
| 不适用 | **微信**（完全屏蔽节点树） | — |

> **微信一个节点都不给**（`uiautomator dump` 只有 1 个空节点），只能「截图 + 多模态读图」。
> QQ 相反，无障碍读得又快又全。详见 `docs/无障碍通道实现.md`。

## 组件

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
