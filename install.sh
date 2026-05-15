#!/bin/bash
# ================================================================
#  BOKO - AI 读书老师  一键安装脚本
#  项目地址 : https://github.com/zhangyang-games/boko
#  全局帮助 : https://claude.ai/
# ================================================================

# ── 统一配置区 ────────────────────────────────────────────────────
readonly BOKO_PORT=7860
readonly BOKO_DATA_DIR="/root/boko_data"
readonly BOKO_CONTAINER="boko_app"
readonly BOKO_IMAGE="boko:latest"
readonly GITHUB_RAW="https://raw.githubusercontent.com/zhangyang-games/boko/main"

# ── 颜色 ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PINK='\033[38;5;213m'
PINK2='\033[38;5;219m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Banner ────────────────────────────────────────────────────────
print_banner() {
    clear
    echo ""
    echo -e "${PINK}${BOLD}"
    echo    "  ██████╗  ██████╗ ██╗  ██╗ ██████╗"
    echo    "  ██╔══██╗██╔═══██╗██║ ██╔╝██╔═══██╗"
    echo    "  ██████╔╝██║   ██║█████╔╝ ██║   ██║"
    echo    "  ██╔══██╗██║   ██║██╔═██╗ ██║   ██║"
    echo    "  ██████╔╝╚██████╔╝██║  ██╗╚██████╔╝"
    echo    "  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝"
    echo -e "${NC}"
    echo -e "${BOLD}${PINK}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${PINK}  │          📖  BOKO · AI 读书老师                    │${NC}"
    echo -e "${PINK}  │       上传书籍，让 AI 用大白话讲给你听              │${NC}"
    echo -e "${PINK}  │                       v1.0                          │${NC}"
    echo -e "${BOLD}${PINK}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# ── 工具函数 ──────────────────────────────────────────────────────
info()    { echo -e "  ${CYAN}ℹ${NC}  $*"; }
ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "  ${RED}✘${NC}  $*"; }
step()    { echo -e "\n${BOLD}${BLUE}  ── $* ──${NC}"; }
pause()   { echo ""; read -n 1 -s -r -p "  按任意键继续..."; echo ""; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "请以 root 身份运行此脚本"
        echo -e "  ${DIM}sudo bash install.sh${NC}"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        err "未检测到 Docker，请先安装 Docker"
        echo -e "  ${DIM}curl -fsSL https://get.docker.com | sh${NC}"
        exit 1
    fi
    ok "Docker 已就绪  $(docker --version | awk '{print $3}' | tr -d ',')"
}

