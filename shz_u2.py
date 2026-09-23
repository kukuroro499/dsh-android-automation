#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 uiautomator2 接到 Shizuku(shz) 上 —— 全程不需要 adb。

原理
----
u2 的设备侧服务端是一个 jar，用 app_process 拉起后监听 TCP 端口。
官方客户端本该经 adb 端口转发访问它；但本容器与宿主**共享网络命名空间**
（容器直连 127.0.0.1:8099 的 Termux broker 已验证），
所以直接把 HTTP 连接换成普通 socket 连 127.0.0.1:PORT 即可。

需要替换的只有三处：
  1. AdbHTTPConnection.connect  -> 直连 socket（省掉 adb forward）
  2. adbutils.AdbDevice         -> ShzDevice 子类（shell/sync/push 走 shz）
  3. 确保设备侧 server 在跑
"""
import os
import shlex
import sys
import socket
import subprocess
import time
from pathlib import Path

import adbutils
import uiautomator2 as u2
import uiautomator2.core as core

SHZ = "/usr/local/bin/shz"
SHZ_PUSH = "/usr/local/bin/shz-push"
JAR_LOCAL = Path(u2.__file__).parent / "assets" / "u2.jar"
JAR_REMOTE = "/data/local/tmp/u2.jar"
DEFAULT_PORT = 9008


# ---------- 1. 设备 shim ----------

class _ShzSync:
    def push(self, local, remote, check=True, **_kw):
        r = subprocess.run([SHZ_PUSH, str(local), str(remote)],
                           capture_output=True, text=True, timeout=600)
        if check and r.returncode != 0:
            raise RuntimeError(f"shz-push 失败 rc={r.returncode}: {r.stdout}{r.stderr}")
        return r.stdout


class _MockProc:
    """冒充 adbutils 的 stream 进程对象（launch_uiautomator 的返回值）"""
    def __init__(self, out: str = ""):
        self.output = out.encode()

    def pool(self):
        return None          # None = 仍在运行

    def wait(self):
        return True

    def kill(self):
        pass


class ShzDevice(adbutils.AdbDevice):
    """只要满足 u2 用到的那几样：serial / shell / sync.push / create_connection"""

    def __init__(self, serial="shizuku-local"):
        self._shz_serial = serial
        self._shz_sync = _ShzSync()

    @property
    def serial(self):
        return self._shz_serial

    @property
    def sync(self):
        return self._shz_sync

    def shell(self, cmd, stream=False, timeout=120, **_kw):
        if isinstance(cmd, (list, tuple)):
            cmd = " ".join(shlex.quote(str(c)) for c in cmd)
        r = subprocess.run([SHZ, cmd], capture_output=True, text=True, timeout=timeout)
        out = r.stdout + r.stderr
        return _MockProc(out) if stream else out

    def create_connection(self, network=None, port=DEFAULT_PORT, timeout=10):
        # 共享网络命名空间 -> 直连，等价于 adb forward
        return socket.create_connection(("127.0.0.1", int(port)), timeout=timeout)


# ---------- 2. 把 HTTP 连接改成直连 ----------

def _direct_connect(self):
    port = self._AdbHTTPConnection__port          # 名称改写后的私有属性
    self.sock = socket.create_connection(("127.0.0.1", int(port)), timeout=10)


core.AdbHTTPConnection.connect = _direct_connect


# ---------- 3. 设备侧 server ----------

def ping(port=DEFAULT_PORT, timeout=3) -> bool:
    try:
        s = socket.create_connection(("127.0.0.1", int(port)), timeout=timeout)
        s.sendall(b"GET /ping HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        buf = b""
        while True:
            d = s.recv(4096)
            if not d:
                break
            buf += d
        s.close()
        return buf.rstrip().endswith(b"pong")
    except OSError:
        return False


def push_jar() -> bool:
    """把 u2.jar 送到设备（走 bind-mount 的 shared 目录，比 shz-push 快得多）"""
    local_md5 = subprocess.run(["md5sum", str(JAR_LOCAL)], capture_output=True, text=True).stdout.split()[0]
    remote = subprocess.run([SHZ, f"md5sum {JAR_REMOTE} 2>/dev/null || true"],
                            capture_output=True, text=True).stdout
    if local_md5 in remote:
        return True
    shared = "/home/dsh/shared/u2.jar"
    os.makedirs(os.path.dirname(shared), exist_ok=True)
    with open(JAR_LOCAL, "rb") as f, open(shared, "wb") as g:   # 容器写 shared 只能用 open()
        g.write(f.read())
    out = subprocess.run(
        [SHZ, f"cp /sdcard/dsh-shared/u2.jar {JAR_REMOTE} && chmod 644 {JAR_REMOTE} && md5sum {JAR_REMOTE}"],
        capture_output=True, text=True).stdout
    return local_md5 in out


def ensure_server(port=DEFAULT_PORT, wait=25) -> bool:
    """确保设备侧 server 在监听。用 setsid 脱离，避免随本进程退出而死。"""
    if ping(port):
        return True
    subprocess.Popen(
        [SHZ, f"CLASSPATH={JAR_REMOTE} app_process / com.wetest.uia2.Main -p {port}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + wait
    while time.time() < deadline:
        if ping(port):
            return True
        time.sleep(0.5)
    return False


def connect(port=DEFAULT_PORT, start=True):
    """返回一个可用的 uiautomator2 Device"""
    if start:
        if not push_jar():
            raise RuntimeError("u2.jar 推送/校验失败")
        if not ensure_server(port):
            raise RuntimeError(f"设备侧 server 未能在 127.0.0.1:{port} 就绪")
    return u2.Device(ShzDevice(), port=port)


# ---------- 4. 服务生命周期 ----------

def stop_server(port=DEFAULT_PORT) -> bool:
    """停掉设备侧 server（它是以 shell 身份跑的 app_process）"""
    subprocess.run([SHZ, f"pkill -f 'com.wetest.uia2.Main -p {port}' 2>/dev/null; true"],
                   capture_output=True, text=True, timeout=30)
    time.sleep(0.8)
    return not ping(port)


def status(port=DEFAULT_PORT) -> dict:
    jar_ok = False
    try:
        local_md5 = subprocess.run(["md5sum", str(JAR_LOCAL)], capture_output=True, text=True).stdout.split()[0]
        remote = subprocess.run([SHZ, f"md5sum {JAR_REMOTE} 2>/dev/null || true"],
                                capture_output=True, text=True, timeout=30).stdout
        jar_ok = local_md5 in remote
    except Exception:
        pass
    return {"port": port, "listening": ping(port), "jar_on_device": jar_ok}


# ---------- 5. CLI ----------

def _main(argv):
    import argparse
    import json
    ap = argparse.ArgumentParser(prog="shz_u2", description="uiautomator2 over Shizuku (无需 adb)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status"); sub.add_parser("start"); sub.add_parser("stop")
    sub.add_parser("info")
    p = sub.add_parser("dump"); p.add_argument("--out", default="-"); p.add_argument("--find", default=None)
    p = sub.add_parser("shot"); p.add_argument("out")
    p = sub.add_parser("click"); p.add_argument("x", type=int); p.add_argument("y", type=int)
    p = sub.add_parser("tap-id"); p.add_argument("resource_id")
    args = ap.parse_args(argv)

    if args.cmd == "status":
        print(json.dumps(status(), ensure_ascii=False, indent=2)); return 0
    if args.cmd == "start":
        print("jar 就绪" if push_jar() else "jar 失败")
        print("server 就绪" if ensure_server() else "server 未就绪"); return 0
    if args.cmd == "stop":
        print("已停止" if stop_server() else "停止失败"); return 0

    d = connect()
    if args.cmd == "info":
        i = d.info
        print(json.dumps({k: i.get(k) for k in ("currentPackageName","displayWidth","displayHeight","sdkInt")},
                         ensure_ascii=False, indent=2)); return 0
    if args.cmd == "dump":
        xml = d.dump_hierarchy()
        if args.find:
            import re
            for m in re.finditer(r"<node[^>]*>", xml):
                s = m.group(0)
                if args.find in s:
                    b = re.search(r'bounds="(\[[^"]*\])"', s)
                    t = re.search(r'text="([^"]*)"', s)
                    r = re.search(r'resource-id="([^"]*)"', s)
                    print(f"{b.group(1) if b else '?':<22} id={(r.group(1) if r else '').split('/')[-1]:<24} text={t.group(1) if t else ''!r}")
        elif args.out == "-":
            print(xml)
        else:
            open(args.out, "w", encoding="utf-8").write(xml); print(f"写入 {args.out}")
        return 0
    if args.cmd == "shot":
        d.screenshot(args.out); print(f"写入 {args.out}"); return 0
    if args.cmd == "click":
        d.click(args.x, args.y); print(f"click ({args.x},{args.y})"); return 0
    if args.cmd == "tap-id":
        el = d(resourceId=args.resource_id)
        if not el.exists:
            print(f"找不到 {args.resource_id}", file=sys.stderr); return 2
        el.click(); print(f"click {args.resource_id} @ {el.center()}"); return 0
    return 1


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
