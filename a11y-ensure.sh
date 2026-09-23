#!/bin/bash
# a11y-ensure.sh —— 无障碍脚本看门狗：心跳过期就重启 AutoX 脚本
# 心跳 a11y.hb 由脚本每 800ms 覆写；>90s 未更新即判定死亡。
set -uo pipefail
DIR=/home/dsh/shared
HB="$DIR/a11y.hb"
SVC=org.autojs.autoxjs.v6/com.stardust.autojs.core.accessibility.AccessibilityService
INTENT="am start -n org.autojs.autoxjs.v6/org.autojs.autojs.external.open.RunIntentActivity -a android.intent.action.VIEW -d file:///sdcard/dsh-shared/dsh-a11y.js -t text/javascript"
STALE=90

hb=$(cat "$HB" 2>/dev/null || echo 0)
case "$hb" in ''|*[!0-9]*) hb=0 ;; esac
now=$(date +%s)
age=$(( now - hb / 1000 ))
if [ "$age" -le "$STALE" ]; then
  echo "ALIVE age=${age}s"; exit 0
fi
echo "DEAD age=${age}s -> 重启"
# 无障碍服务可能被一起干掉，先确保绑定
shz "settings put secure enabled_accessibility_services $SVC; settings put secure accessibility_enabled 1" >/dev/null 2>&1
shz "$INTENT" >/dev/null 2>&1
sleep 6
hb2=$(cat "$HB" 2>/dev/null || echo 0)
case "$hb2" in ''|*[!0-9]*) hb2=0 ;; esac
now2=$(date +%s)
age2=$(( now2 - hb2 / 1000 ))
if [ "$age2" -le "$STALE" ]; then echo "RESTARTED age=${age2}s"; exit 0; fi
echo "RESTART_FAILED age=${age2}s" >&2; exit 2