# ── 安装核心 ──────────────────────────────────────────────────────
install_boko() {
    print_banner
    step "收集配置信息"

    # 1. Cloudflare 域名
    echo ""
    echo -e "  ${YELLOW}请输入 BOKO 的访问域名${NC}"
    echo -e "  ${DIM}（你需要提前在 Cloudflare Tunnel 里添加好这条记录）${NC}"
    echo -e "  ${DIM}例如：boko.yourdomain.com${NC}"
    echo ""
    read -p "  域名: " BOKO_DOMAIN
    if [ -z "$BOKO_DOMAIN" ]; then
        err "域名不能为空"
        exit 1
    fi

    # 2. AI 服务商
    echo ""
    echo -e "  ${YELLOW}选择 AI 服务商${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} DeepSeek      ${DIM}← 国产，便宜好用，首选${NC}"
    echo -e "  ${GREEN}2)${NC} Google Gemini  ${DIM}← 有免费额度${NC}"
    echo -e "  ${GREEN}3)${NC} Groq           ${DIM}← 完全免费，速度极快${NC}"
    echo -e "  ${GREEN}4)${NC} OpenRouter     ${DIM}← 一个Key用多种模型${NC}"
    echo -e "  ${GREEN}5)${NC} Claude         ${DIM}← Anthropic，质量最高${NC}"
    echo -e "  ${GREEN}6)${NC} OpenAI / GPT   ${DIM}← 经典选择${NC}"
    echo ""
    read -p "  请选择 [1-6]: " PROVIDER_CHOICE

    case "$PROVIDER_CHOICE" in
        1) AI_PROVIDER="deepseek";   AI_BASE_URL="https://api.deepseek.com/v1";                             AI_MODEL="deepseek-chat" ;;
        2) AI_PROVIDER="gemini";     AI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"; AI_MODEL="gemini-2.0-flash" ;;
        3) AI_PROVIDER="groq";       AI_BASE_URL="https://api.groq.com/openai/v1";                          AI_MODEL="llama-3.3-70b-versatile" ;;
        4) AI_PROVIDER="openrouter"; AI_BASE_URL="https://openrouter.ai/api/v1";                            AI_MODEL="meta-llama/llama-3.3-70b-instruct:free" ;;
        5) AI_PROVIDER="claude";     AI_BASE_URL="https://api.anthropic.com/v1";                            AI_MODEL="claude-3-5-haiku-20241022" ;;
        6) AI_PROVIDER="openai";     AI_BASE_URL="https://api.openai.com/v1";                               AI_MODEL="gpt-4o-mini" ;;
        *) AI_PROVIDER="deepseek";   AI_BASE_URL="https://api.deepseek.com/v1";                             AI_MODEL="deepseek-chat" ;;
    esac

    # 3. API Key
    echo ""
    echo -e "  ${YELLOW}请输入 ${AI_PROVIDER} 的 API Key${NC}"
    read -p "  API Key: " AI_API_KEY
    if [ -z "$AI_API_KEY" ]; then
        err "API Key 不能为空"
        exit 1
    fi

    # 4. 可选：自定义模型
    echo ""
    echo -e "  ${DIM}默认模型：${AI_MODEL}（直接回车使用默认）${NC}"
    read -p "  自定义模型（留空跳过）: " CUSTOM_MODEL
    if [ -n "$CUSTOM_MODEL" ]; then
        AI_MODEL="$CUSTOM_MODEL"
    fi

    # 确认
    echo ""
    echo -e "${BOLD}${PINK}  ── 安装确认 ─────────────────────────────────────────${NC}"
    echo -e "  域名    : ${GREEN}https://${BOKO_DOMAIN}${NC}"
    echo -e "  AI      : ${GREEN}${AI_PROVIDER} / ${AI_MODEL}${NC}"
    echo -e "  数据目录: ${GREEN}${BOKO_DATA_DIR}${NC}"
    echo -e "  端口    : ${GREEN}${BOKO_PORT}（仅本地，通过 Cloudflare 访问）${NC}"
    echo ""
    read -p "  确认安装？[y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[yY]$ ]] || { info "已取消"; exit 0; }

    step "准备环境"

    check_docker
    mkdir -p "$BOKO_DATA_DIR"
    ok "数据目录已就绪：${BOKO_DATA_DIR}"

    step "下载程序文件"

    mkdir -p /tmp/boko_build
    cd /tmp/boko_build

    # 下载源文件
    for f in server.py index.html Dockerfile requirements.txt; do
        echo -ne "  下载 ${f}... "
        if curl -fsSL "${GITHUB_RAW}/${f}" -o "${f}" 2>/dev/null; then
            echo -e "${GREEN}✔${NC}"
        else
            echo -e "${RED}✘${NC}"
            err "下载失败，请检查网络或 GitHub 地址"
            exit 1
        fi
    done

    step "构建 Docker 镜像"
    info "首次构建需要 2-5 分钟，请耐心等待..."
    echo ""
    if docker build -t "$BOKO_IMAGE" . ; then
        ok "镜像构建成功"
    else
        err "镜像构建失败，请查看上方错误信息"
        exit 1
    fi

    step "启动容器"

    # 停掉旧容器
    docker rm -f "$BOKO_CONTAINER" 2>/dev/null && info "已清理旧容器"

    docker run -d \
        --name "$BOKO_CONTAINER" \
        --restart unless-stopped \
        -p "127.0.0.1:${BOKO_PORT}:7860" \
        -v "${BOKO_DATA_DIR}:/data" \
        -e "AI_PROVIDER=${AI_PROVIDER}" \
        -e "AI_API_KEY=${AI_API_KEY}" \
        -e "AI_BASE_URL=${AI_BASE_URL}" \
        -e "AI_MODEL=${AI_MODEL}" \
        -e "BOKO_DATA=/data" \
        "$BOKO_IMAGE"

    if [ $? -eq 0 ]; then
        ok "容器启动成功"
    else
        err "容器启动失败"
        exit 1
    fi

    step "配置 Cloudflare Tunnel"

    TUNNEL_CONFIG="/root/.cloudflared/config.yml"
    if [ -f "$TUNNEL_CONFIG" ]; then
        # 检查是否已有此域名
        if grep -q "$BOKO_DOMAIN" "$TUNNEL_CONFIG" 2>/dev/null; then
            warn "Tunnel 配置中已存在 ${BOKO_DOMAIN}，跳过"
        else
            # 在 ingress 列表末尾（404规则之前）插入新条目
            INGRESS_LINE="- hostname: ${BOKO_DOMAIN}\n  service: http://localhost:${BOKO_PORT}"
            sed -i "/- service: http_status:404/i\\${INGRESS_LINE}" "$TUNNEL_CONFIG"
            systemctl restart cloudflared 2>/dev/null || true
            ok "Cloudflare Tunnel 已更新，已重启服务"
        fi
    else
        warn "未找到 Cloudflare Tunnel 配置文件"
        echo -e "  ${DIM}请手动在 Cloudflare Tunnel 中添加：${NC}"
        echo -e "  ${DIM}  主机名: ${BOKO_DOMAIN}${NC}"
        echo -e "  ${DIM}  服务:   http://localhost:${BOKO_PORT}${NC}"
    fi

    # 等待服务就绪
    echo ""
    echo -ne "  等待服务启动"
    for i in $(seq 1 15); do
        sleep 1
        echo -ne "."
        if curl -s "http://localhost:${BOKO_PORT}/api/health" &>/dev/null; then
            echo ""
            break
        fi
    done

    # 验证
    if curl -s "http://localhost:${BOKO_PORT}/api/health" | grep -q "ok"; then
        echo ""
        echo -e "${BOLD}${GREEN}"
        echo "  ╔══════════════════════════════════════════════╗"
        echo "  ║                                              ║"
        echo "  ║    🎉  BOKO 安装成功！                      ║"
        echo "  ║                                              ║"
        echo "  ╚══════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "  ${BOLD}访问地址${NC}：${GREEN}https://${BOKO_DOMAIN}${NC}"
        echo -e "  ${BOLD}AI 引擎${NC} ：${GREEN}${AI_PROVIDER} / ${AI_MODEL}${NC}"
        echo -e "  ${BOLD}数据目录${NC}：${GREEN}${BOKO_DATA_DIR}${NC}"
        echo ""
        echo -e "  ${DIM}管理命令：${NC}"
        echo -e "  ${DIM}  docker logs -f ${BOKO_CONTAINER}   查看日志${NC}"
        echo -e "  ${DIM}  docker restart ${BOKO_CONTAINER}   重启服务${NC}"
        echo -e "  ${DIM}  bash install.sh                    重新配置${NC}"

        # 保存凭证
        _save_credential
    else
        err "服务启动可能有问题，请查看日志："
        echo -e "  ${DIM}docker logs ${BOKO_CONTAINER}${NC}"
    fi

    # 清理构建文件
    rm -rf /tmp/boko_build
}

