#!/usr/bin/env python3
"""按词表纠正 SRT 里的专有名词，并把改了哪些词原样报出来。

    apply_terms.py 字幕.srt --terms 词表.txt [--terms 另一份.txt]

词表是 UTF-8 文本，一行一条 `错=>对`，`#` 开头是注释：

    多包=>豆包
    报款=>爆款

只改字幕正文，序号行和时间轴行原样不动——词表里万一混进数字也不会把时间戳改坏。
纯 ASCII 的模式按整词匹配（`AI` 不会命中 `TRAIL`），中文按子串直接替换。
"""

import argparse
import re
import sys
from pathlib import Path

TS_LINE = re.compile(r"^\d{1,2}:\d{2}:\d{2}[,.]\d{1,3}\s*-->")
IDX_LINE = re.compile(r"^\d+$")
ASCII_ONLY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 .'\-]*$")


def load_terms(paths):
    """读词表，返回 [(错, 对, 来源文件名)]。后面的文件覆盖前面的同名条目。"""
    pairs, seen = [], {}
    for p in paths:
        for lineno, raw in enumerate(Path(p).read_text(encoding="utf-8").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=>" not in line:
                print(f"⚠️  {Path(p).name}:{lineno} 不是 `错=>对` 格式，跳过：{line}", file=sys.stderr)
                continue
            wrong, right = (s.strip() for s in line.split("=>", 1))
            if not wrong or wrong == right:
                continue
            if wrong in seen:
                pairs[seen[wrong]] = (wrong, right, Path(p).name)
            else:
                seen[wrong] = len(pairs)
                pairs.append((wrong, right, Path(p).name))
    return pairs


def compile_rule(wrong):
    """ASCII 词按整词边界匹配，中文按子串——中文没有词边界，\\b 会失效。"""
    if ASCII_ONLY.match(wrong):
        return re.compile(rf"\b{re.escape(wrong)}\b")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("srt")
    ap.add_argument("--terms", action="append", default=[], help="词表文件，可重复")
    args = ap.parse_args()

    srt = Path(args.srt)
    if not srt.is_file():
        return 0  # 没字幕就没什么好纠的，静默退出，不打断主流程

    pairs = load_terms(args.terms)
    if not pairs:
        return 0

    rules = [(w, r, src, compile_rule(w)) for w, r, src in pairs]
    counts = {}
    out = []
    for line in srt.read_text(encoding="utf-8").splitlines():
        if not (IDX_LINE.match(line.strip()) or TS_LINE.match(line.strip())):
            for wrong, right, src, rx in rules:
                n = len(rx.findall(line)) if rx else line.count(wrong)
                if n:
                    line = rx.sub(right, line) if rx else line.replace(wrong, right)
                    key = (wrong, right, src)
                    counts[key] = counts.get(key, 0) + n
        out.append(line)

    if not counts:
        return 0

    srt.write_text("\n".join(out) + "\n", encoding="utf-8")
    total = sum(counts.values())
    srcs = sorted({src for _, _, src in counts})
    print(f"🔤 术语纠错：改了 {total} 处（词表：{', '.join(srcs)}）")
    for (wrong, right, _), n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"   {wrong} → {right}  ×{n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
