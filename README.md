# link2transcript（顺风耳）

一个链接进，一份文字稿出。**全本地、免费、不限次数、不调任何大模型接口。**

给 Claude Code 用的 skill，也可以当普通命令行脚本单独跑。

```bash
bash scripts/run.sh "https://www.youtube.com/watch?v=XXXX" --lang zh
```

## 它干什么

丢一个视频/音频链接或本地文件进去，出一份干净的文字稿。就这一件事。

支持 YouTube、B站、播客，以及本地视频音频文件（凡是 `yt-dlp` 支持的站点都能试）。

跑完落盘四份东西：

| 文件 | 用途 |
|---|---|
| `transcript.txt` | 按停顿和句子分好段的可读稿，日常看这个 |
| `transcript-timed.md` | 每句带 `mm:ss` 时间戳，要回原片定位用 |
| `transcript.srt` | 标准字幕文件 |
| `info.md` | 标题、作者、平台、时长、播放、点赞、原文案 |

## 三条设计取舍

1. **全本地，不上传**。会议录音、未发布的素材、私人访谈，一个字节都不出你的电脑。
2. **零 API Key**。不调任何大模型接口，没有额度、没有排队、不消耗 token。装完断网也能转本地文件。
3. **只做转录这一件事**。不做翻译、不做配音、不做字幕烧录——那些有更全的工具，这里不重复造。

## 装它：复制下面这段话，丢给你的 AI

**你不用开终端，也不用懂这些工具是什么。** Claude Code、Codex 都认，复制这段粘贴过去：

```text
帮我装 link2transcript 这个 skill：
1. 从 GitHub 装 stelomighty/link2transcript（Claude Code 放 ~/.claude/skills/link2transcript，
   Codex 用 skill-installer 装，--path . --name link2transcript）
2. 读里面的 README.md，按「手动安装」一节把 yt-dlp、ffmpeg、whisper-cpp 三个依赖和模型装好
3. 我在中国大陆，模型用 hf-mirror 那个地址（不在大陆的把这句删掉）
4. 装完随便找条视频链接跑一遍，确认能出文字稿再告诉我
```

它会逐条问你要不要执行命令，点同意就行。全程五到十分钟，绝大部分时间花在下那个 547MB 的模型上。

**Codex 用户注意：装完要重启 Codex 才能认到新 skill。**

### 支持哪些工具

`SKILL.md`（Claude Code / Codex 都读）和 `AGENTS.md`（Codex / Cursor / Aider / Cline 等读）都在仓库根目录，命令契约是同一套。文档里的 `$SKILL` 指本 skill 的安装目录：

| 工具 | `$SKILL` 是 | 装法 |
|---|---|---|
| Claude Code | `~/.claude/skills/link2transcript/` | clone 进去即可 |
| Codex | `~/.codex/skills/link2transcript/` | 内置 skill-installer，见下 |
| 其他 / 直接用 | 仓库根目录 | clone 到任意位置，直接跑 `scripts/run.sh` |

Codex 手动装（不想让 AI 代劳的话）：

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo stelomighty/link2transcript --path . --name link2transcript
```

`--name` 不能省——不给的话安装器会拿 `--path .` 的 basename 当名字，报 `Invalid skill name`。

装完之后**也不用记命令**，直接跟 Claude 说人话：

```text
把这个视频转成文字 https://...
这条链接讲了什么
只要前 30 秒，我想看他开头怎么勾人的
这个视频没有口播，你看看画面里写了什么
```

---

## 手动安装

三个免费依赖，一条命令：

```bash
brew install yt-dlp ffmpeg whisper-cpp
```

再下模型（547MB，**下 turbo 那版**，别下 3GB 的完整版，日常听写用不上那个精度）：

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

**中国大陆用户**：`huggingface.co` 直连不通，把上面命令里的域名换成 `hf-mirror.com` 即可，文件完全一样（574,041,195 字节，已核对）：

```bash
curl -L --create-dirs -o ~/.cache/whisper.cpp/ggml-large-v3-turbo-q5_0.bin \
  https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

当 Claude Code skill 用的话，直接 clone 到 skills 目录（目录名和仓库名一致）：

```bash
git clone https://github.com/stelomighty/link2transcript.git ~/.claude/skills/link2transcript
```

然后跟 Claude 说「把这个视频转成文字」+ 链接就行。

