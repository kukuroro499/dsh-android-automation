#!/bin/bash
# qq-fast.sh —— QQ 发送（快版）：不用 uiautomator dump，靠色彩定位 + 截图自校验
# 相比 qq-fire.sh 省掉两次 dump（各约 3.7s），实测 13~16s -> 目标 5~7s
# 用法: qq-fast.sh "消息"
# 退出码: 0=成功 3=链路断 8=定位/校验失败 9=注入失败
set -uo pipefail
MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: qq-fast.sh <消息>" >&2; exit 1; }
QQ=com.tencent.mobileqq
ADB_IME=com.android.adbkeyboard/.AdbIME
D=/sdcard/dsh-shared
L=/home/dsh/shared
T0=$(date +%s%3N)
shz 'echo __LINK_OK__' 2>/dev/null | grep -q __LINK_OK__ || { echo "__QQ_ABORT__ 链路断" >&2; exit 3; }
B64=$(python3 -c 'import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())' "$MSG")

# ---- 一次 shz 完成：切输入法 / 聚焦 / 注入 / 截图 ----
OUT=$(shz "
ime enable $ADB_IME >/dev/null 2>&1; ime set $ADB_IME >/dev/null 2>&1; sleep 0.5
dumpsys window 2>/dev/null | grep -q 'mCurrentFocus=.*$QQ' || { am start -n $QQ/.activity.SplashActivity >/dev/null 2>&1; sleep 1.6; }
input tap 300 2080; sleep 0.25; input tap 300 2130; sleep 0.45
am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1; sleep 0.25
am broadcast -a ADB_INPUT_B64 --es msg '$B64' >/dev/null 2>&1; sleep 0.8
screencap -p $D/_f1.png
echo __TYPED__
" 2>&1)
echo "$OUT" | grep -v '^$'
case "$OUT" in *__TYPED__*) : ;; *) echo "__QQ_ABORT__ 注入阶段失败" >&2; exit 9 ;; esac

# ---- 色彩找发送键（蓝色实心块）----
R=$(python3 - <<'PY'
from PIL import Image
try: im = Image.open('/home/dsh/shared/_f1.png').convert("RGB")
except Exception: print("0 0 0 0 0"); raise SystemExit
W,H = im.size
pts=[]
for y in range(1950, min(H,2300), 2):
    for x in range(780, W, 2):
        p = im.getpixel((x,y))
        if p[2]>200 and p[2]-p[0]>50 and p[1]>140: pts.append((x,y))
if not pts: print("0 0 0 0 0")
else:
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    print(sum(xs)//len(xs), sum(ys)//len(ys), len(pts), max(xs)-min(xs), max(ys)-min(ys))
PY
)
read -r BX BY N BW BH <<<"$R"
echo "发送键: ($BX,$BY) $N 点 ${BW}x${BH}"
if [ "$N" -lt 800 ] || [ "$BW" -gt 300 ] || [ "$BH" -gt 200 ]; then
  echo "__QQ_ABORT__ 蓝块不可信（可能没打进字），草稿留在输入框" >&2; exit 8
fi

# ---- 点击 + 用无障碍文件校验（比截图判色快且准）----
shz "input tap $BX $BY; sleep 0.9" >/dev/null 2>&1
KEY=$(printf '%s' "$MSG" | cut -c1-8)
SENT=0
for _ in 1 2 3 4 5 6 7 8; do
  sleep 0.5
  if grep -qF "$KEY" /home/dsh/shared/a11y-qq.txt 2>/dev/null; then SENT=1; break; fi
done
T1=$(date +%s%3N)
if [ "$SENT" = 1 ]; then
  echo "__QQ_SENT__ ($BX,$BY) 耗时 $((T1-T0)) ms"
  exit 0
fi
echo "__QQ_UNVERIFIED__ 无障碍文件里没看到这条，请人工看屏幕（勿重复发）" >&2
exit 8
