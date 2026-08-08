#!/usr/bin/env bash
# link2transcript 抽帧模块 — 本地视频文件 -> 均匀抽帧的 jpg + INDEX.md
#
#   frames.sh <视频文件> --out <目录> [--max-frames N] [--width 1024]
#                        [--start 秒|mm:ss] [--end 秒|mm:ss] [--offset 秒]
#
# 帧预算（规则形状参考 bradautomates/claude-video，帧数按本项目自己的口径压小）：
#   ≤30s → 10 帧 ；30s-3min → 20 帧 ；>3min → 30 帧（同样的帧数摊到更长时间＝自动稀疏）
#   硬上限：总数 ≤30 帧、平均 ≤2 帧/秒（--max-frames 也压不破）
# --offset：原片被裁过时用。帧文件名和 INDEX 里的时间戳会加上这个偏移，好对回原片时间轴。

set -euo pipefail

die() { echo "❌ $*" >&2; exit 1; }

VIDEO=""; OUT=""; MAXF=""; WIDTH=1024; START=0; END=""; OFFSET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --max-frames) MAXF="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --end) END="$2"; shift 2 ;;
    --offset) OFFSET="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) VIDEO="$1"; shift ;;
  esac
done

[[ -n "$VIDEO" && -f "$VIDEO" ]] || die "抽帧要一个存在的视频文件，收到：${VIDEO:-（空）}"
[[ -n "$OUT" ]] || die "抽帧要 --out 目录"
command -v ffmpeg  >/dev/null || die "缺 ffmpeg：brew install ffmpeg"
command -v ffprobe >/dev/null || die "缺 ffprobe（跟 ffmpeg 一起装）：brew install ffmpeg"

HASV="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_type \
        -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null || true)"
[[ "$HASV" == "video" ]] || die "「$(basename "$VIDEO")」里没有视频流，抽不了帧（纯音频文件用不上 --frames）"

DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null || true)"
[[ -n "$DUR" && "$DUR" != "N/A" ]] || \
  DUR="$(ffprobe -v error -select_streams v:0 -show_entries stream=duration \
         -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null || true)"
[[ -n "$DUR" && "$DUR" != "N/A" ]] || die "读不出视频时长，没法定帧预算"

# ── 排帧计划（时间点都在 python 里算，bash 不碰浮点）────────
ERRF="$(mktemp)"
trap 'rm -f "$ERRF"' EXIT
PLAN="$(python3 - "$DUR" "$START" "${END:-}" "${MAXF:-}" "$OFFSET" 2>"$ERRF" <<'PY'
import sys

HARD_CAP, FPS_CAP = 30, 2.0   # 硬上限：总数 ≤30 帧、平均 ≤2 帧/秒

def t(s):
    s = str(s).strip()
    if not s:
        return None
    if ":" in s:                       # hh:mm:ss / mm:ss
        v = 0.0
        for p in s.split(":"):
            v = v * 60 + float(p or 0)
        return v
    return float(s)

dur = t(sys.argv[1]) or 0.0
start = t(sys.argv[2]) or 0.0
end = t(sys.argv[3])
maxf = sys.argv[4].strip()
off = t(sys.argv[5]) or 0.0

if dur <= 0:
    sys.exit("视频时长为 0")
ws = max(0.0, min(start, dur))
we = dur if end is None else max(0.0, min(end, dur))
win = we - ws
if win <= 0:
    sys.exit(f"时间区间无效：{ws:.1f}s -> {we:.1f}s（原片只有 {dur:.1f}s）")

tier = 10 if win <= 30 else (20 if win <= 180 else 30)
n = int(maxf) if maxf else tier
n = min(n, HARD_CAP, max(1, int(win * FPS_CAP)))
n = max(n, 1)
step = win / n

def stamp(g, sep):
    h, m, s = int(g // 3600), int(g % 3600 // 60), int(g % 60)
    return (f"{h}h{m:02d}m{s:02d}s" if sep == "f" and h else
            f"{m:02d}m{s:02d}s" if sep == "f" else
            f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}")

if off:   # 原片被裁过，本地文件只是一段：一律按原片时间轴报，别拿裁出来的时长当原片时长
    desc = (f"抽帧区间 {stamp(ws+off,'d')}-{stamp(we+off,'d')}（原片时间轴；"
            f"本地只有裁出来的 {win:.0f}s）")
else:
    desc = f"原片时长 {dur:.0f}s ｜ 抽帧区间 {stamp(ws,'d')}-{stamp(we,'d')}"
print(f"HEAD\t{n}\t{tier}\t{step:.3f}\t{desc}")
for i in range(n):
    tl = ws + (i + 0.5) * step          # 取每格中点，躲开开头黑场/转场
    g = tl + off
    print(f"F\t{i+1:02d}\t{tl:.3f}\t{stamp(g,'f')}\t{stamp(g,'d')}")
PY
)" || die "抽帧没法排计划：$(cat "$ERRF")"

IFS=$'\t' read -r _ N TIER STEP DESC <<<"$(printf '%s\n' "$PLAN" | grep '^HEAD' | head -1)"

mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -name 'frame-*.jpg' -delete 2>/dev/null || true

printf '正在抽 %s 帧（%s，每 %.1fs 一帧，宽 %spx）…\n' "$N" "$DESC" "$STEP" "$WIDTH"
awk -v s="$STEP" 'BEGIN{ if (s+0 > 20) print "  ⚠️  帧间隔 " int(s) "s，画面会跳得很厉害——想看细节就用 --start/--end 圈小一点" }'

ROWS=""; OK=0
while IFS=$'\t' read -r tag idx tl label disp; do
  [[ "$tag" == "F" ]] || continue
  f="frame-${idx}_${label}.jpg"
  # 装进 min(WIDTH,iw) × min(1568,ih) 的盒子，保比例、绝不放大。
  # 高也得封顶：竖屏片只卡宽度会出 1024x1820 这种，读图前反正要被降采样，白传字节。
  if ffmpeg -nostdin -y -v error -ss "$tl" -i "$VIDEO" -frames:v 1 \
       -vf "scale=w='min(${WIDTH},iw)':h='min(1568,ih)':force_original_aspect_ratio=decrease:flags=lanczos" \
       -q:v 2 "$OUT/$f" 2>/dev/null \
     && [[ -s "$OUT/$f" ]]; then
    ROWS+="| $((10#$idx)) | \`$disp\` | $f |"$'\n'
    OK=$((OK+1))
  else
    echo "  （$disp 这一帧抽不出来，跳过）" >&2
  fi
done < <(printf '%s\n' "$PLAN")

[[ $OK -gt 0 ]] || die "一帧都没抽出来"

{
  echo "# 抽帧索引"
  echo
  printf '%s ｜ 共 %s 帧（档位 %s 帧，每 %.1fs 一帧）｜ 宽 %spx\n' \
    "$DESC" "$OK" "$TIER" "$STEP" "$WIDTH"
  echo
  echo "| 帧 | 原片时间 | 文件 |"
  echo "|---|---|---|"
  printf '%s' "$ROWS"
  echo
  echo "**读法**：按顺序用 Read 逐帧读图。画面里的文字、数字、命令、UI 一律以图为准，"
  echo "不要拿转录稿去猜；字卡视频里同一句话常连着几帧，归纳时自己去重。"
} > "$OUT/INDEX.md"

echo "  ✅ $OK 帧 -> $OUT/"
