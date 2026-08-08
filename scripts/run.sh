#!/usr/bin/env bash
# link2transcript（顺风耳）— 任何视频/音频链接或本地文件 -> 干净文字稿
#
#   run.sh <URL|文件> [--lang zh|en|auto] [--out 目录] [--keep-media] [--force-asr]
#                         [--frames] [--max-frames N] [--frame-width 1024]
#                         [--start mm:ss] [--end mm:ss]
#                         [--hint "领域词"] [--terms 词表] [--no-terms]
#
# 两条路：
#   快路 — 平台自带字幕（YouTube/B站常有），秒取，不动 GPU
#   慢路 — yt-dlp 扒音轨 -> whisper.cpp 转录（M 芯片约实时 20-60 倍速）
# 两条路都收敛成 SRT，再由 srt2text.py 统一转成可读稿。
#
# --frames（默认关，开了才下原片）：额外抽帧到 <输出目录>/frames/，给 AI 用 Read 看画面。
#   纯字卡/无口播/关键信息只在画面里的视频，只靠转录一个字都拿不到，得靠这个。
#
# 专有名词两道闸（whisper 把人名/术语听错是常态）：
#   --hint  转录时给 whisper 喂领域词（事前偏向），只对慢路有用，务必短
#   --terms 出稿前按 `错=>对` 词表纠错（事后擦），改了哪些词会原样打出来

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YTDLP="$(command -v yt-dlp || echo "$HOME/.local/bin/yt-dlp")"
# TikTok 会认出 yt-dlp 的默认身份，发一个不含视频数据的空壳页（报 "Unable to extract
# universal data for rehydration"）。换成浏览器 UA 即可拿到正常页面——2026-08-08 实测。
UA="${TRANSCRIPT_UA:-Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36}"
YTA=(--user-agent "$UA")
MODEL="${WHISPER_MODEL:-$HOME/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin}"

INPUT=""; LANG_OPT="auto"; OUTDIR=""; KEEP=0; FORCE_ASR=0; HEAD=0
FRAMES=0; MAXF=""; FWIDTH=1024; START=""; END=""
HINT=""; NO_TERMS=0; TERMS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG_OPT="$2"; shift 2 ;;
    --out) OUTDIR="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --keep-media) KEEP=1; shift ;;
    --force-asr) FORCE_ASR=1; shift ;;
    --frames|--with-frames) FRAMES=1; shift ;;
    --max-frames) FRAMES=1; MAXF="$2"; shift 2 ;;
    --frame-width) FRAMES=1; FWIDTH="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --end) END="$2"; shift 2 ;;
    --hint) HINT="$2"; shift 2 ;;
    --terms) TERMS+=("$2"); shift 2 ;;
    --no-terms) NO_TERMS=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) INPUT="$1"; shift ;;
  esac
done
[[ -n "$INPUT" ]] || { echo "用法: run.sh <URL|文件> [--lang zh|en|auto] [--out 目录] [--frames]" >&2; exit 1; }
# --start/--end 只圈抽帧区间；没开 --frames 就是空转，宁可吵一声也别让用户以为生效了
if [[ $FRAMES -eq 0 && -n "${START}${END}" ]]; then
  echo "⚠️  --start/--end 只管抽帧区间，没开 --frames 时不起作用（只想截转录用 --head N）" >&2
fi

die() { echo "❌ $*" >&2; exit 1; }

# ── 词表：默认表（中文任务）+ --terms 追加 ────────────────
# --terms 可以给路径，也可以给 terms/ 下的短名（--terms medical → terms/medical.txt）
TERMS_DIR="$HERE/../terms"
TERM_FILES=()
if [[ $NO_TERMS -eq 0 && -f "$TERMS_DIR/default-zh.txt" ]] \
   && [[ "$LANG_OPT" == "zh" || "$LANG_OPT" == "auto" ]]; then
  TERM_FILES+=("$TERMS_DIR/default-zh.txt")
