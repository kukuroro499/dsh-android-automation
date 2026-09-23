#!/bin/bash
# qq-read.sh —— 直接读出 QQ 当前会话的文本（绕过 DSH 面板遮挡）
#
# 原理：uiautomator dump 只导出「持有焦点」的那个窗口。
#       DSH 悬浮面板会抢焦点，那时 dump 出来全是面板自己的内容。
#       所以先强制把 QQ 拉到前台并确认它拿到焦点，再 dump，并按包名过滤。
#
# 用法: qq-read.sh [行数上限]
set -uo pipefail
LIMIT="${1:-40}"
XML=/sdcard/dsh-shared/_read.xml

OK=""
for i in 1 2 3 4; do
  shz 'am start -n com.tencent.mobileqq/.activity.SplashActivity >/dev/null 2>&1' >/dev/null 2>&1
  sleep 1.2
  F=$(shz 'dumpsys window 2>/dev/null | grep mCurrentFocus' 2>/dev/null | tr -d '\r')
  case "$F" in
    *com.tencent.mobileqq*) OK=1; break ;;
  esac
done
if [ -z "$OK" ]; then echo "__QQ_READ_ABORT__ QQ 拿不到焦点（面板在抢），当前: $F" >&2; exit 9; fi

shz "uiautomator dump $XML >/dev/null 2>&1" >/dev/null 2>&1
cp -f /home/dsh/shared/_read.xml /tmp/_read.xml 2>/dev/null
python3 - "$LIMIT" <<'PY'
import re, sys
limit = int(sys.argv[1])
try:
    x = open('/tmp/_read.xml', encoding='utf-8').read()
except Exception as e:
    print("读不到 dump:", e); sys.exit(1)
rows = []
for m in re.finditer(r'<node[^>]*>', x):
    s = m.group(0)
    p = re.search(r'package="([^"]*)"', s)
    if not p or p.group(1) != 'com.tencent.mobileqq':
        continue
    t = re.search(r'text="([^"]*)"', s)
    b = re.search(r'bounds="\[(\d+),(\d+)\]', s)
    if t and t.group(1).strip() and b:
        rows.append((int(b.group(2)), t.group(1).strip()))
rows.sort()
print(f"QQ 文本节点 {len(rows)} 条（按屏幕纵向）:")
for y, t in rows[-limit:]:
    print(f"  y={y:<5} {t[:90]}")
PY
