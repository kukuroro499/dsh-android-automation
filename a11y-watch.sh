#!/bin/bash
# a11y-watch.sh —— 盯无障碍通道的 QQ 文本；末尾内容一变就打印并退出 0
# 比 qq-watch.py 快得多：直接读 bind-mount 文件，不做 uiautomator dump。
# 签名只取【末尾 12 行】：新消息总出现在底部，这样滚动不会误触发。
# 用法: a11y-watch.sh [轮询秒数] [最长分钟]
set -uo pipefail
EVERY="${1:-3}"
MIN="${2:-40}"
DIR=/home/dsh/shared
F="$DIR/a11y-qq.txt"
TAILN=3
[ -x /home/dsh/a11y-ensure.sh ] && /home/dsh/a11y-ensure.sh >/dev/null 2>&1

for _ in $(seq 1 10); do [ -f "$F" ] && break; sleep 1; done
[ -f "$F" ] || { echo "LINK_DOWN a11y-qq.txt 不存在"; exit 2; }

sig() { tail -n "$TAILN" "$1" 2>/dev/null | md5sum | cut -d' ' -f1; }

BASE=$(sig "$F")
echo "BASELINE $BASE  $(date +%H:%M:%S)  (末尾 $TAILN 行)"
CNT=$(( MIN * 60 / EVERY ))
for i in $(seq 1 "$CNT"); do
  sleep "$EVERY"
  if [ $(( i % 40 )) -eq 0 ]; then /home/dsh/a11y-ensure.sh >/dev/null 2>&1; fi
  [ -f "$F" ] || { echo "LINK_DOWN 文件消失"; exit 2; }
  CUR=$(sig "$F")
  if [ "$CUR" != "$BASE" ]; then
    echo "CHANGED $BASE -> $CUR"
    cat "$F"
    exit 0
  fi
done
echo "TIMEOUT_NO_CHANGE"
exit 1