_save_credential() {
    local CRED_FILE="/root/.boko_credentials"
    cat > "$CRED_FILE" << EOF
# BOKO 安装信息
BOKO_DOMAIN=${BOKO_DOMAIN}
AI_PROVIDER=${AI_PROVIDER}
AI_MODEL=${AI_MODEL}
BOKO_PORT=${BOKO_PORT}
BOKO_DATA_DIR=${BOKO_DATA_DIR}
INSTALLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    chmod 600 "$CRED_FILE"
    ok "凭证已保存到 ${CRED_FILE}"
}

# ── 卸载 ─────────────────────────────────────────────────────────
uninstall_boko() {
    echo ""
    warn "这将删除 BOKO 容器和镜像（数据目录 ${BOKO_DATA_DIR} 不会删除）"
    read -p "  确认卸载？[y/N] " CONFIRM
    [[ "$CONFIRM" =~ ^[yY]$ ]] || { info "已取消"; return; }

    docker rm -f "$BOKO_CONTAINER" 2>/dev/null && ok "容器已删除"
    docker rmi "$BOKO_IMAGE" 2>/dev/null && ok "镜像已删除"
    ok "卸载完成（书籍数据保留在 ${BOKO_DATA_DIR}）"
}

# ── 查看状态 ──────────────────────────────────────────────────────
show_status() {
    echo ""
    local CRED_FILE="/root/.boko_credentials"
    if [ -f "$CRED_FILE" ]; then
        source "$CRED_FILE"
        echo -e "  ${BOLD}域名${NC}  : ${GREEN}https://${BOKO_DOMAIN}${NC}"
        echo -e "  ${BOLD}AI  ${NC}  : ${GREEN}${AI_PROVIDER} / ${AI_MODEL}${NC}"
        echo -e "  ${BOLD}安装${NC}  : ${DIM}${INSTALLED_AT}${NC}"
    fi
    echo ""
    if docker inspect "$BOKO_CONTAINER" &>/dev/null; then
        local STATUS=$(docker inspect --format='{{.State.Status}}' "$BOKO_CONTAINER")
        if [ "$STATUS" = "running" ]; then
            echo -e "  容器状态: ${GREEN}● 运行中${NC}"
        else
            echo -e "  容器状态: ${RED}■ 已停止${NC}"
        fi
    else
        echo -e "  容器状态: ${DIM}未安装${NC}"
    fi
    echo ""
}