fi
for t in ${TERMS[@]+"${TERMS[@]}"}; do
  if [[ -f "$t" ]]; then TERM_FILES+=("$t")
  elif [[ -f "$TERMS_DIR/$t.txt" ]]; then TERM_FILES+=("$TERMS_DIR/$t.txt")
  else die "词表找不到：$t（也不在 $TERMS_DIR/$t.txt）"; fi
done

command -v ffmpeg >/dev/null || die "缺 ffmpeg：brew install ffmpeg"
command -v whisper-cli >/dev/null || die "缺 whisper-cli：brew install whisper-cpp"
[[ -f "$MODEL" ]] || die "缺模型 $MODEL
下载：curl -L --create-dirs -o '$MODEL' https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$(basename "$MODEL")"

IS_URL=0
[[ "$INPUT" =~ ^https?:// ]] && IS_URL=1
if [[ $IS_URL -eq 1 ]]; then
  [[ -x "$YTDLP" ]] || die "缺 yt-dlp：uv tool install yt-dlp"
else
  [[ -f "$INPUT" ]] || die "文件不存在：$INPUT"
fi

# ── 输出目录 ──────────────────────────────────────────────
if [[ -z "$OUTDIR" ]]; then
  SLUG="$(date +%m%d-%H%M%S)"
  OUTDIR="${TRANSCRIPT_HOME:-$HOME/transcripts}/$SLUG"
fi
mkdir -p "$OUTDIR"
SRT="$OUTDIR/transcript.srt"

# ── 元数据（链接才有）─────────────────────────────────────
TITLE=""
if [[ $IS_URL -eq 1 ]]; then
  echo "[1/4] 读元数据…"
  if "$YTDLP" "${YTA[@]}" -J --no-warnings --skip-download "$INPUT" > "$OUTDIR/meta.json" 2>"$OUTDIR/.meta.err"; then
    python3 - "$OUTDIR/meta.json" "$OUTDIR/info.md" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
def g(k, default="—"):
    v = d.get(k)
    return default if v in (None, "") else v
dur = d.get("duration")
rows = [
    ("标题", g("title")), ("作者", g("uploader") or g("channel")),
    ("平台", g("extractor_key")), ("时长", f"{int(dur//60)}:{int(dur%60):02d}" if dur else "—"),
    ("发布", g("upload_date")), ("播放", g("view_count")),
    ("点赞", g("like_count")), ("评论", g("comment_count")),
    ("链接", g("webpage_url")),
]
md = "\n".join(f"- **{k}**：{v}" for k, v in rows)
desc = (d.get("description") or "").strip()
if desc:
    md += "\n\n## 原文案 / 简介\n\n" + desc
open(sys.argv[2], "w", encoding="utf-8").write(md + "\n")
print(g("title"))
PY
    TITLE="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8')).get('title') or '')" "$OUTDIR/meta.json")"
  else
    echo "  （元数据读不到，继续）"
  fi
fi

# ── 快路：平台自带字幕 ────────────────────────────────────
GOT_SUB=0
if [[ $IS_URL -eq 1 && $FORCE_ASR -eq 0 ]]; then
  echo "[2/4] 找平台自带字幕…"
  case "$LANG_OPT" in
    zh) SUBLANGS="zh,zh-Hans,zh-CN,zh-Hant,zh-TW" ;;
    en) SUBLANGS="en,en-US,en-GB,en-orig" ;;
    *)  SUBLANGS="zh,zh-Hans,zh-CN,en,en-US,en-orig" ;;
  esac
  "$YTDLP" "${YTA[@]}" --no-warnings --skip-download --write-subs --write-auto-subs \
    --sub-langs "$SUBLANGS" --convert-subs srt \
    -o "$OUTDIR/sub.%(ext)s" "$INPUT" >/dev/null 2>&1 || true
  FOUND="$(find "$OUTDIR" -maxdepth 1 -name 'sub*.srt' | head -1)"
  if [[ -n "$FOUND" ]]; then
    mv "$FOUND" "$SRT"; find "$OUTDIR" -maxdepth 1 -name 'sub*.srt' -delete
    GOT_SUB=1
    echo "  ✅ 拿到自带字幕，跳过转录"
    # --hint 是喂给 whisper 的，走快路根本没跑 whisper，说清楚免得以为生效了
    [[ -n "$HINT" ]] && echo "  ⚠️  用的是平台自带字幕，--hint 这趟没参与（它只作用于 whisper 转录）。想让它生效加 --force-asr"
  else
    echo "  没有，走转录"
  fi
