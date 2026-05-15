#!/usr/bin/env python3
"""
BOKO - AI 读书老师后端  v1.1
新增：Basic Auth 登录保护 / 原文查看接口
"""

import os, json, sqlite3, time, hashlib, base64, secrets
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, HTTPException, Request, Depends
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx

# ── 路径配置 ──────────────────────────────────────────────────────
DATA_DIR  = Path(os.environ.get("BOKO_DATA", "/data"))
BOOKS_DIR = DATA_DIR / "books"
DB_PATH   = DATA_DIR / "boko.db"
BOOKS_DIR.mkdir(parents=True, exist_ok=True)

# ── Basic Auth ────────────────────────────────────────────────────
BOKO_USER = os.environ.get("BOKO_USER", "")
BOKO_PASS = os.environ.get("BOKO_PASS", "")

def check_auth(request: Request):
    if not BOKO_USER or not BOKO_PASS:
        return
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Basic "):
        raise HTTPException(
            status_code=401, detail="请登录",
            headers={"WWW-Authenticate": 'Basic realm="BOKO"'},
        )
    try:
        decoded = base64.b64decode(auth[6:]).decode("utf-8")
        username, password = decoded.split(":", 1)
    except Exception:
        raise HTTPException(status_code=401, detail="认证格式错误",
                            headers={"WWW-Authenticate": 'Basic realm="BOKO"'})
    if not (secrets.compare_digest(username, BOKO_USER) and
            secrets.compare_digest(password, BOKO_PASS)):
        raise HTTPException(status_code=401, detail="用户名或密码错误",
                            headers={"WWW-Authenticate": 'Basic realm="BOKO"'})

AUTH = [Depends(check_auth)]

# ── AI 配置 ───────────────────────────────────────────────────────
def get_ai_config():
    return {
        "provider": os.environ.get("AI_PROVIDER", "openai"),
        "api_key":  os.environ.get("AI_API_KEY", ""),
        "model":    os.environ.get("AI_MODEL", ""),
        "base_url": os.environ.get("AI_BASE_URL", ""),
    }

PROVIDER_DEFAULTS = {
    "openai":     {"base_url": "https://api.openai.com/v1",                               "model": "gpt-4o-mini"},
    "claude":     {"base_url": "https://api.anthropic.com/v1",                            "model": "claude-3-5-haiku-20241022"},
    "deepseek":   {"base_url": "https://api.deepseek.com/v1",                             "model": "deepseek-chat"},
    "gemini":     {"base_url": "https://generativelanguage.googleapis.com/v1beta/openai", "model": "gemini-2.0-flash"},
    "groq":       {"base_url": "https://api.groq.com/openai/v1",                          "model": "llama-3.3-70b-versatile"},
    "openrouter": {"base_url": "https://openrouter.ai/api/v1",                            "model": "meta-llama/llama-3.3-70b-instruct:free"},
}

