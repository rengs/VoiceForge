# VoiceForge

VoiceForge 是面向 macOS Apple Silicon 的本地优先中文语音输入助手：

> 按住 ⌘⇧Space 讲话 → 松开 → 本地中文识别 → 可选 Agent 处理 → 输入当前光标位置

第一版采用 Python AI 服务与 Swift 菜单栏客户端分层设计。普通听写完全
不调用 LLM；只有识别到“改写、总结、翻译、生成、代码”等明确意图时，
才调用配置的本地 Ollama 或 OpenAI-compatible 服务。

## 已实现

- 全局 Push-to-Talk 快捷键：按住 `Command + Shift + Space` 录音，松开处理
- SenseVoiceSmall 本地中文识别，Paraformer 作为可切换备选
- 中文标点收尾、SenseVoice 标签清理、SQLite 专业词替换
- `input / rewrite / summarize / translate / generate / code` 意图路由
- 写作、翻译、总结、生成、编程 Agent 插件
- Ollama 与任意 OpenAI-compatible LLM 统一接口
- macOS Accessibility API 获取选中文字，并通过剪贴板输入当前应用
- 菜单栏状态：Ready / Listening / Processing / Error
- 事件总线：语音、意图、LLM、文本注入与服务状态事件
- SQLite Memory：最近输入、用户偏好、专业词库、事件记录
- Word、浏览器、VS Code、ChatGPT 客户端、微信等通用文本框兼容路径

## 系统要求

- Apple Silicon Mac，macOS 13 或更高
- Xcode Command Line Tools
- Homebrew
- Python 3.10–3.12（安装脚本会自动选取；不使用不兼容的 Python 3.14）
- 约 3–6 GB 可用磁盘空间（Python 依赖和 ASR 模型）

## 一键安装

```bash
cd "/Users/rengs/Nutstore Files/我的坚果云/VoiceForge"
./install.sh
```

安装脚本会：

1. 创建项目独立的 `.venv`；
2. 安装后端、SoundDevice/PortAudio 运行库、FunASR、ModelScope、Torch
   与测试依赖；
3. 下载 SenseVoiceSmall；
4. 从 Ollama 官方安装用户级运行时并下载低延迟的 `qwen2.5:3b`；
5. 构建并签名 `VoiceForge.app`；
6. 安装到 `~/Applications/VoiceForge.app`；
7. 运行全部后端测试。

只在调试安装脚本时跳过模型下载：

```bash
VOICEFORGE_SKIP_MODEL_DOWNLOAD=1 ./install.sh
```

若只需要普通听写，可跳过约 2.5 GB 的本地 LLM：

```bash
VOICEFORGE_SKIP_LLM_INSTALL=1 ./install.sh
```

## 启动与首次授权

```bash
./start.sh
```

首次启动后按 macOS 提示完成：

1. `系统设置 → 隐私与安全性 → 辅助功能`：允许 VoiceForge；
2. `系统设置 → 隐私与安全性 → 输入监控`：允许 VoiceForge；
3. `系统设置 → 隐私与安全性 → 麦克风`：允许 VoiceForge/Python；
4. 修改输入监控权限后必须退出并重新打开 VoiceForge。

菜单栏显示 `🎙 VoiceForge` 后，在任意输入框按住 `⌘⇧Space` 讲话，
松开后识别结果会粘贴到原光标位置。VoiceForge 不会激活自己的窗口，
因此 Word、浏览器、VS Code、ChatGPT 和微信中的焦点会被保留。

## Agent 使用

普通口述直接输入：

```text
今天完成智能采油项目方案编制
```

输出：

```text
今天完成智能采油项目方案编制。
```

处理当前选中文字：

1. 在当前应用选中一段文字；
2. 按住快捷键说“把这句话改成科技项目申报语言”；
3. VoiceForge 获取选中文字，调用 Rewrite Agent，并用结果替换选区。

没有选中文字时，Agent 会使用 SQLite Memory 中最近一次输入作为上下文。

## 配置本地 LLM

默认配置为 Ollama + `qwen2.5:3b`，一键安装脚本已自动完成安装与下载。
若曾跳过 LLM 安装，可补装：

```bash
./scripts/install_ollama.sh
```

编辑项目根目录 `.env`：

