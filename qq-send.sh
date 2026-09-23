#!/bin/bash
# qq-send.sh —— QQ 发消息（按颜色定位发送键，不依赖固定坐标）
#
#   为什么不用固定坐标：发送键的 y 随「软键盘有无」「输入框行数」变化，
#   实测同一个按钮在 2126 / 2152 / 2164 / 2282 都出现过。固定坐标必翻车。
#   改用颜色定位：QQ 发送键是浅蓝 (123,200,251)，实测中心与
#   uiautomator 给的 send_btn (940,2164) 几乎一致。
#
# 用法: qq-send.sh [-n] "消息"      (-n = 演练，只输入不发送)
set -uo pipefail
DRY=0
[ "${1:-}" = "-n" ] && { DRY=1; shift; }
MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: qq-send.sh [-n] <消息>" >&2; exit 1; }

# 链路守卫：Shizuku 掉线时 shz 会打印 Request timeout 但退出码仍为 0，
# 不检查就会出现"报告成功、实际什么都没做"的假成功。
if ! shz 'echo __LINK_OK__' 2>/dev/null | grep -q __LINK_OK__; then
  echo "__QQ_ABORT__ shz 链路不可用（Shizuku 掉线？）—— 未做任何操作" >&2; exit 3
fi

QQ=com.tencent.mobileqq
ADB_IME=com.android.adbkeyboard/.AdbIME
ORIG_IME=$(shz 'settings get secure default_input_method' 2>/dev/null | tr -d '\r\n')
[ "$ORIG_IME" = "$ADB_IME" ] && ORIG_IME=com.iflytek.inputmethod.miui/.FlyIME
B64=$(python3 -c 'import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())' "$MSG")
SHOT=/sdcard/dsh-shared/_qqshot.png

T0=$(date +%s%3N)
# ---- 阶段1：切输入法、把焦点弄到 QQ 输入框、注入文本 ----
OUT=$(shz "
ime enable $ADB_IME >/dev/null 2>&1
ime set $ADB_IME >/dev/null 2>&1
sleep 1.0
if ! dumpsys window 2>/dev/null | grep -q 'mCurrentFocus=.*$QQ'; then
  am start -n $QQ/.activity.SplashActivity >/dev/null 2>&1; sleep 1.5
fi
OK=''
for C in 2126 2164 2289 1552 2600; do
  input tap 427 \$C
  sleep 0.4
  D=\$(dumpsys input_method 2>/dev/null | grep 'mServedView=' | tail -1)
  case \"\$D\" in *$QQ*) OK=1; echo \"FOCUS_Y=\$C\"; break;; esac
done
if [ -z \"\$OK\" ]; then ime set $ORIG_IME >/dev/null 2>&1; echo '__QQ_ABORT__ 没拿到 QQ 输入连接'; exit 9; fi
am broadcast -a ADB_INPUT_B64 --es msg '$B64' >/dev/null 2>&1
sleep 0.9
screencap -p $SHOT
echo '__QQ_TYPED__'
" 2>&1)
RC=$?
echo "$OUT" | grep -v '^$'
if echo "$OUT" | grep -qE '__QQ_ABORT__|Request timeout|Server is not running'; then
  shz "ime set $ORIG_IME" >/dev/null 2>&1
  echo "已中止，未发送"; exit 9
fi
if ! echo "$OUT" | grep -q '__QQ_TYPED__'; then echo "阶段1 未完成，已中止"; exit 9; fi
cp -f /home/dsh/shared/_qqshot.png /home/dsh/shots/qq-typed.png

if [ "$DRY" = 1 ]; then
  shz "am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1; sleep 0.3; ime set $ORIG_IME >/dev/null 2>&1" >/dev/null 2>&1
  echo "__QQ_DRYRUN__ 已输入并清空，未发送（截图 shots/qq-typed.png）"
  exit 0
fi

# ---- 阶段2：按颜色找发送键并点击 ----
TAP=$(python3 - <<'PY'
from PIL import Image
im=Image.open("/home/dsh/shots/qq-typed.png").convert("RGB")
W,H=im.size
pts=[(x,y) for y in range(int(H*0.75),H,3) for x in range(int(W*0.55),W,3)
     if (lambda p: p[2]>200 and p[2]-p[0]>50 and p[1]>140)(im.getpixel((x,y)))]
if not pts: print("NONE")
else:
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    print(f"{sum(xs)//len(pts)} {sum(ys)//len(pts)} {len(pts)} {max(xs)-min(xs)} {max(ys)-min(ys)}")
PY
)
if [ "$TAP" = "NONE" ]; then
  shz "ime set $ORIG_IME" >/dev/null 2>&1
  echo "__QQ_ABORT__ 截图里没找到蓝色发送键（文本已留在输入框，请手动处理）"; exit 8
fi
read -r BX BY N BW BH <<<"$TAP"
echo "发送键: 中心=($BX,$BY) 命中 $N 点 尺寸 ${BW}x${BH}"
# 尺寸合理才点，避免误匹配聊天气泡
# 发送键实测约 192x111。宽或高任一超标，说明把别的蓝色元素（头像/气泡）也算进来了，
# 那样算出的几何中心会偏移，可能点空。宁可放弃也不瞎点。
if [ "$N" -lt 80 ] || [ "$BW" -gt 300 ] || [ "$BH" -gt 200 ]; then
  shz "ime set $ORIG_IME" >/dev/null 2>&1
  echo "__QQ_ABORT__ 蓝色块尺寸可疑 (${BW}x${BH}, $N 点，期望约 192x111)，不敢点"; exit 8
fi

shz "input tap $BX $BY; sleep 1.2; ime set $ORIG_IME >/dev/null 2>&1; sleep 0.6; screencap -p $SHOT" >/dev/null 2>&1
cp -f /home/dsh/shared/_qqshot.png /home/dsh/shots/qq-sent.png
T1=$(date +%s%3N)
echo "__QQ_SENT__ 已点发送 (${BX},${BY})，耗时 $((T1-T0)) ms —— 务必看 shots/qq-sent.png 确认"
