# link2transcript（顺风耳）

**中文** ｜ [English](#english)

**丢一个视频链接进去，出一份文字稿。** 就这一件事，做干净。

全本地跑，免费，不限次数，**一个 API key 都不需要**。

---

## 怎么装：复制下面这段话，粘给你的 AI

**你不用开终端，也不用懂下面提到的任何工具是什么。** Claude Code、Codex 都认这一段：

```text
帮我装 link2transcript 这个 skill：
1. 从 GitHub 装 stelomighty/link2transcript
2. 读它的 README.md，按「自己动手装」一节把三个依赖和模型装好
3. 模型从 hf-mirror.com 那个地址下（全球都连得上），下不动再换官方地址
4. 装完自检一下：用 say 命令生成一段测试语音，跑一遍看能不能出文字稿，然后告诉我结果
```

它会逐条问你要不要执行命令，点同意就行。**全程五到十分钟**，绝大部分时间花在下那个 547MB 的模型上。

> **Codex 用户**：装完要重启 Codex 才认得到新 skill。

## 怎么用：直接说人话

装完**不用记任何命令**，跟你的 AI 这么说就行：

```text
把这个视频转成文字 https://...
这条链接讲了什么
只要前 30 秒，我想看他开头怎么勾人的
这个视频没有口播，你看看画面里写了什么
```

文字稿会**直接出现在对话里**，你不用去找文件。

## 跑完你会得到什么

文字稿当场打印在对话里，同时四份文件落盘留档，默认在 `~/transcripts/<月日-时分秒>/`（每跑一次新建一个文件夹，不会互相覆盖）：

| 文件 | 长什么样 | 什么时候用 |
|---|---|---|
| `transcript.txt` | `All right, so here we are, in front of the elephants` | 日常看这个，按停顿分好段的纯文本 |
| `transcript-timed.md` | `` `00:01`  All right, so here we are... `` | 要回原片定位某句话 |
| `transcript.srt` | `00:00:01,200 --> 00:00:03,360` + 文本 | 拿去压字幕 |
| `info.md` | 标题 / 作者 / 时长 / 播放 / 点赞 / 原文案 | 要元数据 |

（还有一个 `meta.json` 是原始元数据，给程序读的，你不用管。）

## 支持哪些平台

全部实测跑通过。**有附加条件的三个，条件写在下面这一列——动手前先看一眼，省得白试。**

| 平台 | | 附加条件 |
|---|---|---|
| **YouTube / B站 / 播客** | ✅ | 无 |
| **本地视频音频文件** | ✅ | 无。mp4 / mov / mp3 / m4a / aiff 等 |
| **X（Twitter）** | ✅ | 推文里得有视频 |
| **TikTok** | ✅ | 无。偶尔会自动重试一次，等它跑完就行 |
| **小红书** | ✅ | ① 视频笔记，图文笔记没有音轨<br>② 链接要**从 App 分享**（带 `xsec_token`），桌面地址栏复制的不行 |
| **抖音** | ✅ | ① 要**你自己提供 cookies**<br>② 还得指定对 Chrome 配置文件，默认那个多半不对 |

<details>
<summary><b>小红书链接扒不动？</b></summary>

链接得是**从 App 分享出来的**那种，带 `xsec_token` 参数。桌面浏览器地址栏直接复制的没有这个参数。token 也会过期，隔一阵子重新分享一次就行。

另外两件正常现象：小红书只给标题和时长，作者/播放/点赞是空的——平台没给；图文笔记本身没有视频流，报 `No video formats found` 是对的，换视频笔记即可。

</details>

<details>
<summary><b>TikTok 提示「隔 8 秒重试」？</b></summary>

正常，不用管。TikTok 的 JS 挑战让请求成功带随机性，所以脚本内置了 8 秒 / 20 秒两级重试，等它自己跑完就行。

脚本还给所有请求挂了浏览器 User-Agent——不挂的话 TikTok 会发一个不含视频数据的空壳页。哪天这招失效，见下面「支持哪些 AI 工具」一节的 `--impersonate`。

</details>

<details>
<summary><b>抖音报 <code>Fresh cookies are needed</code>？</b></summary>

抖音有 cookie 墙，得你自己提供：

```bash
--cookies-from-browser chrome     # 从浏览器取
--cookies cookies.txt             # 或用 Netscape 格式文件
```

**默认不开**——cookies 是隐私数据，必须你显式指定，脚本不会自作主张去读你的浏览器。

**加了还是报同样的错？多半是 Chrome 配置文件选错了。** Chrome 常有多个 profile，而 `--cookies-from-browser chrome` 只读 `Default` 那个——很多人日常用的其实是 Profile 1/2/3，Default 可能几个月没动过了。

查自己是哪个：Chrome 地址栏输 `chrome://version`，看「个人资料路径 / Profile Path」那行，末尾就是配置文件名。然后：

```bash
--cookies-from-browser "chrome:Profile 2"
```

还有一点：**抖音的 cookie 得是那个 profile 真的访问过 douyin.com 才有**（不用登录）。无痕窗口不算，它的 cookie 不落盘。

另外从抖音「精选」页复制出来的链接是 `douyin.com/jingxuan?modal_id=<id>` 这种形式，yt-dlp 不认。脚本会自动归一成 `douyin.com/video/<id>`，你直接粘原链接就行。

</details>

## 快到什么程度

它先去问平台要现成字幕，要到了几秒钟就结束，本地模型根本不启动。要不到才下音轨转录。

本地转录实测约 **10 倍实时**（49 秒音频跑 4.9 秒，196 秒音频跑 19.9 秒，Apple Silicon）。**10 分钟的播客约 1 分钟出稿。**

## 三个别人不会告诉你的坑

**转录模型只有耳朵，没有眼睛。** 纯字卡视频、没有口播的演示，转出来是空的——不是工具坏了，是那条视频压根没人说话。这种加 `--frames`，它会均匀抽帧存下来，文件名自带原片时间，让 AI 直接读图。

**模型在纯背景音上会编内容。** 空白你一眼看得出来，编出来的句子看不出来。所以脚本对 30 字以下的结果会告警，见到告警就当没转录到。

**专有名词几乎一定会转错。** 两道闸：`--hint` 在转录时给模型喂领域词（事前偏向），`--terms` 在出稿前按 `错=>对` 词表擦一遍（事后纠正，**每改一处都打印出来，不偷偷改字**）。实测一句技术口播里 6 个术语错 5 个，两道闸叠加能全部救回来。

<details>
<summary><b>有些地址连不上？</b></summary>

**下模型**：`huggingface.co` 连不上就换 `hf-mirror.com`，同一个文件（574,041,195 字节，核对过）。上面那段安装提示词默认就走镜像。

**YouTube 链接**：连不上那条路就用不了，但 **B站、小红书、播客、本地文件都不受影响**。

**装依赖慢**：`brew` 换中科大或清华的镜像源。

</details>

---

# 给愿意自己动手的人

上面那段话已经够用了。下面是给想手动装、或者想当普通命令行工具用的人看的。

## 自己动手装

三个免费依赖，一条命令：

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

再下模型（547MB，**下 turbo 那版**，别下 3GB 的完整版，日常听写用不上那个精度）：

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

**连不上的话**换镜像，同一个文件：

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

然后把仓库放进你的 AI 工具的 skills 目录：

```bash
# Claude Code
git clone https://github.com/stelomighty/link2transcript.git ~/.claude/skills/link2transcript

# Codex（用它自带的安装器；--name 不能省，不给会报 Invalid skill name）
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo stelomighty/link2transcript --path . --name link2transcript
```

不当 skill 用也行，clone 到任意位置直接跑 `scripts/run.sh` 就是个普通命令行工具。

## 直接跑命令

```bash
bash scripts/run.sh "<链接或本地文件>" --lang zh
```

| 参数 | 说明 |
|---|---|
| `--lang zh\|en\|auto` | 语种。知道就写死，识别更准 |
| `--out 目录` | 输出目录，默认 `~/transcripts/<月日-时分秒>/` |
| `--head N` | 只处理前 N 秒 |
| `--frames` | 抽帧看画面（默认关） |
| `--force-asr` | 跳过平台自带字幕，强制重新转录 |
| `--hint "领域词"` | 转录时喂给模型的领域词，30 词以内 |
| `--terms 词表` | 出稿前按 `错=>对` 词表纠错 |
| `--keep-media` | 保留下载的音频（默认删掉省空间） |
| `--cookies-from-browser 浏览器` | 从浏览器取 cookies（抖音等站点需要）。**默认不开**——cookies 是隐私数据，必须你显式指定 |
| `--cookies 文件` | 用 Netscape 格式的 cookies 文件，不碰浏览器 |

完整参数、实现细节、以及给 AI 看的使用规则见 [SKILL.md](SKILL.md) 和 [AGENTS.md](AGENTS.md)。

## 支持哪些 AI 工具

`SKILL.md`（Claude Code / Codex 读）和 `AGENTS.md`（Codex / Cursor / Aider / Cline 等读）都在仓库根目录，命令契约是同一套。文档里的 `$SKILL` 指本 skill 的安装目录：

| 工具 | `$SKILL` 是 |
|---|---|
| Claude Code | `~/.claude/skills/link2transcript/` |
| Codex | `~/.codex/skills/link2transcript/` |
| 其他 / 直接用 | 仓库根目录 |

UA 哪天被平台识破的话，装 `curl_cffi` 后可以用 yt-dlp 的 `--impersonate` 做更彻底的浏览器指纹伪装；也可以用环境变量 `TRANSCRIPT_UA` 换成你自己的 UA。

## 关于支持

**按现状提供。** 我不接 issue 也不接 PR，但代码你随便改、随便 fork。

## License

MIT

---

<a name="english"></a>

# link2transcript (English)

[中文](#link2transcript顺风耳) ｜ **English**

**Drop in a video link, get back a transcript.** That's the whole job, done properly.

Runs entirely on your machine. Free, unlimited, and **it needs no API key of any kind**.

---

## Install: copy the block below and paste it to your AI

**You don't need a terminal, and you don't need to know what any of the tools below are.** Both Claude Code and Codex understand this:

```text
Please install the link2transcript skill for me:
1. Install stelomighty/link2transcript from GitHub
2. Read its README.md and follow the "Manual install" section to set up the three
   dependencies and the model
3. Pull the model from the hf-mirror.com URL (reachable worldwide); fall back to the
   official one if that stalls
4. When you're done, verify it: generate a short test clip with the `say` command,
   run that through, and tell me whether a transcript came out
```

It will ask before running each command — just approve. **Five to ten minutes total**, almost all of it spent downloading the 547MB model.

> **Codex users**: restart Codex after installing so it picks up the new skill.

## Use it: just say what you want

Once installed you **never have to remember a command**. Talk to your AI:

```text
Turn this video into text: https://...
What's in this link?
Just the first 30 seconds — I want to see how the hook works
This video has no narration, look at what's written on screen
```

The transcript **appears right in the conversation**. You don't have to go hunting for files.

## What you get

The transcript prints into the conversation, and four files land on disk for your records — by default under `~/transcripts/<MMDD-HHMMSS>/` (a fresh folder per run, nothing overwrites):

| File | Looks like | When you want it |
|---|---|---|
| `transcript.txt` | `All right, so here we are, in front of the elephants` | The everyday one — plain text, split at natural pauses |
| `transcript-timed.md` | `` `00:01`  All right, so here we are... `` | Locating a line back in the original |
| `transcript.srt` | `00:00:01,200 --> 00:00:03,360` + text | Burning subtitles |
| `info.md` | Title / uploader / duration / views / likes / description | When you need the metadata |

(There's also a `meta.json` with raw metadata — that one's for machines, ignore it.)

## Supported platforms

All verified end-to-end. **Three of them have prerequisites — they're spelled out in the last column, so check before you try.**

| Platform | | Prerequisites |
|---|---|---|
| **YouTube / Bilibili / podcasts** | ✅ | None |
| **Local audio & video files** | ✅ | None. mp4 / mov / mp3 / m4a / aiff, etc. |
| **X (Twitter)** | ✅ | The tweet has to contain a video |
| **TikTok** | ✅ | None. It may auto-retry once — just let it finish |
| **Xiaohongshu (RedNote)** | ✅ | ① Video posts only — image posts have no audio track<br>② The link must be **shared from the app** (carries `xsec_token`); a desktop URL won't work |
| **Douyin** | ✅ | ① You have to **supply cookies** yourself<br>② And point at the right Chrome profile — the default one usually isn't it |

<details>
<summary><b>Xiaohongshu link not working?</b></summary>

The link has to be the one **shared from the app**, carrying an `xsec_token` parameter — a URL copied from the desktop address bar doesn't have one. The token also expires, so grab a fresh share now and then.

Two more things that look like bugs but aren't: Xiaohongshu only exposes title and duration, so uploader/views/likes come back empty; and image posts have no video stream at all, so `No video formats found` is the correct answer — use a video post instead.

</details>

<details>
<summary><b>TikTok says "retrying in 8 seconds"?</b></summary>

That's expected — just let it run. TikTok's JS challenge makes any single request probabilistic, so the script retries after 8 and then 20 seconds.

Every request also carries a browser User-Agent; without one TikTok serves a shell page with no video data. If that ever stops working, see `--impersonate` under "Which AI tools are supported" below.

</details>

<details>
<summary><b>Douyin returns <code>Fresh cookies are needed</code>?</b></summary>

Douyin sits behind a cookie wall, so you have to supply them:

```bash
--cookies-from-browser chrome     # pull from your browser
--cookies cookies.txt             # or a Netscape-format file
```

**Off by default** — cookies are private data, so the script never reaches into your browser unless you explicitly ask.

**Still the same error after adding that?** You're probably pointing at the wrong Chrome profile. Chrome usually has several, and `--cookies-from-browser chrome` only reads `Default` — which may be months stale if you actually live in Profile 1/2/3.

To find yours: type `chrome://version` in the address bar and look at "Profile Path" — the last path segment is the profile name. Then:

```bash
--cookies-from-browser "chrome:Profile 2"
```

One more thing: the Douyin cookies only exist if **that profile has actually visited douyin.com** (no login needed). Incognito windows don't count — their cookies never hit disk.

Also, links copied from Douyin's 精选 feed come in the form `douyin.com/jingxuan?modal_id=<id>`, which yt-dlp doesn't recognise. The script normalises those to `douyin.com/video/<id>` for you — just paste the original.

</details>

## How fast

It asks the platform for existing captions first. If it gets them, you're done in seconds and the local model never starts. Only when there are none does it pull the audio and transcribe.

Local transcription measures at roughly **10× realtime** (49s of audio in 4.9s; 196s in 19.9s, Apple Silicon). **A 10-minute podcast takes about a minute.**

## Three things nobody warns you about

**The model has ears, not eyes.** Text-card videos and silent screencasts come back empty — that isn't a failure, it's a video with nobody speaking. Add `--frames` and it samples evenly spaced stills whose filenames carry the source timestamp, so your AI can read the screen instead.

**On pure background noise the model invents content.** An empty result is obvious; a fabricated sentence isn't. So anything under 30 characters raises a warning — when you see it, treat the run as having captured nothing.

**Proper nouns will almost always come out wrong.** Two defences: `--hint` feeds domain vocabulary to the model up front (biasing decoding), and `--terms` applies a `wrong=>right` list afterwards (**every substitution is printed — nothing is changed behind your back**). In one measured technical sentence, 5 of 6 terms were wrong; the two together recovered all of them.

<details>
<summary><b>Some hosts unreachable from your network?</b></summary>

**The model**: if `huggingface.co` won't load, use `hf-mirror.com` — byte-identical file (574,041,195 bytes, verified), reachable worldwide. The install block above already points there.

**YouTube links**: if YouTube itself won't load, that route is out — but **Bilibili, Xiaohongshu, podcasts and local files are unaffected**.

**Slow dependency install**: point `brew` at a closer mirror.

</details>

---

# For people who'd rather do it by hand

The paste-to-your-AI block above is all most people need. What follows is for manual installation, or for using this as a plain command-line tool.

## Manual install

Three free dependencies, one command:

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

Then the model (547MB — **get the turbo build**, not the 3GB full one; you don't need that precision for everyday transcription):

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

Mirror (identical file, reachable worldwide):

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

Then drop the repo into your AI tool's skills directory:

```bash
# Claude Code
git clone https://github.com/stelomighty/link2transcript.git ~/.claude/skills/link2transcript

# Codex (its own installer; --name is required — without it you get "Invalid skill name")
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo stelomighty/link2transcript --path . --name link2transcript
```

You don't have to use it as a skill at all — clone it anywhere and run `scripts/run.sh` as an ordinary CLI tool.

## Running it directly

```bash
bash scripts/run.sh "<url or local file>" --lang en
```

| Flag | What it does |
|---|---|
| `--lang zh\|en\|auto` | Spoken language. Set it explicitly when you know it — accuracy improves |
| `--out DIR` | Output directory (default `~/transcripts/<MMDD-HHMMSS>/`) |
| `--head N` | Only process the first N seconds |
| `--frames` | Sample stills so the screen can be read (off by default) |
| `--force-asr` | Skip platform captions and transcribe from scratch |
| `--hint "terms"` | Domain vocabulary fed to the model during transcription; keep it under 30 words |
| `--terms FILE` | Apply a `wrong=>right` correction list before writing the transcript |
| `--keep-media` | Keep the downloaded audio (deleted by default to save space) |
| `--cookies-from-browser BROWSER` | Pull cookies from your browser (Douyin and similar need them). **Off by default** — cookies are private data, you have to ask for this explicitly |
| `--cookies FILE` | Use a Netscape-format cookie file instead of touching the browser |

Full flags, implementation notes, and the rules your AI should follow are in [SKILL.md](SKILL.md) and [AGENTS.md](AGENTS.md).

## Which AI tools are supported

`SKILL.md` (read by Claude Code and Codex) and `AGENTS.md` (read by Codex, Cursor, Aider, Cline and friends) both sit at the repo root and describe the same command contract. `$SKILL` throughout the docs means wherever this skill got installed:

| Tool | `$SKILL` is |
|---|---|
| Claude Code | `~/.claude/skills/link2transcript/` |
| Codex | `~/.codex/skills/link2transcript/` |
| Anything else / direct use | the repo root |

If the User-Agent ever stops fooling a platform, installing `curl_cffi` unlocks yt-dlp's `--impersonate` for full browser fingerprint spoofing; you can also override the UA with the `TRANSCRIPT_UA` environment variable.

## Support

**Provided as is.** I don't take issues or pull requests — but the code is yours to change and fork freely.

## License

MIT