fi

# ── 抽帧（--frames，默认关）：下原片 -> 均匀抽帧到 frames/ ─
# 放在 whisper 前面：转录再怎么炸，帧也已经落盘了。
VIDEO=""; FSTART="${START:-0}"; FEND="${END:-}"; FOFF=0
if [[ $FRAMES -eq 1 ]]; then
  if [[ $IS_URL -eq 1 ]]; then
    CUT=0
    VSEC=()
    # 只在 start/end 都给了的情况下让 yt-dlp 裁着下（省带宽），单给一头就下全片本地再切
    if [[ -n "$START" && -n "$END" ]]; then
      CUT=1; VSEC=(--download-sections "*${START}-${END}")
    fi
    echo "[帧 1/2] 下原片（要看画面，音轨不够用）…"
    "$YTDLP" "${YTA[@]}" --no-warnings -f "bv*+ba/b" --merge-output-format mp4 \
      "${VSEC[@]+"${VSEC[@]}"}" -o "$OUTDIR/video.%(ext)s" "$INPUT" >/dev/null 2>&1 \
    || "$YTDLP" "${YTA[@]}" --no-warnings "${VSEC[@]+"${VSEC[@]}"}" \
      -o "$OUTDIR/video.%(ext)s" "$INPUT" >/dev/null \
    || die "原片下不下来（可能需要登录，或该站点不给视频流）"
    VIDEO="$(find "$OUTDIR" -maxdepth 1 -name 'video.*' ! -name '*.part' | head -1)"
    [[ -n "$VIDEO" ]] || die "原片下下来了但找不到落盘文件"

    if [[ $CUT -eq 1 ]]; then
      # yt-dlp 不是每个站点都吃 --download-sections，得实测本地文件到底是一段还是全片
      read -r FSTART FEND FOFF <<<"$(python3 - "$VIDEO" "$START" "$END" <<'PY'
import subprocess, sys
def t(s):
    s = str(s).strip()
    if ":" in s:
        v = 0.0
        for p in s.split(":"):
            v = v * 60 + float(p or 0)
        return v
    return float(s or 0)
vid, st, en = sys.argv[1], t(sys.argv[2]), t(sys.argv[3])
out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=nw=1:nk=1", vid], capture_output=True, text=True).stdout.strip()
ld = float(out or 0)
if ld and abs(ld - (en - st)) <= 2.0:
    print(f"0 {ld:.3f} {st:.3f}")   # 真裁成一段了：本地从 0 起，时间戳补回偏移
else:
    print(f"{st:.3f} {en:.3f} 0")   # 没裁成，还是全片：按绝对时间取
PY
)"
    fi
  else
    VIDEO="$INPUT"
  fi

  echo "[帧 2/2] 抽帧…"
  # 抽帧失败不该连文字稿一起废掉（比如把 --frames 用在了纯音频文件上）
  bash "$HERE/frames.sh" "$VIDEO" --out "$OUTDIR/frames" --width "$FWIDTH" \
    --start "$FSTART" ${FEND:+--end "$FEND"} --offset "$FOFF" \
    ${MAXF:+--max-frames "$MAXF"} \
    || echo "⚠️  抽帧失败（原因见上一行），这趟只出文字稿" >&2
fi