# ── 数据库 ────────────────────────────────────────────────────────
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS books (
            id        TEXT PRIMARY KEY,
            title     TEXT NOT NULL,
            filename  TEXT NOT NULL,
            size      INTEGER,
            pages     INTEGER DEFAULT 0,
            added_at  INTEGER NOT NULL,
            last_read INTEGER
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id  TEXT NOT NULL,
            idx      INTEGER NOT NULL,
            title    TEXT,
            content  TEXT NOT NULL,
            FOREIGN KEY(book_id) REFERENCES books(id)
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id         TEXT PRIMARY KEY,
            book_id    TEXT NOT NULL,
            chunk_idx  INTEGER DEFAULT 0,
            history    TEXT DEFAULT '[]',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY(book_id) REFERENCES books(id)
        );
    """)
    conn.commit()
    conn.close()

# ── 书籍解析 ──────────────────────────────────────────────────────
def parse_pdf(path):
    try:
        import pypdf
        reader = pypdf.PdfReader(str(path))
        chunks, buf = [], ""
        for i, page in enumerate(reader.pages):
            buf += (page.extract_text() or "") + "\n"
            if len(buf) > 2000 or i == len(reader.pages) - 1:
                chunks.append({"title": f"第 {len(chunks)+1} 段", "content": buf.strip()})
                buf = ""
        return chunks or [{"title": "全文", "content": "（无法提取文本，可能是扫描版）"}]
    except Exception as e:
        return [{"title": "解析失败", "content": f"PDF 解析出错：{e}"}]

def parse_epub(path):
    try:
        import ebooklib
        from ebooklib import epub
        from html.parser import HTMLParser
        class _P(HTMLParser):
            def __init__(self): super().__init__(); self.text = []
            def handle_data(self, d): self.text.append(d)
            def get_text(self): return " ".join(self.text)
        book = epub.read_epub(str(path))
        chunks = []
        for item in book.get_items_of_type(ebooklib.ITEM_DOCUMENT):
            p = _P()
            p.feed(item.get_content().decode("utf-8", errors="ignore"))
            text = p.get_text().strip()
            if len(text) > 100:
                title = item.get_name().split("/")[-1].replace(".xhtml","").replace(".html","")
                chunks.append({"title": title or f"第{len(chunks)+1}章", "content": text})
        return chunks or [{"title": "全文", "content": "（EPUB 内容为空）"}]
    except Exception as e:
        return [{"title": "解析失败", "content": f"EPUB 解析出错：{e}"}]

def parse_book(path):
    s = path.suffix.lower()
    if s == ".pdf":  return parse_pdf(path)
    if s == ".epub": return parse_epub(path)
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
        return [{"title": f"第 {i//2000+1} 段", "content": text[i:i+2000]}
                for i in range(0, max(len(text),1), 2000)]
    except:
        return [{"title": "全文", "content": "（无法读取文件）"}]

# ── AI 调用 ───────────────────────────────────────────────────────
async def call_ai(messages, system=""):
    cfg      = get_ai_config()
    provider = cfg["provider"]
    api_key  = cfg["api_key"]
    model    = cfg["model"]    or PROVIDER_DEFAULTS.get(provider, {}).get("model", "")
    base_url = cfg["base_url"] or PROVIDER_DEFAULTS.get(provider, {}).get("base_url", "")
    if not api_key:
        raise HTTPException(400, "未配置 AI API Key")
    if provider == "claude":
        headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01",
                   "content-type": "application/json"}
        payload = {"model": model, "max_tokens": 2000, "messages": messages}
        if system: payload["system"] = system
        async with httpx.AsyncClient(timeout=60) as c:
            r = await c.post(f"{base_url}/messages", headers=headers, json=payload)
            r.raise_for_status()
            return r.json()["content"][0]["text"]
    else:
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        msgs = ([{"role": "system", "content": system}] if system else []) + messages
        async with httpx.AsyncClient(timeout=60) as c:
            r = await c.post(f"{base_url}/chat/completions", headers=headers,
                             json={"model": model, "max_tokens": 2000, "messages": msgs})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]

# ── 应用 ──────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app):
    init_db()
    yield

app = FastAPI(title="BOKO", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ── 页面 ──────────────────────────────────────────────────────────
@app.get("/", response_class=HTMLResponse, dependencies=AUTH)
async def index():
    return HTMLResponse((Path(__file__).parent / "index.html").read_text(encoding="utf-8"))

# ── 书籍 API ──────────────────────────────────────────────────────
@app.post("/api/books/upload", dependencies=AUTH)
async def upload_book(file: UploadFile = File(...)):
    if Path(file.filename).suffix.lower() not in (".pdf", ".epub", ".txt"):
        raise HTTPException(400, "只支持 PDF、EPUB、TXT 格式")
    content = await file.read()
    book_id = hashlib.md5(content).hexdigest()[:12]
    dest    = BOOKS_DIR / f"{book_id}{Path(file.filename).suffix.lower()}"
    dest.write_bytes(content)
    chunks  = parse_book(dest)
    title   = Path(file.filename).stem
    conn    = get_db()
    if not conn.execute("SELECT id FROM books WHERE id=?", (book_id,)).fetchone():
        conn.execute(
            "INSERT INTO books(id,title,filename,size,pages,added_at) VALUES(?,?,?,?,?,?)",
            (book_id, title, file.filename, len(content), len(chunks), int(time.time()))
        )
        for i, chunk in enumerate(chunks):
            conn.execute("INSERT INTO chunks(book_id,idx,title,content) VALUES(?,?,?,?)",
                         (book_id, i, chunk["title"], chunk["content"]))
        conn.commit()
    conn.close()
    return {"id": book_id, "title": title, "chunks": len(chunks)}

@app.get("/api/books", dependencies=AUTH)
async def list_books():
    conn = get_db()
    rows = conn.execute("SELECT * FROM books ORDER BY added_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]

@app.delete("/api/books/{book_id}", dependencies=AUTH)
async def delete_book(book_id: str):
    conn = get_db()
    if not conn.execute("SELECT id FROM books WHERE id=?", (book_id,)).fetchone():
        raise HTTPException(404, "书籍不存在")
    conn.execute("DELETE FROM chunks WHERE book_id=?", (book_id,))
    conn.execute("DELETE FROM sessions WHERE book_id=?", (book_id,))
    conn.execute("DELETE FROM books WHERE id=?", (book_id,))
    conn.commit()
    conn.close()
    for f in BOOKS_DIR.glob(f"{book_id}.*"):
        f.unlink(missing_ok=True)
    return {"ok": True}

@app.get("/api/books/{book_id}/chunks", dependencies=AUTH)
async def get_chunks(book_id: str):
    conn = get_db()
    rows = conn.execute(
        "SELECT idx, title, substr(content,1,100) as preview FROM chunks WHERE book_id=? ORDER BY idx",
        (book_id,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]

@app.get("/api/books/{book_id}/chunks/{chunk_idx}/content", dependencies=AUTH)
async def get_chunk_content(book_id: str, chunk_idx: int):
    """返回某章节完整原文"""
    conn = get_db()
    row  = conn.execute(
        "SELECT title, content FROM chunks WHERE book_id=? AND idx=?",
        (book_id, chunk_idx)
    ).fetchone()
    conn.close()
    if not row:
        raise HTTPException(404, "章节不存在")
    return {"title": row["title"], "content": row["content"]}

# ── 聊天 API ──────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    session_id: Optional[str] = None
    book_id:    str
    chunk_idx:  int = 0
    message:    Optional[str] = None

@app.post("/api/chat", dependencies=AUTH)
async def chat(req: ChatRequest):
    conn  = get_db()
    book  = conn.execute("SELECT title FROM books WHERE id=?", (req.book_id,)).fetchone()
    if not book: raise HTTPException(404, "书籍不存在")
    chunk = conn.execute("SELECT title, content FROM chunks WHERE book_id=? AND idx=?",
                         (req.book_id, req.chunk_idx)).fetchone()
    if not chunk: raise HTTPException(404, "章节不存在")

    session_id = req.session_id
    history    = []
    if session_id:
        sess = conn.execute("SELECT history FROM sessions WHERE id=?", (session_id,)).fetchone()
        if sess: history = json.loads(sess["history"])

    if not session_id:
        session_id = hashlib.md5(f"{req.book_id}{time.time()}".encode()).hexdigest()[:16]
        conn.execute(
            "INSERT INTO sessions(id,book_id,chunk_idx,history,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            (session_id, req.book_id, req.chunk_idx, "[]", int(time.time()), int(time.time()))
        )
        conn.commit()

    system = f"""你是 BOKO，一个温暖、耐心的 AI 读书老师。

