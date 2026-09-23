#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qq-at-check.py —— 检测 QQ「示例群」群里【新的】@我

实测样本（2026-09-23 19:38 真实抓到）：
    notify pkg=com.tencent.mobileqq title=示例群 text=[有人@我]群友B @示例昵称 ？

命中条件（或关系）：
    A) QQ 自己的标记 **[有人@我]** —— 权威，必须保留
       （通知文本可能截断在 @ 之前，那时只有 A 能救）
    B) 文本里出现 **@示例昵称**       —— 兜底，只在带 @ 时命中
    两者都不认纯文本提到的「示例昵称 / 其它写法」，避免闲聊误触发。

去重：按【内容哈希】，不是行数水位。
   原因：实测日志行数会回落（1629 -> 1628），纯水位会漏判或误判。
   全量扫描 + 哈希集合，对日志重置天然免疫。

退出码：0=有新 @（逐行 AT|...） 1=无 2=链路故障
"""
import hashlib
import json
import os
import subprocess
import sys
import time

LOG = "/sdcard/dsh-notify.log"
STATE = "/home/dsh/.qq_at_state.json"
# ⚠️ 改成你自己要监听的群名（必须与通知里的 title 完全一致）
GROUP = "示例群"
MARK = "[有人@我]"
# 兜底别名：只认带 @ 的正式召唤，不认纯文本提到的「示例昵称/其它写法」
# ⚠️ 改成你自己的群昵称
AT_ALIASES = ("@示例昵称",)
SHZ = "/usr/local/bin/shz"
MAX_SEEN = 300


def shz(cmd, timeout=30):
    try:
        r = subprocess.run([SHZ, cmd], capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return 3, "TIMEOUT"



HB = "/sdcard/dsh-notify.hb"
JS = "/sdcard/脚本/dsh-notify.js"
INTENT = (f"am start -n org.autojs.autoxjs.v6/org.autojs.autojs.external.open.RunIntentActivity "
          f"-a android.intent.action.VIEW -d file://{JS} -t text/javascript")
HB_STALE_SEC = 150   # 90 太紧：App 后台时 MIUI 限流 JS 定时器，会造成误判重启


def heartbeat_age():
    """返回心跳文件的年龄（秒）。取不到就返回 9999。"""
    rc, out = shz(f"cat {HB} 2>/dev/null")
    try:
        return time.time() - int(out.strip()) / 1000.0
    except Exception:
        return 9999.0


def ensure_alive(verbose=True):
    """心跳过期就用 intent 重启 AutoX 脚本（实测有效）。
    AutoX 的 JS 脚本会随 App 进程被系统回收而死，没有这一步监控会静默失效。"""
    age = heartbeat_age()
    if age <= HB_STALE_SEC:
        return False, age
    rc, out = shz(INTENT)
    ok = "Starting:" in out
    if verbose:
        print(f"WATCHDOG: 心跳过期 {age:.0f}s -> 重启脚本 {'已下发' if ok else '下发失败'}")
    return True, age


def h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:16]


def matches(line):
    """或条件：
       A) QQ 自己的 [有人@我] 标记  —— 权威
       B) 文本里出现 @示例昵称        —— 兜底（只在带 @ 时命中）
    保留 A 是必要的：通知可能截断在 @ 之前，那时只有 A 能救。
    """
    if "com.tencent.mobileqq" not in line or GROUP not in line:
        return False
    return MARK in line or any(a in line for a in AT_ALIASES)


def load():
    if os.path.exists(STATE):
        try:
            d = json.load(open(STATE))
            return list(d.get("seen", [])), d
        except Exception:
            pass
    return [], {}


def save(seen, extra=None):
    d = {"seen": seen[-MAX_SEEN:]}
    if extra:
        d.update(extra)
    json.dump(d, open(STATE, "w"), ensure_ascii=False)


def main():
    if "--no-watchdog" not in sys.argv:
        ensure_alive()
    rc, out = shz(f"cat {LOG} 2>/dev/null")
    if rc != 0 or "Request timeout" in out or "Server is not running" in out:
        print("LINK_DOWN " + out.strip()[:80]); return 2
    lines = out.splitlines()
    all_at = [l for l in lines if matches(l)]
    seen, _ = load()

    if "--init" in sys.argv:
        save([h(l) for l in all_at], {"lines": len(lines)})
        print(f"BASELINE_SET: 已把现存 {len(all_at)} 条 @ 标记为已处理（共 {len(lines)} 行）")
        return 1

    new = [l for l in all_at if h(l) not in seen]
    save(seen + [h(l) for l in new], {"lines": len(lines)})

    if not new:
        print(f"NO_NEW_AT (全量扫 {len(lines)} 行，历史 @ {len(all_at)} 条，均已处理)")
        return 1
    for l in new:
        print("AT|" + l)
    return 0


if __name__ == "__main__":
    sys.exit(main())