# ── 主菜单 ────────────────────────────────────────────────────────
main_menu() {
    print_banner

    # 显示当前状态
    if docker inspect "$BOKO_CONTAINER" &>/dev/null; then
        local STATUS=$(docker inspect --format='{{.State.Status}}' "$BOKO_CONTAINER")
        if [ "$STATUS" = "running" ]; then
            echo -e "  ${GREEN}● 运行中${NC}"
        else
            echo -e "  ${RED}■ 已停止${NC}"
        fi
        local CRED_FILE="/root/.boko_credentials"
        [ -f "$CRED_FILE" ] && source "$CRED_FILE" && echo -e "  ${DIM}https://${BOKO_DOMAIN}  ·  ${AI_PROVIDER}${NC}"
    else
        echo -e "  ${DIM}尚未安装${NC}"
    fi

    echo ""
    echo -e "${PINK2}  ─────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${PINK}i)${NC}  📦 安装 BOKO"
    echo -e "  ${PINK}s)${NC}  📊 查看状态"
    echo -e "  ${PINK}l)${NC}  📋 查看日志"
    echo -e "  ${PINK}r)${NC}  🔄 重启服务"
    echo -e "  ${PINK}u)${NC}  ⬆  更新到最新版"
    echo -e "  ${RED}x)  🗑  卸载${NC}"
    echo -e "  ${DIM}q)  退出${NC}"
    echo ""

    read -p "  👉 请选择: " CHOICE
    case "$CHOICE" in
        i|I) install_boko ;;
        s|S) show_status; pause ;;
        l|L) docker logs --tail=50 -f "$BOKO_CONTAINER" 2>/dev/null || err "容器未运行" ;;
        r|R) docker restart "$BOKO_CONTAINER" && ok "已重启" || err "重启失败"; pause ;;
        u|U) update_boko ;;
        x|X) uninstall_boko; pause ;;
        q|Q) echo -e "${PINK}  再见！去读书吧 📚${NC}"; exit 0 ;;
        *) warn "无效选项"; sleep 1 ;;
    esac
}

update_boko() {
    step "更新 BOKO"
    mkdir -p /tmp/boko_build && cd /tmp/boko_build
    for f in server.py index.html Dockerfile requirements.txt; do
        curl -fsSL "${GITHUB_RAW}/${f}" -o "${f}" 2>/dev/null && ok "下载 ${f}" || { err "下载 ${f} 失败"; exit 1; }
    done

    # 重新构建镜像
    docker build -t "$BOKO_IMAGE" . && ok "镜像更新成功" || { err "构建失败"; exit 1; }

    # 重启容器（保留原有环境变量）
    local OLD_ENV=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$BOKO_CONTAINER" 2>/dev/null | grep -E "^(AI_|BOKO_)" | sed 's/^/-e /' | tr '\n' ' ')
    docker rm -f "$BOKO_CONTAINER" 2>/dev/null

    eval docker run -d \
        --name "$BOKO_CONTAINER" \
        --restart unless-stopped \
        -p "127.0.0.1:${BOKO_PORT}:7860" \
        -v "${BOKO_DATA_DIR}:/data" \
        $OLD_ENV \
        "$BOKO_IMAGE"

    ok "更新完成，BOKO 已重启"
    rm -rf /tmp/boko_build
    pause
}

# ── 入口 ─────────────────────────────────────────────────────────
check_root

# 支持直接传参快速操作
case "${1:-}" in
    install)   install_boko ;;
    status)    show_status ;;
    logs)      docker logs -f "$BOKO_CONTAINER" ;;
    restart)   docker restart "$BOKO_CONTAINER" ;;
    uninstall) uninstall_boko ;;
    *)
        while true; do
            main_menu
        done
        ;;
esac