你正在帮助用户阅读《{book['title']}》的"{chunk['title']}"部分。

原文内容（你的知识来源）：
---
{chunk['content'][:3000]}
---

你的工作方式：
1. 用简单、口语化的中文讲解这段内容，就像一个朋友在讲故事
2. 把复杂概念翻译成生活中能理解的例子
3. 控制在300字以内，让对话保持轻松
4. 如果用户有问题，先回答问题，再继续讲
5. 每次讲解结尾，用一句话勾起用户的好奇心，让他想继续

不要照抄原文，用你自己的话讲。"""

    user_msg = req.message or "开始讲这一段内容吧"
    history.append({"role": "user", "content": user_msg})
    reply = await call_ai(history, system)
    history.append({"role": "assistant", "content": reply})

    if len(history) > 20:
        history = history[-20:]
    conn.execute(
        "UPDATE sessions SET history=?, chunk_idx=?, updated_at=? WHERE id=?",
        (json.dumps(history, ensure_ascii=False), req.chunk_idx, int(time.time()), session_id)
    )
    conn.execute("UPDATE books SET last_read=? WHERE id=?", (int(time.time()), req.book_id))
    conn.commit()
    conn.close()
    return {"session_id": session_id, "reply": reply}

# ── 配置 API ──────────────────────────────────────────────────────
@app.get("/api/config", dependencies=AUTH)
async def get_config():
    cfg = get_ai_config()
    return {
        "provider": cfg["provider"],
        "model":    cfg["model"] or PROVIDER_DEFAULTS.get(cfg["provider"], {}).get("model", ""),
        "has_key":  bool(cfg["api_key"]),
    }

class ConfigSet(BaseModel):
    provider: str
    api_key:  str
    model:    Optional[str] = ""

@app.post("/api/config/set", dependencies=AUTH)
async def set_config(cfg: ConfigSet):
    os.environ["AI_PROVIDER"] = cfg.provider
    os.environ["AI_API_KEY"]  = cfg.api_key
    os.environ["AI_BASE_URL"] = PROVIDER_DEFAULTS.get(cfg.provider, {}).get("base_url", "")
    if cfg.model: os.environ["AI_MODEL"] = cfg.model
    return {"ok": True}

@app.get("/api/health")
async def health():
    return {"status": "ok", "name": "BOKO", "version": "1.1"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "7860")))
