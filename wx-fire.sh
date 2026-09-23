#!/bin/bash
# wx-fire.sh —— 微信发送（全程 ADBKeyboard，绿色发送键定位，不弹讯飞键盘）
#
# 微信与 QQ 的关键差异：
#   微信不向无障碍/uiautomator 暴露任何节点（uiautomator dump 只有 1 个空节点），
#   所以发送键只能用【颜色】定位：微信发送键是绿色，实测中心 (983,2225)，约 132x84。
#   输入框实测 x132-843 y2230-2330，中心 (300,2280)。
#
# 用法: wx-fire.sh [-n] "消息"    (-n = 只注入不发送，随后清空)
# 退出码: 0=成功  3=链路断  8=定位失败  9=注入失败
set -uo pipefail
DRY=0
[ "${1:-}" = "-n" ] && { DRY=1; shift; }
MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: wx-fire.sh [-n] <消息>" >&2; exit 1; }

WX=com.tencent.mm
ADB_IME=com.android.adbkeyboard/.AdbIME
SHOT=/sdcard/dsh-shared/_wxshot.png
LOCAL=/home/dsh/shared/_wxshot.png
IX=300; IY=2280
T0=$(date +%s%3N)

shz 'echo __LINK_OK__' 2>/dev/null | grep -q __LINK_OK__ || {
  echo "__WX_ABORT__ shz 链路不可用" >&2; exit 3; }

B64=$(python3 -c 'import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())' "$MSG")

OUT=$(shz "
ime enable $ADB_IME >/dev/null 2>&1
ime set $ADB_IME >/dev/null 2>&1
sleep 0.8
if ! dumpsys window 2>/dev/null | grep -q 'mCurrentFocus=.*$WX'; then
  am start -n $WX/.ui.LauncherUI >/dev/null 2>&1; sleep 2.0
fi
input tap $IX $IY
sleep 0.8
am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1
sleep 0.4
am broadcast -a ADB_INPUT_B64 --es msg '$B64' >/dev/null 2>&1
sleep 1.2
screencap -p $SHOT
echo '__WX_TYPED__'
" 2>&1)
echo "$OUT" | grep -v '^$'
case "$OUT" in *__WX_TYPED__*) : ;; *) echo "__WX_ABORT__ 注入阶段失败" >&2; exit 9 ;; esac

cp -f "$LOCAL" /home/dsh/shots/wx-typed.png 2>/dev/null

# 阶段2：定位绿色发送键
read -r BX BY N BW BH < <(python3 - <<'PY'
from PIL import Image
try:
    im = Image.open("/home/dsh/shots/wx-typed.png").convert("RGB")
except Exception:
    print("0 0 0 0 0"); raise SystemExit
W, H = im.size
pts = []
for y in range(2150, min(H, 2380), 2):
    for x in range(700, W, 2):
        r, g, b = im.getpixel((x, y))
        if g > 130 and g - r > 40 and g - b > 40:
            pts.append((x, y))
if not pts:
    print("0 0 0 0 0")
else:
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    print(sum(xs)//len(xs), sum(ys)//len(ys), len(pts), max(xs)-min(xs), max(ys)-min(ys))
PY
)
echo "发送键: 中心=($BX,$BY) 命中 $N 点 尺寸 ${BW}x${BH}"
if [ "$N" -lt 300 ] || [ "$BW" -gt 400 ] || [ "$BH" -gt 300 ]; then
  echo "__WX_ABORT__ 绿色块不可信 (${BW}x${BH}, $N 点)，不敢点" >&2; exit 8
fi
if [ "$DRY" = 1 ]; then
  shz 'am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1' >/dev/null 2>&1
  echo "__WX_DRYRUN__ 已定位未点击（草稿已清空）"; exit 0
fi

shz "input tap $BX $BY; sleep 1.3; screencap -p $SHOT" >/dev/null 2>&1
cp -f "$LOCAL" /home/dsh/shots/wx-sent.png 2>/dev/null
GREEN_AFTER=$(python3 - <<'PYV'
from PIL import Image
try:
    im = Image.open("/home/dsh/shots/wx-sent.png").convert("RGB")
except Exception:
    print(-1); raise SystemExit
W, H = im.size
n = 0
for y in range(2150, min(H, 2380), 2):
    for x in range(700, W, 2):
        r, g, b = im.getpixel((x, y))
        if g > 130 and g - r > 40 and g - b > 40:
            n += 1
print(n)
PYV
)
T1=$(date +%s%3N)
echo "发送后绿色像素: $GREEN_AFTER  (归零=发送键已变回 +，即已发出)"
if [ "$GREEN_AFTER" -ge 0 ] && [ "$GREEN_AFTER" -lt 300 ]; then
  echo "__WX_SENT__ 已点发送 ($BX,$BY)，耗时 $((T1-T0)) ms —— 看图确认 shots/wx-sent.png"
  exit 0
fi
echo "__WX_UNVERIFIED__ 绿色发送键仍在，草稿可能没发出去，请人工确认（勿重复发送）" >&2
exit 8
