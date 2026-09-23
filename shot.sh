#!/bin/bash
# shot.sh —— 设备截图并转 JPG（PNG 太肥：600KB~1.2MB → JPG 约 100-200KB）
# 用法: shot.sh [输出路径(不含扩展名)]   默认 /home/dsh/shots/shot
set -uo pipefail
OUT="${1:-/home/dsh/shots/shot}"
shz 'screencap -p /sdcard/dsh-shared/_shot.png' >/dev/null 2>&1
python3 - "$OUT" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open('/home/dsh/shared/_shot.png').convert('RGB')
except Exception as e:
    print("SHOT_FAIL", e); sys.exit(1)
p = sys.argv[1] + ".jpg"
im.save(p, "JPEG", quality=78, optimize=True)
import os
print(f"{p}  {im.size[0]}x{im.size[1]}  {os.path.getsize(p)//1024} KB")
PY
