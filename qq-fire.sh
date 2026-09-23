#!/bin/bash
# qq-fire.sh —— QQ 发送（全程 ADBKeyboard，不切回讯飞；发送键用 uiautomator 精确定位）
#
# 为什么不复用 qq-send.sh（本脚本不修改它）：
#   qq-send.sh 收尾会把输入法切回讯飞 → 键盘弹起 → 输入栏整体上移约 890px，
#   它的颜色定位随即失效（实测包围盒被撑到 429x318 / 198x351 而拒绝点击）。
#   本脚本全程停在 ADBKeyboard：没有键盘弹起，布局稳定（发送键恒在 y≈2112），
#   再用 uiautomator 直接读发送键的真实 bounds，不依赖颜色。
#
# 用法: qq-fire.sh [-n] "消息"      (-n = 只注入并定位，不点击，随后清空草稿)
# 退出码: 0=成功  3=链路断  8=定位/注入失败  9=没拿到输入连接
set -uo pipefail
DRY=0
[ "${1:-}" = "-n" ] && { DRY=1; shift; }
MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: qq-fire.sh [-n] <消息>" >&2; exit 1; }

QQ=com.tencent.mobileqq
ADB_IME=com.android.adbkeyboard/.AdbIME
XML=/sdcard/dsh-shared/_fire.xml
LOCAL=/home/dsh/shared/_fire.xml
T0=$(date +%s%3N)

shz 'echo __LINK_OK__' 2>/dev/null | grep -q __LINK_OK__ || {
  echo "__FIRE_ABORT__ shz 链路不可用" >&2; exit 3; }

B64=$(python3 -c 'import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())' "$MSG")

# ---------- 阶段1：ADBKeyboard 常驻 + 注入 ----------
OUT=$(shz "
ime enable $ADB_IME >/dev/null 2>&1
ime set $ADB_IME >/dev/null 2>&1
sleep 0.8
if ! dumpsys window 2>/dev/null | grep -q 'mCurrentFocus=.*$QQ'; then
  am start -n $QQ/.activity.SplashActivity >/dev/null 2>&1; sleep 1.4
fi
OK=''
for C in 2126 2164 2289 1552 2600; do
  input tap 427 \$C
  sleep 0.35
  D=\$(dumpsys input_method 2>/dev/null | grep 'mServedView=' | tail -1)
  case \"\$D\" in *$QQ*) OK=1; echo \"FOCUS_Y=\$C\"; break;; esac
done
[ -n \"\$OK\" ] || { echo '__FIRE_ABORT__ 没拿到 QQ 输入连接'; exit 9; }
am broadcast -a ADB_INPUT_B64 --es msg '$B64' >/dev/null 2>&1
sleep 0.9
echo '__FIRE_TYPED__'
" 2>&1)
echo "$OUT" | grep -v '^$'
case "$OUT" in *__FIRE_ABORT__*) exit 9 ;; esac
case "$OUT" in *__FIRE_TYPED__*) : ;; *) echo "__FIRE_ABORT__ 注入失败" >&2; exit 8 ;; esac

# ---------- 阶段2：uiautomator 精确定位 ----------
rm -f "$LOCAL"
shz "uiautomator dump $XML >/dev/null 2>&1" >/dev/null 2>&1
LOC=$(python3 - "$MSG" <<'PY'
import re, sys
msg = sys.argv[1]
try:
    x = open('/home/dsh/shared/_fire.xml', encoding='utf-8').read()
except Exception:
    print("DRAFT|"); print("SEND|"); raise SystemExit
draft = send = None
for m in re.finditer(r'<node[^>]*>', x):
    s = m.group(0)
    if 'com.tencent.mobileqq' not in s:
        continue
    t = re.search(r'text="([^"]*)"', s)
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', s)
    if not (t and b):
        continue
    txt = t.group(1).strip()
    x1, y1, x2, y2 = map(int, b.groups())
    if txt == "发送" and 60 <= x2 - x1 <= 300 and 60 <= y2 - y1 <= 200:
        send = f"{(x1+x2)//2} {(y1+y2)//2}"
    if msg[:6] in txt:
        draft = txt[:36]
print(f"DRAFT|{draft or ''}")
print(f"SEND|{send or ''}")
PY
)
DRAFT=$(echo "$LOC" | sed -n 's/^DRAFT|//p')
SEND=$(echo "$LOC" | sed -n 's/^SEND|//p')
echo "草稿: ${DRAFT:-无}"
echo "发送键: ${SEND:-未找到}"

# 关键安全闸：输入框里没有草稿就绝不点击（防空发/误发）
[ -n "$DRAFT" ] || { echo "__FIRE_ABORT__ 输入框没有草稿，不点击" >&2; exit 8; }

if [ "$DRY" = 1 ]; then
  shz 'am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1' >/dev/null 2>&1
  echo "__FIRE_DRYRUN__ 已注入并定位，未点击（草稿已清空）"
  exit 0
fi
[ -n "$SEND" ] || { echo "__FIRE_ABORT__ 没找到发送键" >&2; exit 8; }

# ---------- 阶段3：点击 + 自校验 ----------
set -- $SEND
shz "input tap $1 $2; sleep 1.4" >/dev/null 2>&1
rm -f "$LOCAL"
shz "uiautomator dump $XML >/dev/null 2>&1" >/dev/null 2>&1
VER=$(python3 - "$MSG" <<'PY'
import re, sys
msg = sys.argv[1]
try:
    x = open('/home/dsh/shared/_fire.xml', encoding='utf-8').read()
except Exception:
    print("DRAFT_LEFT|?  IN_CHAT|?"); raise SystemExit
rows = []
for m in re.finditer(r'<node[^>]*>', x):
    s = m.group(0)
    if 'com.tencent.mobileqq' not in s:
        continue
    t = re.search(r'text="([^"]*)"', s)
    b = re.search(r'bounds="\[(\d+),(\d+)\]', s)
    if t and t.group(1).strip() and b:
        rows.append((int(b.group(2)), t.group(1).strip()))
rows.sort()
send_y = next((y for y, t in rows if t.strip() == "发送"), 9999)
key = msg[:6]
draft = any(key in t and abs(y - send_y) <= 140 for y, t in rows)
chat = any(key in t and y < send_y - 140 for y, t in rows)
print(f"DRAFT_LEFT|{'1' if draft else '0'}  IN_CHAT|{'1' if chat else '0'}")
PY
)
T1=$(date +%s%3N)
echo "$VER"
case "$VER" in *"DRAFT_LEFT|0"*"IN_CHAT|1"*) echo "__FIRE_SENT__ 已发送并验证 ($1,$2)，耗时 $((T1-T0)) ms"; exit 0 ;; esac
echo "__FIRE_UNVERIFIED__ 点了但没验证到，请人工看屏幕（可能已发出，勿重复发送）" >&2
exit 8
