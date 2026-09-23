# Android 免 adb 自动化工具集（Shizuku 版）

在**没有 root、没有 adb** 的 Android 设备上做 UI 自动化。
运行环境：设备上的 PRoot 容器（Ubuntu），通过 Shizuku 以 `shell`(uid 2000) 身份执行命令。

## 组件

| 文件 | 说明 |
|---|---|
| `shz_u2.py` | **uiautomator2 over Shizuku**。把 u2 的 HTTP 客户端从 adb 端口转发改成直连 socket，并子类化 `adbutils.AdbDevice` 让 u2 接受 shz 后端。含 CLI。 |
| `wx-send.sh` | 微信发消息单次往返快速通道。ASCII 走 `input text`，中文/emoji 走 ADBKeyboard 广播 `ADB_INPUT_B64`，含输入法自动切换与还原。 |
| `docs/uiautomator2接入记录.md` | 接入原理、实测性能对比、踩坑记录 |
| `docs/点击流程提速调研.md` | 各项操作的成本实测与方案调研 |

## 关键实测数据

| 操作 | 传统 shz 路径 | uiautomator2 直连 | 倍数 |
|---|---|---|---|
| 控件树 | `uiautomator dump` 3731 ms | `dump_hierarchy` 252–339 ms | ~12× |
| 截图 | `screencap` 1030 ms | `screenshot` 130–262 ms | ~6× |
| 设备状态 | `dumpsys window` 642 ms | `d.info` 74 ms | ~8× |
| 单次点击 | `input tap` 713 ms | `click` 283 ms | ~2.5× |

截图返回 JPEG(216KB) 而非 PNG(1MB)，多模态读取成本降至 1/5。

## 为什么不需要 adb

容器与 Android 宿主**共享网络命名空间**，所以设备侧 server 监听的
`127.0.0.1:PORT` 可被容器直接连接，`adb forward` 那一步整个跳过。

设备侧 server 本体就是一条命令：

```sh
CLASSPATH=/data/local/tmp/u2.jar app_process / com.wetest.uia2.Main -p 9008
```

## 用法

```bash
pip install uiautomator2
python3 shz_u2.py start        # 推送 jar 并拉起设备侧 server
python3 shz_u2.py info
python3 shz_u2.py dump --find 'id/input'    # 按 id 定位，直接出坐标，不用截图
python3 shz_u2.py shot /tmp/a.jpg
python3 shz_u2.py click 540 1200
python3 shz_u2.py stop
```

```bash
./wx-send.sh "消息"        # 直接发
./wx-send.sh -n "消息"     # 演练：只输入不发送，并自动清空
```

## 安全提醒

`shz_u2.py start` 会在设备上以 `shell` 身份运行一个监听 `127.0.0.1:9008` 的
固定功能 HTTP 服务（仅暴露 UiAutomator 的 UI 控制接口，无法任意命令执行）。
但它仍等于把 UI 控制权暴露给本机任意进程，**不用时请 `stop`**。

## 前置条件

- 设备已启动 Shizuku（非 root 无法开机自启，每次重启需手动启动一次）
- 容器内可用 `shz`（Shizuku shell 通道）
- 中文输入需自行安装 ADBKeyboard（<https://github.com/senzhk/ADBKeyBoard>）