# ── 慢路：扒音轨 + whisper ────────────────────────────────
if [[ $GOT_SUB -eq 0 ]]; then
  MEDIA="$INPUT"
  if [[ -n "$VIDEO" ]]; then
    MEDIA="$VIDEO"      # 抽帧已经把原片下下来了，音轨直接从它里面拿，不重复下载
  elif [[ $IS_URL -eq 1 ]]; then
    # HEAD 默认是字符串 "0"（表示不限），${HEAD:+} 只判空不判零，会一直打出"只要前 0s"
    HEAD_NOTE=""; [[ "$HEAD" != "0" ]] && HEAD_NOTE="（只要前 ${HEAD}s）"
    echo "[2/4] 扒音轨${HEAD_NOTE}…"
    SECTION=(); [[ "$HEAD" != "0" ]] && SECTION=(--download-sections "*0-$HEAD")
    # TikTok 这类站点有 JS 挑战，同一条链接反复请求会互相拖累，成功与否带随机性
    # （2026-08-08 实测：同一条视频交替成功/失败，跟加不加 --download-sections 无关）。
    # 所以失败后隔几秒重试，并且第二次去掉分段——分段只是省带宽，下面 ffmpeg 会按 --head 再裁一次。
    if ! "$YTDLP" "${YTA[@]}" --no-warnings -f "bestaudio/best" -x --audio-format mp3 "${SECTION[@]+"${SECTION[@]}"}" \
         -o "$OUTDIR/media.%(ext)s" "$INPUT" >/dev/null 2>&1; then
      echo "  ⚠️  第一次没扒下来，隔 8 秒重试（部分站点有反爬挑战，失败带随机性）…"
      sleep 8
      "$YTDLP" "${YTA[@]}" --no-warnings -f "bestaudio/best" -x --audio-format mp3 \
        -o "$OUTDIR/media.%(ext)s" "$INPUT" >/dev/null 2>&1 \
      || { echo "  ⚠️  第二次也没成，再隔 20 秒最后试一次…"; sleep 20;
           "$YTDLP" "${YTA[@]}" --no-warnings -f "bestaudio/best" -x --audio-format mp3 \
             -o "$OUTDIR/media.%(ext)s" "$INPUT" >/dev/null \
           || die "yt-dlp 扒不下来（可能需要登录、站点反爬，或该站点不支持）"; }
    fi
    MEDIA="$OUTDIR/media.mp3"
  fi

  echo "[3/4] 转 16k 单声道…"
  TRIM=(); [[ "$HEAD" != "0" ]] && TRIM=(-t "$HEAD")
  ffmpeg -y -v error -i "$MEDIA" "${TRIM[@]+"${TRIM[@]}"}" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$OUTDIR/audio.wav"

  echo "[4/4] whisper 转录中…${HINT:+（带领域词提示）}"
  # --carry-initial-prompt：不带的话提示只作用于头 30 秒那一窗，长视频等于没提示
  HINT_ARGS=(); [[ -n "$HINT" ]] && HINT_ARGS=(--prompt "$HINT" --carry-initial-prompt)
  whisper-cli -m "$MODEL" -l "$LANG_OPT" "${HINT_ARGS[@]+"${HINT_ARGS[@]}"}" \
    -osrt -of "${SRT%.srt}" "$OUTDIR/audio.wav" \
    >"$OUTDIR/.whisper.log" 2>&1 || { tail -20 "$OUTDIR/.whisper.log" >&2; die "whisper 失败"; }

  # 只清自己造的中间产物，绝不碰用户传进来的源文件
  if [[ $KEEP -eq 0 ]]; then
    [[ "$(cd "$(dirname "$OUTDIR/audio.wav")" && pwd)/audio.wav" != "$(cd "$(dirname "$INPUT")" 2>/dev/null && pwd || echo x)/$(basename "$INPUT")" ]] && rm -f "$OUTDIR/audio.wav"
    [[ $IS_URL -eq 1 ]] && rm -f "$OUTDIR/media.mp3"
  fi
fi

