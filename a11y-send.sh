#!/bin/bash
# a11y-send.sh —— 通过常驻无障碍脚本(AutoX)发 QQ 消息
# 原理：写 a11y-cmd.txt → AutoX 用 setText()+click("发送") → 回写 a11y-result.txt
# 不需要 Shizuku / uiautomator / ADBKeyboard / 坐标点击。
# 用法: a11y-send.sh "消息"
# 退出码: 0=已发送  2=脚本无响应(可能被MIUI杀)  3=脚本报错
set -uo pipefail
MSG="${1:-}"
[ -n "$MSG" ] || { echo "用法: a11y-send.sh <消息>" >&2; exit 1; }
DIR=/home/dsh/shared
RES="$DIR/a11y-result.txt"
rm -f "$RES"
python3 -c "import json,sys;open('$DIR/a11y-cmd.txt','w',encoding='utf-8').write(json.dumps({'msg':sys.argv[1]},ensure_ascii=False))" "$MSG"
for _ in $(seq 1 24); do
  sleep 1.5
  if [ -f "$RES" ]; then
    OUT=$(cat "$RES")
    echo "$OUT"
    case "$OUT" in OK*) exit 0 ;; *) exit 3 ;; esac
  fi
done
echo "__A11Y_TIMEOUT__ 无障碍脚本没响应（可能被 MIUI 杀了，跑 a11y-ensure.sh）" >&2
exit 2
