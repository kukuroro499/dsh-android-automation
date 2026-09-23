#!/bin/bash
# qq-group-watch.sh —— 盯无障碍通道里的 QQ 当前群；底部内容一变就退出并打印
# 签名 = 第 1 行(群名) + 末尾 3 行(最新消息)，所以换群也会触发。
# 每 10 轮检查一次前台，QQ 被 DSH 面板挤掉就重新拉回（保证无障碍能读到）。
# 用法: qq-group-watch.sh [轮询秒] [最长分钟]
set -uo pipefail
EVERY="${1:-3}"
MIN="${2:-40}"
DIR=/home/dsh/shared
F="$DIR/a11y-qq.txt"
QQ=com.tencent.mobileqq

[ -x /home/dsh/a11y-ensure.sh ] && /home/dsh/a11y-ensure.sh >/dev/null 2>&1
for _ in $(seq 1 10); do [ -f "$F" ] && break; sleep 1; done
[ -f "$F" ] || { echo "LINK_DOWN a11y-qq.txt 不存在"; exit 2; }

sig() { { head -1 "$F" 2>/dev/null; tail -3 "$F" 2>/dev/null; } | md5sum | cut -d' ' -f1; }
keep_front() {
  local f
  f=$(shz 'dumpsys window 2>/dev/null | grep -m1 mCurrentFocus' 2>/dev/null)
  case "$f" in *"$QQ"*) return 0 ;; esac
  shz 'input keyevent KEYCODE_HOME; sleep 1.2; am start -n com.tencent.mobileqq/.activity.SplashActivity >/dev/null 2>&1' >/dev/null 2>&1
}

BASE=$(sig)
echo "BASELINE $BASE  $(date +%H:%M:%S)"
echo "群: $(head -1 "$F" | sed 's/.*|\(.*\)|.*/\1/')"
CNT=$(( MIN * 60 / EVERY ))
for i in $(seq 1 "$CNT"); do
  sleep "$EVERY"
  if [ $(( i % 10 )) -eq 0 ]; then keep_front; fi
  if [ $(( i % 40 )) -eq 0 ]; then /home/dsh/a11y-ensure.sh >/dev/null 2>&1; fi
  [ -f "$F" ] || { echo "LINK_DOWN 文件消失"; exit 2; }
  CUR=$(sig)
  if [ "$CUR" != "$BASE" ]; then
    echo "CHANGED $BASE -> $CUR"
    cat "$F"
    exit 0
  fi
done
echo "TIMEOUT_NO_CHANGE"
exit 1
