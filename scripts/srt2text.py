#!/usr/bin/env python3
# SRT -> 可读文字稿。
# 两个来源共用这一个转换器：whisper.cpp 出的 srt，和 YouTube 自带字幕的 srt。
# YouTube 自动字幕是滚动式的（下一条包含上一条的尾巴），所以要去重叠。
#
#   python3 srt2text.py <in.srt> --out-txt <out.txt> --out-md <out.md> [--lang zh]

import re
import sys
import argparse

TAG = re.compile(r"<[^>]+>")
TIME = re.compile(
    r"(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})"
)


def secs(h, m, s, ms):
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def parse(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    segs = []
    for block in re.split(r"\n\s*\n", raw.strip()):
        lines = [l for l in block.splitlines() if l.strip()]
        if not lines:
            continue
        m = None
        body_from = 0
        for i, l in enumerate(lines):
            m = TIME.search(l)
            if m:
                body_from = i + 1
                break
        if not m:
            continue
        text = " ".join(lines[body_from:])
        text = TAG.sub("", text).strip()
        text = re.sub(r"\s+", " ", text)
        if not text:
            continue
        segs.append(
            {
                "s": secs(*m.group(1, 2, 3, 4)),
                "e": secs(*m.group(5, 6, 7, 8)),
                "t": text,
            }
        )
    return segs


def dedupe(segs):
    """滚动字幕去重：新句若以上一句结尾重叠，砍掉重叠部分；完全重复则丢弃。"""
    out = []
    for sg in segs:
        t = sg["t"]
        if out:
            prev = out[-1]["t"]
            if t == prev or t in prev:
                continue
            # 找最长的「prev 尾巴 == t 开头」重叠
            n = min(len(prev), len(t))
            cut = 0
            for k in range(n, 3, -1):
                if prev[-k:] == t[:k]:
                    cut = k
                    break
            if cut:
                t = t[cut:].strip()
            if not t:
                continue
        out.append({**sg, "t": t})
    return out


SENT_END = tuple("。！？.!?…；;")


def join(segs, lang, gap=1.2, max_chars=180, hard_chars=420):
    """按停顿和长度分段。长度到了也要等一句话说完再断，别拦腰砍。"""
    sep = "" if lang.startswith("zh") else " "
    paras, cur, last_end = [], [], None

    def flush():
        nonlocal cur
        if cur:
            paras.append(sep.join(cur))
            cur = []

    for sg in segs:
        if cur:
            body = sep.join(cur)
            long_pause = last_end is not None and sg["s"] - last_end > gap
            ended = body.rstrip().endswith(SENT_END)
            if long_pause or (len(body) > max_chars and ended) or len(body) > hard_chars:
                flush()
        cur.append(sg["t"])
        last_end = sg["e"]
    flush()
    return [p.strip() for p in paras if p.strip()]


def hhmm(t):
    return f"{int(t // 60):02d}:{int(t % 60):02d}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("srt")
    ap.add_argument("--out-txt", required=True)
    ap.add_argument("--out-md")
    ap.add_argument("--lang", default="zh")
    ap.add_argument("--max-sec", type=float, default=0, help="只保留前 N 秒（0=全部）")
    a = ap.parse_args()

    segs = dedupe(parse(a.srt))
    if a.max_sec:
        segs = [s for s in segs if s["s"] < a.max_sec]
    if not segs:
        print("srt 里没解析出任何内容", file=sys.stderr)
        sys.exit(2)

    paras = join(segs, a.lang)
    open(a.out_txt, "w", encoding="utf-8").write("\n\n".join(paras) + "\n")

    if a.out_md:
        lines = [f"`{hhmm(s['s'])}`  {s['t']}" for s in segs]
        open(a.out_md, "w", encoding="utf-8").write("\n".join(lines) + "\n")

    print(f"{len(segs)} 段 -> {len(paras)} 自然段, {sum(len(p) for p in paras)} 字")


if __name__ == "__main__":
    main()
