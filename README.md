# BOKO · AI 读书老师 📖

> 上传书籍，让 AI 用大白话把内容讲给你听

BOKO 是一个运行在你自己 VPS 上的 AI 读书助手。你把 PDF 或 EPUB 丢进去，它就像一个耐心的朋友，用简单的语言把书的内容讲给你听。

## 功能

- 📚 上传 PDF / EPUB / TXT 书籍
- 🎯 按章节选择，不用从头开始
- 💬 对话式讲解，随时可以追问
- 🔄 支持多种 AI：DeepSeek / Gemini / Groq / Claude / OpenAI
- 🔒 数据完全在你自己的服务器上

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zhangyang-games/boko/main/install.sh)
```

需要提前准备：
1. 一台有 Docker 的 VPS（已有 Cloudflare Tunnel）
2. 任意一家 AI 的 API Key（推荐 [Groq](https://console.groq.com) 免费）

## 技术栈

- **后端**：Python · FastAPI · SQLite
- **前端**：纯 HTML/CSS/JS，无需 Node.js
- **部署**：Docker · Cloudflare Tunnel

## 目录结构

```
boko/
├── server.py        # FastAPI 后端
├── index.html       # 网页界面
├── Dockerfile       # 容器构建
├── requirements.txt # Python 依赖
└── install.sh       # 一键安装脚本
```