## 快到什么程度

它先去问平台要自带字幕，要到了几秒钟结束，本地模型根本不启动。要不到才下音轨转录。

本地转录实测约 **10 倍实时**（49 秒音频 4.9 秒，196 秒音频 19.9 秒，Apple Silicon）。10 分钟的播客约 1 分钟出稿。

## 三个别人不会告诉你的坑

**转录模型只有耳朵没有眼睛。** 纯字卡视频、没有口播的演示，转出来是空的——不是工具坏了，是那条视频压根没人说话。这种加 `--frames`，它会均匀抽帧存下来，文件名自带原片时间，直接读图。

**模型在纯背景音上会编内容。** 空白你一眼看得出来，编出来的句子看不出来。所以脚本对 30 字以下的结果会告警，见到告警就当没转录到。

**专有名词几乎一定会转错。** 两道闸：`--hint` 在转录时给模型喂领域词（事前偏向），`--terms` 在出稿前按 `错=>对` 词表擦一遍（事后纠正，每改一处都打印，不偷偷改字）。实测一句技术口播里 6 个术语错 5 个，两道闸叠加能全部救回来。

## 常用参数

| 参数 | 说明 |
|---|---|
| `--lang zh\|en\|auto` | 语种。知道就写死，识别更准 |
| `--out 目录` | 输出目录 |
| `--head N` | 只处理前 N 秒 |
| `--frames` | 抽帧看画面（默认关） |
| `--force-asr` | 跳过平台自带字幕，强制重新转录 |
| `--hint "领域词"` | 转录时喂给模型的领域词，30 词以内 |
| `--terms 词表` | 出稿前按 `错=>对` 词表纠错 |

完整参数和实现细节见 [SKILL.md](SKILL.md)。

## 各平台实测情况

| 平台 | 状态 | 说明 |
|---|---|---|
| YouTube / B站 / 播客 | ✅ 稳 | 端到端跑通 |
| 本地视频音频文件 | ✅ 稳 | mp4 / mov / mp3 / m4a / aiff 等 |
| **小红书** | ✅ 能用，但**链接有讲究** | 见下 |
| **TikTok** | ✅ 能用，靠 UA 伪装 + 重试撑着 | 见下 |
| 抖音 / X | ❓ 没实测 | yt-dlp 有提取器，可以试 |

**小红书**：链接必须是**从 App 分享出来的**，带 `xsec_token` 参数的那种。桌面浏览器地址栏直接复制的链接没有这个参数，扒不动。token 还会过期，隔一阵子得重新分享一次。另外小红书只给标题和时长，作者/播放/点赞全是 `—`，这是平台没给不是脚本坏了；图文笔记（非视频）本身没有视频流，报 `No video formats found` 是正常结果。

**TikTok**：脚本给所有 yt-dlp 请求挂了浏览器 User-Agent（可用环境变量 `TRANSCRIPT_UA` 覆盖）。不挂的话 TikTok 认得出 yt-dlp，会发一个不含视频数据的空壳页，报 `Unable to extract universal data for rehydration`。另外 TikTok 的 JS 挑战让成功带随机性，所以失败后有 8 秒 / 20 秒两级重试。看到「隔 8 秒重试」的提示是正常的，不是坏了。

UA 哪天失效的话，装 `curl_cffi` 后可以用 yt-dlp 的 `--impersonate` 做更彻底的浏览器指纹伪装。

## 中国大陆网络下能用吗

能，但有两处要绕：

| 环节 | 情况 | 怎么办 |
|---|---|---|
| 装依赖 `brew install` | 能跑，就是慢 | 嫌慢换中科大 / 清华的 Homebrew 镜像 |
| **下模型** | `huggingface.co` 直连不通 | 换 `hf-mirror.com`，见上面安装一节 |
| **转 YouTube 链接** | YouTube 本身不通 | 需要代理 |
| 转 B站 / 小宇宙 / 本地文件 | **不受影响** | — |

换句话说：**拿它处理本地录音、B站、播客完全没问题**；只有 YouTube 那条路需要你自己有代理。

（作者的机器走代理出口，无法实测大陆直连情况。上表中「hf-mirror 供同一个文件」是核对过字节数的，其余是通行经验，以你本地实测为准。）

## 关于支持

**按现状提供。** 我不接 issue 也不接 PR，但代码你随便改、随便 fork。

## License

MIT
