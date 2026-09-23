#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qq-watch.py —— 保持 QQ 前台，轮询屏幕文本；屏幕一变就打印并退出 0。

用于「保持前台看消息」模式：不依赖 AutoX 通知监听，直接读屏。
退出码: 0=屏幕有变化(已打印当前文本) 1=超时无变化 2=链路故障
"""
import hashlib
import re
import subprocess
import sys
import time

SHZ = "/usr/local/bin/shz"
XML = "/sdcard/dsh-shared/_watch.xml"
LOCAL = "/home/dsh/shared/_watch.xml"
QQ = "com.tencent.mobileqq"


def shz(cmd, timeout=60):
    try:
        r = subprocess.run([SHZ, cmd], capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 3, "TIMEOUT"


def focus_qq():
    _, out = shz("dumpsys window 2>/dev/null | grep mCurrentFocus")
    if QQ in out:
        return True
    shz(f"am start -n {QQ}/.activity.SplashActivity >/dev/null 2>&1")
    time.sleep(1.4)
    _, out = shz("dumpsys window 2>/dev/null | grep mCurrentFocus")
    return QQ in out


def grab():
    if not focus_qq():
        return None
    for _ in range(3):
        shz(f"uiautomator dump {XML} >/dev/null 2>&1", timeout=60)
        try:
            x = open(LOCAL, encoding="utf-8").read()
        except Exception:
            x = ""
        if x:
            rows = []
            for m in re.finditer(r"<node[^>]*>", x):
                s = m.group(0)
                if QQ not in s:
                    continue
                t = re.search(r'text="([^"]*)"', s)
                b = re.search(r'bounds="\[(\d+),(\d+)\]', s)
                if t and t.group(1).strip() and b:
                    rows.append((int(b.group(2)), t.group(1).strip()))
            if rows:
                rows.sort()
                # 排除输入栏：发送键 ±130px 内是「输入框草稿」。
                # 用户正在打字时不该触发我（否则一直误报，还可能干扰输入）。
                send_y = next((y for y, t in rows if t.strip() == "发送"), None)
                if send_y is not None:
                    rows = [(y, t) for y, t in rows if abs(y - send_y) > 130]
                return rows
        time.sleep(1)
    return None


def sig(rows):
    return hashlib.sha1("\n".join(t for _, t in rows).encode()).hexdigest()[:16]


def main():
    every = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    minutes = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    base = grab()
    if base is None:
        print("LINK_DOWN 拿不到 QQ 屏幕")
        return 2
    b = sig(base)
    print(f"BASELINE {b}  ({len(base)} 节点)  {time.strftime('%H:%M:%S')}", flush=True)
    end = time.time() + minutes * 60
    while time.time() < end:
        time.sleep(every)
        rows = grab()
        if rows is None:
            print("LINK_DOWN 轮询中拿不到屏幕")
            return 2
        s = sig(rows)
        if s != b:
            print(f"CHANGED {b} -> {s}")
            for y, t in rows:
                print(f"  y={y:<5} {t[:90]}")
            return 0
    print("TIMEOUT_NO_CHANGE")
    return 1


if __name__ == "__main__":
    sys.exit(main())