```dotenv
VOICEFORGE_LLM_PROVIDER=ollama
VOICEFORGE_LLM_MODEL=qwen2.5:3b
VOICEFORGE_OLLAMA_URL=http://127.0.0.1:11434
VOICEFORGE_LLM_TIMEOUT_SECONDS=45
VOICEFORGE_LLM_MAX_TOKENS=512
VOICEFORGE_LLM_THINK=false
```

也可切换到任何 OpenAI-compatible API：

```dotenv
VOICEFORGE_LLM_PROVIDER=openai
VOICEFORGE_LLM_MODEL=your-model
VOICEFORGE_OPENAI_BASE_URL=https://example.com/v1
VOICEFORGE_OPENAI_API_KEY=your-key
```

只做普通听写、不使用 Agent：

```dotenv
VOICEFORGE_LLM_PROVIDER=disabled
```

## 修改快捷键

在菜单栏点击 `VoiceForge → 打开设置文件`，修改：

```dotenv
VOICEFORGE_HOTKEY=command+shift+space
```

保存后点击 `VoiceForge → 重新加载快捷键`，无需重启。支持
`command/cmd`、`shift`、`option/alt`、`control/ctrl`，以及
`Space`、`A-Z`、`0-9`、`Return`、`Tab`、`Escape`。快捷键至少需要一个修饰键。

## 切换 ASR

SenseVoiceSmall（默认）：

```dotenv
VOICEFORGE_ASR_MODEL=sensevoice
VOICEFORGE_ASR_DEVICE=cpu
```

Paraformer：

```dotenv
VOICEFORGE_ASR_MODEL=paraformer
VOICEFORGE_ASR_DEVICE=cpu
```

修改 `.env` 后退出并重新打开 VoiceForge。M2 上默认使用 CPU 是为了兼容
FunASR 自定义算子；24 GB 内存足以运行第一版模型。

## 开发与测试

```bash
source .venv/bin/activate
python -m pytest
python -m backend.main doctor
python -m backend.main serve
```

Swift 客户端单独构建：

```bash
./scripts/build_app.sh
```

构建脚本会校验 Swift 编译器与 macOS SDK。若本机 Command Line Tools
内部版本不一致（例如编译器与 SDK 的 `swiftlang` build 不同），会自动构建
功能等价的 Objective-C 原生兼容客户端，避免安装中断；完整 Swift/AppKit
源码仍位于 `frontend/swift/`，工具链修复后再次运行脚本会自动恢复 Swift
构建。这一兼容路径不改变快捷键、Accessibility、菜单栏或后端协议。

后端 API 文档（服务启动后）：

- `http://127.0.0.1:8765/docs`
- `GET /health`
- `POST /v1/recording/start`
- `POST /v1/recording/stop`
- `POST /v1/process`
- `GET/PUT /v1/memory/terms`

## 数据与隐私

- 普通录音和识别默认只在本机处理。
- 录音保存在 `data/recordings/`，便于问题定位；可定期手动删除。
- Memory 数据库位于 `data/voiceforge.sqlite3`。
- 只有 Agent 任务会把文本发送给 `.env` 中配置的 LLM。
- 使用本地 Ollama 时，Agent 文本同样不离开本机。

## 当前实时语义

第一版在按键期间持续采集实时音频流，在松开后按完整语句执行
SenseVoice 解码。这符合 Push-to-Talk 的低误触闭环，但不是“边说边显示字”
的增量字幕模式。`ASREngine` 和事件总线已经隔离，后续可增加
ParaformerStreaming 插件而不改变 Swift 客户端和 Agent 层。

## 项目结构

```text
VoiceForge/
├── backend/
│   ├── agent/       # Intent Router 与插件式 Agents
│   ├── asr/         # SenseVoice / Paraformer
│   ├── llm/         # Ollama / OpenAI-compatible
│   ├── memory/      # SQLite Memory
│   ├── text/        # 文本后处理
│   ├── voice/       # 实时音频采集
│   ├── api.py       # 本地 FastAPI
│   ├── events.py    # Event Bus
│   └── service.py   # 主流程编排
├── frontend/swift/  # macOS 菜单栏与系统输入集成
├── scripts/         # 模型下载、App 构建
├── tests/           # 自动验收测试
├── install.sh
├── start.sh
└── stop.sh
```

架构与扩展约定见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