# 原片是抽帧时下的，帧已落盘就没用了；本地传进来的源文件绝不碰
if [[ $KEEP -eq 0 && $IS_URL -eq 1 && -n "$VIDEO" ]]; then rm -f "$VIDEO"; fi

# ── 术语纠错：改 SRT，让 txt/timed/srt 三份产物口径一致 ────
if [[ -s "$SRT" && ${#TERM_FILES[@]} -gt 0 ]]; then
  TERM_ARGS=(); for f in "${TERM_FILES[@]}"; do TERM_ARGS+=(--terms "$f"); done
  # 纠错失败不该把整篇文字稿废掉，原稿还在，吵一声继续
  python3 "$HERE/apply_terms.py" "$SRT" "${TERM_ARGS[@]}" \
    || echo "⚠️  术语纠错没跑成（原因见上一行），文字稿按原样出" >&2
fi

# ── 收敛：SRT -> 可读稿 ───────────────────────────────────
NO_SPEECH=0
if [[ -s "$SRT" ]]; then
  TXT_LANG="$LANG_OPT"
  [[ "$TXT_LANG" == "auto" ]] && TXT_LANG="zh"
  python3 "$HERE/srt2text.py" "$SRT" \
    --out-txt "$OUTDIR/transcript.txt" \
    --out-md  "$OUTDIR/transcript-timed.md" \
    --lang "$TXT_LANG" --max-sec "$HEAD" || NO_SPEECH=1
else
  NO_SPEECH=1
fi

if [[ $NO_SPEECH -eq 1 ]]; then
  # 纯字卡/无口播视频走到这里是正常结果，不是故障——但前提是开了 --frames，不然这趟白跑
  [[ $FRAMES -eq 1 ]] || die "没拿到字幕/转录结果。这条大概是纯字卡/无口播视频，
   加 --frames 重跑一遍，改成读画面：run.sh \"$INPUT\" --frames"
  echo "（转录为空：这条没有口播，内容全在画面里 -> frames/）"
  printf '（无口播，转录为空。内容全在画面里，逐帧读 frames/ ，索引见 frames/INDEX.md）\n' \
    > "$OUTDIR/transcript.txt"
  rm -f "$OUTDIR/transcript-timed.md"
fi

rm -f "$OUTDIR/.meta.err" "$OUTDIR/.whisper.log"

# 极短转录 ≠ 短视频没内容，多半是背景音上的幻觉（实测出过「字幕志愿者 李宗盛」这种）
if [[ $NO_SPEECH -eq 0 ]]; then
  CHARS="$(python3 -c "import sys;print(len(open(sys.argv[1],encoding='utf-8').read().strip()))" "$OUTDIR/transcript.txt" 2>/dev/null || echo 999)"
  if [[ "$CHARS" -lt 30 ]]; then
    if [[ $FRAMES -eq 1 ]]; then
      echo "⚠️  转录只有 $CHARS 字，基本可以断定是纯背景音上的幻觉——别当内容用，以 frames/ 画面为准"
    else
      echo "⚠️  转录只有 $CHARS 字：要么没口播、要么这是背景音幻觉。加 --frames 重跑改读画面"
    fi
  fi
fi

echo
echo "✅ ${TITLE:-完成}"
echo "   $OUTDIR/transcript.txt        ← 可读文字稿"
[[ -f "$OUTDIR/transcript-timed.md" ]] && echo "   $OUTDIR/transcript-timed.md   ← 带时间戳"
[[ -s "$SRT" ]] && echo "   $OUTDIR/transcript.srt"
[[ -f "$OUTDIR/info.md" ]] && echo "   $OUTDIR/info.md               ← 标题/作者/播放/点赞/原文案"
[[ -d "$OUTDIR/frames" ]] && echo "   $OUTDIR/frames/               ← 画面帧，用 Read 逐帧读图"
echo
cat "$OUTDIR/transcript.txt"
if [[ -f "$OUTDIR/frames/INDEX.md" ]]; then
  echo
  cat "$OUTDIR/frames/INDEX.md"
fi
