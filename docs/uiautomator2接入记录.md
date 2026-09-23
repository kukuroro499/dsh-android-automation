# uiautomator2 over Shizuku 接入记录

**结论：通了，而且全程不需要 adb。**

交付物：`shz_u2.py`（shim + CLI）

---

## 1. 为什么可行

u2 官方客户端靠 **adb 端口转发**访问设备侧 server。本机没有 adb，但：

> **容器与宿主共享网络命名空间** —— 容器能直连 `127.0.0.1:8099` 的 Termux broker（已实测）

所以端口转发这一步可以**整个跳过**，HTTP 直接连 `127.0.0.1:9008`。

设备侧 server 本身就是一句话（来自 `uiautomator2/core.py:78`）：

```
CLASSPATH=/data/local/tmp/u2.jar app_process / com.wetest.uia2.Main -p 9008
```

## 2. 需要替换的三处

| # | 官方做法 | 这里怎么做 |
|---|---|---|
| 1 | `AdbHTTPConnection.connect` 走 `device.create_connection()`（= adb forward） | 改成普通 `socket` 连 `127.0.0.1:PORT` |
| 2 | `adbutils.AdbDevice` 实例 | `ShzDevice(adbutils.AdbDevice)` 子类，覆写 `shell/sync/create_connection`；**`_BaseClient` 用的是 `isinstance` 检查，子类化即可骗过** |
| 3 | server 由 `dev.shell(cmd, stream=True)` 拉起并保持 | 容器侧 `subprocess.Popen(..., start_new_session=True)` 拉起 shz 会话挂住它 |

jar 传输走 **bind-mount 的 `/home/dsh/shared`**（容器写该目录只有 `open()` 能用），
再在设备侧 `cp` 到 `/data/local/tmp`——比 `shz-push` 的 58 个 64KB 分块快得多。

## 3. 实测数据

| 操作 | 旧路径（shz） | uiautomator2 直连 | 倍数 |
|---|---|---|---|
| 控件树 | `uiautomator dump` **3731 ms** | `dump_hierarchy` **252–339 ms**（首次 781） | **~12×** |
| 截图 | `screencap` **1030 ms** | `screenshot` **130–262 ms**（首次 1368） | **~6×** |
| 设备状态 | `dumpsys window` **642 ms** | `d.info` **74 ms** | **~8×** |
| 单次点击 | shz+`input tap` 713 ms | `click` **283 ms**（首次 907） | ~2.5× |
| HTTP 往返 | — | `/ping` **26–67 ms** | — |

附带收益：截图直接返回 **JPEG（216KB）** 而不是 PNG（1MB）——**我读图的 token 成本降到 1/5**。

### 和批量 shz 的关系（重要）

| 场景 | 谁快 |
|---|---|
| 单次 tap | **u2**（283ms vs 713ms） |
| 连续 N 次 tap | **shz 批量**：`650 + 43N` vs u2 `283N` → **N≥3 时 shz 反而更快** |
| dump / 截图 / 状态查询 | **u2 全面碾压** |

所以正确用法是**混用**：用 u2 做"看"和"定位"，用单次 shz 批量做"连续点"。

## 4. 用法

```bash
python3 shz_u2.py status          # server / jar 状态
python3 shz_u2.py start | stop    # 起停设备侧 server
python3 shz_u2.py info            # 当前包名/分辨率/sdk
python3 shz_u2.py dump --find 'id/input'   # 按 id 或文本定位，直接出坐标（不截图！）
python3 shz_u2.py dump --out ui.xml
python3 shz_u2.py shot /tmp/a.jpg
python3 shz_u2.py click 540 1200
python3 shz_u2.py tap-id com.tencent.mobileqq:id/input
```

Python 里：

```python
import shz_u2
d = shz_u2.connect()
d.info
d.dump_hierarchy()
d(resourceId="com.tencent.mobileqq:id/input").click()
d(text="发送").click()
```

## 5. 踩过的坑

1. **`setConfigurator` 里把 `actionAcknowledgmentTimeout` 设 0 会挂死**（我卡了 180s）。
   而且 `waitForIdleTimeout` u2 **默认就已经是 0**，根本不用调——别动它。
2. `screenshot(format='raw')` 在 v3 **已移除**，只剩 `pillow` / `opencv`。
3. **首次调用有冷启动**：截图 1368ms → 暖机 130ms；控件树 781ms → 252ms。别拿首次值当性能。
4. server 是独立 `app_process`，**必须有人拉起来**，不会自动存活；用 `start_new_session=True` 让它脱离调用进程。
5. 期间 **broker 崩过两次**（`Connection refused`），疑似设备内存压力（`free` 仅剩 255MB）。
   supervisor 约 10s 自愈。做实验时别在设备侧 `nohup ... &` 起长驻进程，是它把 broker 搞挂的。
6. QQ 主界面**没有** `id/input`（那是聊天页才有的），定位前先确认在哪个页面。

## 6. 安全说明

设备侧 server 是一个**固定功能的 HTTP 服务**（只暴露 UiAutomator 的 UI 控制接口），
监听 `127.0.0.1:9008`，以 `shell` 身份运行。

比"裸 shell 守候进程"安全得多（拿不到任意命令执行），但**仍等于把 UI 控制权
暴露给本机任意进程**——包括任何 App。不用时建议 `python3 shz_u2.py stop`。
