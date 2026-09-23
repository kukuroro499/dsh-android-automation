#!/bin/bash
# wx-send.sh — 微信发消息「单次 shz 往返」快速通道（ASCII + Unicode 双通道）
#
#   前提：微信已停留在目标聊天窗口（群聊/单聊）
#
#   成本规律（实测）：
#     1. 每次 shz 冷启动一个 rish(app_process)         ~650ms
#     2. 设备侧每次 input 也是一次 app_process 冷启动  ~250ms
#   => 优化重点是"合并调用"：整条链压进 1 次 shz；退格合并成 1 次 input。
#
#   两条文本注入通道：
#     ASCII  -> input text（不切输入法，最快，1 次往返）
#     Unicode-> ADBKeyboard 广播 ADB_INPUT_B64（中文/emoji/引号/换行全支持）
#               切换输入法前先记录原 IME，用完必须还原，否则用户没法打字
#
#   纵坐标有三种几何形态，必须区分，否则 tap 会打偏：
#     无键盘        y=2289
#     讯飞键盘弹起  y=1552
#     ADBKeyboard   y=2223（它自己的 "ADB Keyboard {ON}" 状态条把输入栏顶高约 66px）
#
# 用法：
#   wx-send.sh "消息内容"        # 直接发送
#   wx-send.sh -n "消息内容"     # 演练：只输入不发送，并自动清空
# 环境变量：WX_Y_DOWN / WX_Y_UP / WX_Y_ADB / WX_X_IN / WX_X_SEND
#
# 退出码：0 成功 / 9 未拿到微信输入连接（已中止，未发送）/ 1 参数错误
set -uo pipefail

DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run)  DRY=1; shift ;;
    -h|--help)     sed -n '2,25p' "$0"; exit 0 ;;
    --)            shift; break ;;
    -*)            echo "未知参数: $1" >&2; exit 1 ;;
    *)             break ;;
  esac
done

MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: wx-send.sh [-n] <消息>" >&2; exit 1; }

Y_DOWN=${WX_Y_DOWN:-2289}; Y_UP=${WX_Y_UP:-1552}; Y_ADB=${WX_Y_ADB:-2223}
X_IN=${WX_X_IN:-448};      X_SEND=${WX_X_SEND:-964}
ADB_IME=com.android.adbkeyboard/.AdbIME

if LC_ALL=C grep -q '[^ -~]' <<<"$MSG"; then UNI=1; else UNI=0; fi

# ---------- Unicode 通道 ----------
if [ "$UNI" = 1 ]; then
  ORIG_IME=$(shz 'settings get secure default_input_method' 2>/dev/null | tr -d '\r\n')
  if [ -z "$ORIG_IME" ]; then echo "取不到原始输入法，中止" >&2; exit 1; fi
  if [ "$ORIG_IME" = "$ADB_IME" ]; then ORIG_IME=com.iflytek.inputmethod.miui/.FlyIME; fi
  B64=$(python3 -c 'import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())' "$MSG")

  DEV=$(cat <<DEVEOF
restore() { ime set "$ORIG_IME" >/dev/null 2>&1; }
ime enable $ADB_IME >/dev/null 2>&1
ime set $ADB_IME >/dev/null 2>&1
sleep 1.0
input tap $X_IN $Y_ADB
sleep 0.5
D=\$(dumpsys input_method 2>/dev/null | grep 'mServedView=' | tail -1)
case "\$D" in
  *com.tencent.mm*) : ;;
  *) restore; echo "__WX_ABORT__ 未拿到微信输入连接(未发送): \$D"; exit 9 ;;
esac
am broadcast -a ADB_INPUT_B64 --es msg '$B64' >/dev/null 2>&1
sleep 0.7
if [ "$DRY" = 1 ]; then
  am broadcast -a ADB_CLEAR_TEXT >/dev/null 2>&1
  sleep 0.3
  restore; sleep 0.5
  screencap -p /sdcard/dsh-shared/_wxshot.png
  echo "__WX_DRYRUN__ Unicode: 已注入并清空，未发送 (ime 已还原为 $ORIG_IME)"
  exit 0
fi
input tap $X_SEND $Y_ADB
sleep 0.8
restore; sleep 0.5
screencap -p /sdcard/dsh-shared/_wxshot.png
echo "__WX_SENT__ Unicode，ime 已还原为 $ORIG_IME"
DEVEOF
)
  T0=$(date +%s%3N); OUT=$(shz "$DEV" 2>&1); RC=$?; T1=$(date +%s%3N)
  echo "$OUT"
  # 兜底：设备侧脚本异常退出时，IME 可能还停在 ADBKeyboard
  if [ $RC -ne 0 ]; then shz "ime set $ORIG_IME" >/dev/null 2>&1; fi
  echo "---- 总耗时 $((T1-T0)) ms（2 次 shz 往返：读 IME + 执行）----"

# ---------- ASCII 快通道 ----------
else
  ENC=${MSG// /%s}; ENC=${ENC//\'/}
  N=${#MSG}
  K=$(( N * 2 + 20 ))
  KEYS=$(printf '67 %.0s' $(seq 1 "$K") 2>/dev/null)

  DEV=$(cat <<DEVEOF
kb_y() { dumpsys input_method 2>/dev/null | grep -q 'mInputShown=true' && echo $Y_UP || echo $Y_DOWN; }
if ! dumpsys window 2>/dev/null | grep -q 'mCurrentFocus=.*com.tencent.mm'; then
  am start -n com.tencent.mm/.ui.LauncherUI >/dev/null 2>&1
  sleep 0.8
fi
Y1=\$(kb_y)
input tap $X_IN \$Y1
sleep 0.25
E=\$(input text '$ENC' 2>&1)
case "\$E" in
  *Exception*|*Error*) echo "__WX_ABORT__ 文本注入失败: \$E (未发送)"; exit 8 ;;
esac
sleep 0.35
Y2=\$(kb_y)
if [ "$DRY" = 1 ]; then
  input keyevent $KEYS
  sleep 0.25
  screencap -p /sdcard/dsh-shared/_wxshot.png
  echo "__WX_DRYRUN__ ASCII: 输入 $N 字符后清空，未发送 (y1=\$Y1 y2=\$Y2)"
  exit 0
fi
input tap $X_SEND \$Y2
sleep 0.65
screencap -p /sdcard/dsh-shared/_wxshot.png
echo "__WX_SENT__ ASCII y1=\$Y1 y2=\$Y2"
DEVEOF
)
  T0=$(date +%s%3N); OUT=$(shz "$DEV" 2>&1); RC=$?; T1=$(date +%s%3N)
  echo "$OUT"
  echo "---- 总耗时 $((T1-T0)) ms（1 次 shz 往返）----"
fi

[ -f /home/dsh/shared/_wxshot.png ] && cp -f /home/dsh/shared/_wxshot.png /home/dsh/shots/wx-last.png
exit $RC
