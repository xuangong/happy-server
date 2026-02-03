#!/bin/bash

#############################################
# Happy Server 自动化安装脚本
# 适用于全新 Linux 机器
#
# 用法:
#   交互式安装:
#     curl -fsSL https://raw.githubusercontent.com/xuangong/happy-server/main/install.sh -o install.sh && sudo bash install.sh
#
#   非交互式安装 (使用默认值):
#     curl -fsSL https://raw.githubusercontent.com/xuangong/happy-server/main/install.sh -o install.sh && sudo bash install.sh -y
#
#############################################

set -e

# 解析命令行参数
AUTO_YES=false
while getopts "yh" opt; do
    case $opt in
        y) AUTO_YES=true ;;
        h)
            echo "用法: $0 [-y] [-h]"
            echo "  -y  非交互式安装，使用默认值"
            echo "  -h  显示帮助"
            exit 0
            ;;
        *) ;;
    esac
done

# 确保有交互式输入（支持 curl | bash 方式）
# 定义从 tty 读取的函数
read_tty() {
    if [ -t 0 ]; then
        read "$@"
    else
        read "$@" < /dev/tty
    fi
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 或有 sudo 权限
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            log_error "需要 root 权限或 sudo，请以 root 用户运行"
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    log_info "检测到操作系统: $OS $OS_VERSION"
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker 已安装: $(docker --version)"
        return 0
    fi

    log_info "正在安装 Docker..."

    case $OS in
        ubuntu|debian)
            $SUDO apt-get update
            $SUDO apt-get install -y ca-certificates curl gnupg
            $SUDO install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
            $SUDO apt-get update
            $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            $SUDO yum install -y yum-utils
            $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $SUDO yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            log_warn "未知的操作系统，尝试使用通用安装脚本..."
            curl -fsSL https://get.docker.com | $SUDO sh
            ;;
    esac

    # 启动 Docker 并设置开机自启
    $SUDO systemctl start docker
    $SUDO systemctl enable docker

    # 将当前用户添加到 docker 组
    if [ -n "$SUDO_USER" ]; then
        $SUDO usermod -aG docker $SUDO_USER
    elif [ "$EUID" -ne 0 ]; then
        $SUDO usermod -aG docker $USER
    fi

    log_success "Docker 安装完成"
}

# 安装 Git
install_git() {
    if command -v git &> /dev/null; then
        log_success "Git 已安装: $(git --version)"
        return 0
    fi

    log_info "正在安装 Git..."

    case $OS in
        ubuntu|debian)
            $SUDO apt-get update
            $SUDO apt-get install -y git
            ;;
        centos|rhel|fedora)
            $SUDO yum install -y git
            ;;
        *)
            log_error "请手动安装 Git"
            exit 1
            ;;
    esac

    log_success "Git 安装完成"
}

# 安装 curl 和其他基础工具
install_basic_tools() {
    log_info "检查基础工具..."

    case $OS in
        ubuntu|debian)
            $SUDO apt-get update
            $SUDO apt-get install -y curl wget openssl jq
            ;;
        centos|rhel|fedora)
            $SUDO yum install -y curl wget openssl jq
            ;;
    esac

    log_success "基础工具已就绪"
}

# 克隆 Happy Server 代码仓库
clone_happy_server_repository() {
    echo ""
    log_info "配置代码仓库"

    # 默认值
    DEFAULT_REPO="https://github.com/xuangong/happy-server.git"
    DEFAULT_INSTALL_DIR="/opt/happy-server"

    if [ "$AUTO_YES" = true ]; then
        REPO_URL="$DEFAULT_REPO"
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    else
        echo -n "请输入 Git 仓库地址 [$DEFAULT_REPO]: "
        read_tty -r REPO_URL
        REPO_URL=${REPO_URL:-$DEFAULT_REPO}

        echo -n "请输入安装目录 [$DEFAULT_INSTALL_DIR]: "
        read_tty -r INSTALL_DIR
        INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    fi

    if [ -d "$INSTALL_DIR" ]; then
        log_warn "目录 $INSTALL_DIR 已存在"
        if [ "$AUTO_YES" = true ]; then
            log_info "使用现有目录"
            return 0
        else
            echo -n "是否删除并重新克隆? [y/N]: "
            read_tty -r CONFIRM
            if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
                $SUDO rm -rf "$INSTALL_DIR"
            else
                log_info "使用现有目录"
                return 0
            fi
        fi
    fi

    log_info "正在克隆仓库..."
    $SUDO git clone "$REPO_URL" "$INSTALL_DIR"

    # 设置目录权限
    $SUDO chown -R $(id -u):$(id -g) "$INSTALL_DIR"

    log_success "代码仓库克隆完成: $INSTALL_DIR"
}

# 克隆 Happy 仓库（用于构建 webapp）
clone_happy_repository() {
    echo ""
    log_info "克隆 Happy 仓库（用于构建 webapp）"

    HAPPY_REPO="https://github.com/xuangong/happy.git"
    HAPPY_DIR="/opt/happy"

    if [ -d "$HAPPY_DIR" ]; then
        log_info "Happy 仓库已存在: $HAPPY_DIR"
        return 0
    fi

    log_info "正在克隆 Happy 仓库..."
    $SUDO git clone "$HAPPY_REPO" "$HAPPY_DIR"
    $SUDO chown -R $(id -u):$(id -g) "$HAPPY_DIR"

    log_success "Happy 仓库克隆完成: $HAPPY_DIR"
}

# 创建数据目录
create_data_directories() {
    log_info "创建数据目录..."

    DATA_DIR="$INSTALL_DIR/data"

    mkdir -p "$DATA_DIR/postgres"
    mkdir -p "$DATA_DIR/redis"
    mkdir -p "$DATA_DIR/minio"

    # 设置适当的权限
    chmod -R 755 "$DATA_DIR"

    log_success "数据目录已创建: $DATA_DIR"
    log_info "备份时请复制此目录: $DATA_DIR"
}

# 生成 URL 安全的随机密码（只包含字母和数字）
generate_secret() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# 生成用于数据库连接的安全密码（避免 URL 特殊字符）
generate_db_password() {
    openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24
}

# 配置环境变量
configure_environment() {
    echo ""
    log_info "配置服务参数"

    # 生成随机密码备用（使用 URL 安全字符）
    RANDOM_MASTER_SECRET=$(generate_secret)
    RANDOM_POSTGRES_PASSWORD=$(generate_db_password)
    RANDOM_REDIS_PASSWORD=$(generate_db_password)
    RANDOM_MINIO_PASSWORD=$(generate_db_password)

    if [ "$AUTO_YES" = true ]; then
        MASTER_SECRET="$RANDOM_MASTER_SECRET"
        POSTGRES_PASSWORD="$RANDOM_POSTGRES_PASSWORD"
        REDIS_PASSWORD="$RANDOM_REDIS_PASSWORD"
        MINIO_ROOT_USER="minio"
        MINIO_ROOT_PASSWORD="$RANDOM_MINIO_PASSWORD"
        LISTEN_PORT=8443
        SERVER_HOST="xianliao.de5.net"
        CLOUDFLARE_API_TOKEN=""
    else
        echo ""
        log_info "=== 安全配置 ==="
        echo ""
        echo "选项说明: 1=使用默认值  2=生成随机值  3=自定义输入"
        echo ""

        # HANDY_MASTER_SECRET
        echo "HANDY_MASTER_SECRET 用于签发认证 token"
        echo "  1) 默认: (无默认值)"
        echo "  2) 随机生成"
        echo "  3) 自定义输入"
        echo -n "请选择 [2]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-2}
        case $CHOICE in
            2) MASTER_SECRET="$RANDOM_MASTER_SECRET"; echo "  → $MASTER_SECRET" ;;
            3) echo -n "  请输入: "; read_tty -r MASTER_SECRET ;;
            *) MASTER_SECRET="$RANDOM_MASTER_SECRET"; echo "  → $MASTER_SECRET" ;;
        esac

        # PostgreSQL 密码
        echo ""
        echo "PostgreSQL 密码"
        echo "  1) 默认: postgres"
        echo "  2) 随机生成"
        echo "  3) 自定义输入"
        echo -n "请选择 [2]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-2}
        case $CHOICE in
            1) POSTGRES_PASSWORD="postgres"; echo "  → postgres" ;;
            2) POSTGRES_PASSWORD="$RANDOM_POSTGRES_PASSWORD"; echo "  → $POSTGRES_PASSWORD" ;;
            3) echo -n "  请输入: "; read_tty -r POSTGRES_PASSWORD ;;
            *) POSTGRES_PASSWORD="$RANDOM_POSTGRES_PASSWORD"; echo "  → $POSTGRES_PASSWORD" ;;
        esac

        # Redis 密码
        echo ""
        echo "Redis 密码"
        echo "  1) 默认: redis"
        echo "  2) 随机生成"
        echo "  3) 自定义输入"
        echo -n "请选择 [2]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-2}
        case $CHOICE in
            1) REDIS_PASSWORD="redis"; echo "  → redis" ;;
            2) REDIS_PASSWORD="$RANDOM_REDIS_PASSWORD"; echo "  → $REDIS_PASSWORD" ;;
            3) echo -n "  请输入: "; read_tty -r REDIS_PASSWORD ;;
            *) REDIS_PASSWORD="$RANDOM_REDIS_PASSWORD"; echo "  → $REDIS_PASSWORD" ;;
        esac

        # MinIO 用户名
        echo ""
        echo "MinIO 用户名"
        echo "  1) 默认: minio"
        echo "  2) 自定义输入"
        echo -n "请选择 [1]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-1}
        case $CHOICE in
            1) MINIO_ROOT_USER="minio"; echo "  → minio" ;;
            2) echo -n "  请输入: "; read_tty -r MINIO_ROOT_USER ;;
            *) MINIO_ROOT_USER="minio"; echo "  → minio" ;;
        esac

        # MinIO 密码
        echo ""
        echo "MinIO 密码"
        echo "  1) 默认: minioadmin"
        echo "  2) 随机生成"
        echo "  3) 自定义输入"
        echo -n "请选择 [2]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-2}
        case $CHOICE in
            1) MINIO_ROOT_PASSWORD="minioadmin"; echo "  → minioadmin" ;;
            2) MINIO_ROOT_PASSWORD="$RANDOM_MINIO_PASSWORD"; echo "  → $MINIO_ROOT_PASSWORD" ;;
            3) echo -n "  请输入: "; read_tty -r MINIO_ROOT_PASSWORD ;;
            *) MINIO_ROOT_PASSWORD="$RANDOM_MINIO_PASSWORD"; echo "  → $MINIO_ROOT_PASSWORD" ;;
        esac

        echo ""
        log_info "=== 网络配置 ==="
        echo ""

        # 服务器域名
        echo "服务器域名 (用于 HTTPS 证书和 webapp 连接)"
        echo "  1) 默认: xianliao.de5.net"
        echo "  2) 自定义输入"
        echo -n "请选择 [1]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-1}
        case $CHOICE in
            1) SERVER_HOST="xianliao.de5.net"; echo "  → xianliao.de5.net" ;;
            2) echo -n "  请输入: "; read_tty -r SERVER_HOST ;;
            *) SERVER_HOST="xianliao.de5.net"; echo "  → xianliao.de5.net" ;;
        esac

        # 监听端口
        echo ""
        echo "HTTPS 监听端口"
        echo "  1) 默认: 8443"
        echo "  2) 自定义输入"
        echo -n "请选择 [1]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-1}
        case $CHOICE in
            1) LISTEN_PORT="8443"; echo "  → 8443" ;;
            2) echo -n "  请输入: "; read_tty -r LISTEN_PORT ;;
            *) LISTEN_PORT="8443"; echo "  → 8443" ;;
        esac

        # Cloudflare API Token
        echo ""
        log_info "=== Cloudflare 配置 (用于 HTTPS 证书) ==="
        echo ""
        echo "获取方式:"
        echo "  1. 登录 https://dash.cloudflare.com"
        echo "  2. 点击右上角头像 → My Profile → API Tokens"
        echo "  3. Create Token → Edit zone DNS 模板"
        echo "  4. Zone Resources 选择你的域名"
        echo ""
        echo "Cloudflare API Token"
        echo "  1) 稍后配置 (跳过)"
        echo "  2) 现在输入"
        echo -n "请选择 [1]: "
        read_tty -r CHOICE
        CHOICE=${CHOICE:-1}
        case $CHOICE in
            1) CLOUDFLARE_API_TOKEN=""; echo "  → 已跳过，请稍后在 .env 中配置" ;;
            2)
                echo -n "  请输入 Cloudflare API Token: "
                read_tty -r CLOUDFLARE_API_TOKEN
                if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
                    log_warn "Token 为空，请稍后在 .env 中配置"
                else
                    echo "  → Token 已设置 (${#CLOUDFLARE_API_TOKEN} 字符)"
                fi
                ;;
            *) CLOUDFLARE_API_TOKEN="" ;;
        esac
    fi

    # 保存配置到 .env 文件
    cat > "$INSTALL_DIR/.env" << EOF
# Happy Server 配置
HANDY_MASTER_SECRET=$MASTER_SECRET
LISTEN_PORT=$LISTEN_PORT
SERVER_HOST=$SERVER_HOST

# 数据库
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=handy

# Redis
REDIS_PASSWORD=$REDIS_PASSWORD

# S3/MinIO
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
S3_PUBLIC_URL=https://${SERVER_HOST}:${LISTEN_PORT}/files

# Cloudflare (用于 HTTPS 证书)
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
EOF

    echo ""
    log_success "配置已保存到 $INSTALL_DIR/.env"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请保存以下配置信息（不会再次显示）:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "HANDY_MASTER_SECRET: $MASTER_SECRET"
    echo "PostgreSQL 密码:     $POSTGRES_PASSWORD"
    echo "Redis 密码:          $REDIS_PASSWORD"
    echo "MinIO 用户名:        $MINIO_ROOT_USER"
    echo "MinIO 密码:          $MINIO_ROOT_PASSWORD"
    echo "服务器域名:          $SERVER_HOST"
    echo "HTTPS 端口:          $LISTEN_PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 创建 docker-compose.yaml
create_docker_compose() {
    log_info "创建 docker-compose.yaml..."

    cat > "$INSTALL_DIR/docker-compose.yaml" << 'EOF'
version: '3.8'

services:
    postgres:
        image: postgres:16-alpine
        container_name: happy-postgres
        environment:
            POSTGRES_USER: ${POSTGRES_USER:-postgres}
            POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
            POSTGRES_DB: ${POSTGRES_DB:-handy}
        volumes:
            - ./data/postgres:/var/lib/postgresql/data
        expose:
            - "5432"
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-handy}"]
            interval: 5s
            timeout: 5s
            retries: 5

    redis:
        image: redis:7-alpine
        container_name: happy-redis
        command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
        volumes:
            - ./data/redis:/data
        expose:
            - "6379"
        healthcheck:
            test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
            interval: 5s
            timeout: 5s
            retries: 5

    minio:
        image: minio/minio
        container_name: happy-minio
        command: server /data --console-address ":9001"
        environment:
            MINIO_ROOT_USER: ${MINIO_ROOT_USER}
            MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
        volumes:
            - ./data/minio:/data
        expose:
            - "9000"
            - "9001"
        healthcheck:
            test: ["CMD", "mc", "ready", "local"]
            interval: 5s
            timeout: 5s
            retries: 5

    minio-init:
        image: minio/mc
        container_name: happy-minio-init
        depends_on:
            minio:
                condition: service_started
        entrypoint: >
            /bin/sh -c "
            sleep 5;
            mc alias set local http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD};
            mc mb -p local/happy || true;
            mc anonymous set download local/happy;
            exit 0;
            "

    happy-server:
        build:
            context: .
            dockerfile: Dockerfile
        container_name: happy-server
        depends_on:
            postgres:
                condition: service_healthy
            redis:
                condition: service_healthy
            minio:
                condition: service_started
            minio-init:
                condition: service_completed_successfully
        environment:
            DATABASE_URL: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-handy}
            REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
            S3_HOST: minio
            S3_PORT: "9000"
            S3_USE_SSL: "false"
            S3_ACCESS_KEY: ${MINIO_ROOT_USER}
            S3_SECRET_KEY: ${MINIO_ROOT_PASSWORD}
            S3_BUCKET: happy
            S3_PUBLIC_URL: ${S3_PUBLIC_URL:-http://localhost:9000/happy}
            PORT: "3005"
            NODE_ENV: production
            HANDY_MASTER_SECRET: ${HANDY_MASTER_SECRET}
            WEBAPP_URL: https://${SERVER_HOST}:${LISTEN_PORT}
            METRICS_ENABLED: "true"
            METRICS_PORT: "9090"
        expose:
            - "3005"
        ports:
            - "9090:9090"
        healthcheck:
            test: ["CMD", "wget", "-q", "--spider", "http://localhost:3005/health"]
            interval: 10s
            timeout: 5s
            retries: 3
            start_period: 30s

    happy-webapp:
        build:
            context: /opt/happy
            dockerfile: Dockerfile.webapp
            args:
                EXPO_PUBLIC_HAPPY_SERVER_URL: https://${SERVER_HOST}:${LISTEN_PORT}
        container_name: happy-webapp
        expose:
            - "80"
        depends_on:
            - happy-server
        restart: always

    caddy:
        image: slothcroissant/caddy-cloudflaredns:latest
        container_name: happy-caddy
        restart: always
        ports:
            - "${LISTEN_PORT:-8443}:${LISTEN_PORT:-8443}"
        environment:
            CLOUDFLARE_API_TOKEN: ${CLOUDFLARE_API_TOKEN}
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile:ro
            - ./data/caddy:/data
            - ./data/caddy_config:/config
        depends_on:
            - happy-server
            - happy-webapp

volumes:
    postgres_data:
    redis_data:
    minio_data:
EOF

    log_success "docker-compose.yaml 已创建"
}

# 创建 Dockerfile
create_dockerfile() {
    log_info "检查 Dockerfile..."

    if [ ! -f "$INSTALL_DIR/Dockerfile" ]; then
        cat > "$INSTALL_DIR/Dockerfile" << 'EOF'
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
RUN yarn generate

FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

COPY --from=builder /app/tsconfig.json ./tsconfig.json
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/sources ./sources
COPY --from=builder /app/prisma ./prisma

EXPOSE 3005

COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

CMD ["/app/docker-entrypoint.sh"]
EOF
        log_success "Dockerfile 已创建"
    else
        log_info "Dockerfile 已存在，跳过"
    fi
}

# 创建 docker-entrypoint.sh
create_entrypoint() {
    log_info "检查 docker-entrypoint.sh..."

    if [ ! -f "$INSTALL_DIR/docker-entrypoint.sh" ]; then
        cat > "$INSTALL_DIR/docker-entrypoint.sh" << 'EOF'
#!/bin/sh
set -e

echo "Running database migrations..."
npx prisma migrate deploy

echo "Starting Happy Server..."
exec yarn start
EOF
        chmod +x "$INSTALL_DIR/docker-entrypoint.sh"
        log_success "docker-entrypoint.sh 已创建"
    else
        log_info "docker-entrypoint.sh 已存在，跳过"
    fi
}

# 创建 Caddyfile
create_caddyfile() {
    log_info "创建 Caddyfile..."

    cat > "$INSTALL_DIR/Caddyfile" << EOF
${SERVER_HOST}:${LISTEN_PORT} {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    # API 路由 → happy-server
    handle /v1/* {
        reverse_proxy happy-server:3005
    }

    handle /health {
        reverse_proxy happy-server:3005
    }

    handle /socket.io/* {
        reverse_proxy happy-server:3005 {
            header_up Connection {header.Connection}
            header_up Upgrade {header.Upgrade}
        }
    }

    # 静态文件 (MinIO) → 可选，如果需要通过 Caddy 代理
    handle /files/* {
        reverse_proxy minio:9000
    }

    # 其他所有请求 → happy-webapp (前端)
    handle {
        reverse_proxy happy-webapp:80
    }
}
EOF

    log_success "Caddyfile 已创建"
}

# 生成测试账户和 access.key
generate_access_key() {
    echo ""
    log_info "生成认证凭证"

    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10

    # 检查服务是否正常 (直接检查 happy-server 容器)
    MAX_RETRIES=30
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        if docker exec happy-server wget -q --spider http://localhost:3005/health 2>/dev/null; then
            log_success "服务已启动"
            break
        fi
        RETRY=$((RETRY + 1))
        log_info "等待服务启动... ($RETRY/$MAX_RETRIES)"
        sleep 2
    done

    if [ $RETRY -eq $MAX_RETRIES ]; then
        log_error "服务启动超时，请手动检查"
        return 1
    fi

    # 使用 Node.js 生成密钥对并创建账户
    log_info "生成密钥对并创建账户..."

    # 创建临时脚本生成密钥
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << 'NODEJS_SCRIPT'
const crypto = require('crypto');
const https = require('https');
const http = require('http');

// 简化的 tweetnacl 签名实现 (使用 Node.js crypto)
function generateSignKeyPair() {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
    return {
        publicKey: publicKey.export({ type: 'spki', format: 'der' }).slice(-32),
        secretKey: Buffer.concat([
            privateKey.export({ type: 'pkcs8', format: 'der' }).slice(-32),
            publicKey.export({ type: 'spki', format: 'der' }).slice(-32)
        ])
    };
}

function sign(message, secretKey) {
    const privateKey = crypto.createPrivateKey({
        key: Buffer.concat([
            Buffer.from('302e020100300506032b657004220420', 'hex'),
            secretKey.slice(0, 32)
        ]),
        format: 'der',
        type: 'pkcs8'
    });
    return crypto.sign(null, message, privateKey);
}

async function main() {
    // 直接连接 happy-server 容器 (端口 3005)
    const serverUrl = 'http://happy-server:3005';

    // 生成签名密钥对
    const keyPair = generateSignKeyPair();
    const publicKeyBase64 = Buffer.from(keyPair.publicKey).toString('base64');

    // 生成 challenge
    const challenge = crypto.randomBytes(32);
    const challengeBase64 = challenge.toString('base64');

    // 签名
    const signature = sign(challenge, keyPair.secretKey);
    const signatureBase64 = signature.toString('base64');

    // 发送认证请求
    const postData = JSON.stringify({
        publicKey: publicKeyBase64,
        challenge: challengeBase64,
        signature: signatureBase64
    });

    return new Promise((resolve, reject) => {
        const req = http.request(`${serverUrl}/v1/auth`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    const response = JSON.parse(data);
                    if (response.success && response.token) {
                        // 生成加密用的 secret (32 bytes)
                        const secret = crypto.randomBytes(32).toString('base64');

                        const accessKey = {
                            secret: secret,
                            token: response.token
                        };

                        console.log(JSON.stringify(accessKey, null, 2));
                        resolve();
                    } else {
                        reject(new Error('认证失败: ' + data));
                    }
                } catch (e) {
                    reject(e);
                }
            });
        });

        req.on('error', reject);
        req.write(postData);
        req.end();
    });
}

main().catch(err => {
    console.error('Error:', err.message);
    process.exit(1);
});
NODEJS_SCRIPT

    # 运行脚本生成 access.key (使用 Docker 网络连接 happy-server)
    ACCESS_KEY_CONTENT=$(cat "$TEMP_SCRIPT" | docker run --rm -i --network happy-server_default node:20-alpine node 2>/dev/null)
    rm -f "$TEMP_SCRIPT"

    if [ -n "$ACCESS_KEY_CONTENT" ]; then
        # 询问保存位置
        DEFAULT_HAPPY_DIR="$HOME/.happy"
        if [ "$AUTO_YES" = true ]; then
            HAPPY_DIR="$DEFAULT_HAPPY_DIR"
        else
            echo -n "请输入 Happy CLI 配置目录 [$DEFAULT_HAPPY_DIR]: "
            read_tty -r HAPPY_DIR
            HAPPY_DIR=${HAPPY_DIR:-$DEFAULT_HAPPY_DIR}
        fi

        mkdir -p "$HAPPY_DIR"
        echo "$ACCESS_KEY_CONTENT" > "$HAPPY_DIR/access.key"
        chmod 600 "$HAPPY_DIR/access.key"

        log_success "access.key 已保存到 $HAPPY_DIR/access.key"
        echo ""
        echo "access.key 内容:"
        echo "$ACCESS_KEY_CONTENT"
        echo ""
        log_warn "请妥善保管此密钥，它用于加密你的所有消息"
    else
        log_warn "无法自动生成 access.key，请手动创建"
    fi
}

# 启动服务
start_services() {
    log_info "启动服务..."

    cd "$INSTALL_DIR"

    # 使用 docker compose (新版) 或 docker-compose (旧版)
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_error "未找到 docker compose 命令"
        exit 1
    fi

    # 构建并启动
    log_info "构建镜像（首次可能需要几分钟）..."
    $COMPOSE_CMD build

    log_info "启动容器..."
    $COMPOSE_CMD up -d

    log_success "服务已启动"
}

# 验证安装
verify_installation() {
    echo ""
    log_info "验证安装..."

    sleep 5

    # 检查健康状态 (直接检查 happy-server 容器)
    if docker exec happy-server wget -q -O - http://localhost:3005/ 2>/dev/null | grep -q "Welcome to Happy Server"; then
        log_success "✓ 基础连接正常"
    else
        log_warn "✗ 基础连接检查失败 (服务可能仍在启动)"
    fi

    if docker exec happy-server wget -q -O - http://localhost:3005/health 2>/dev/null | grep -q "ok"; then
        log_success "✓ 健康检查通过"
    else
        log_warn "✗ 健康检查失败 (服务可能仍在启动)"
    fi

    # 检查 HTTPS 是否正常 (通过 Caddy)
    if curl -sk "https://localhost:${LISTEN_PORT}/health" 2>/dev/null | grep -q "ok"; then
        log_success "✓ HTTPS 代理正常"
    else
        log_warn "✗ HTTPS 代理检查失败 (证书可能仍在获取)"
    fi

    # 显示容器状态
    echo ""
    log_info "容器状态:"
    cd "$INSTALL_DIR"
    docker compose ps 2>/dev/null || docker-compose ps
}

# 显示安装摘要
show_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Happy Server 安装完成！${NC}"
    echo "=============================================="
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo "数据目录: $INSTALL_DIR/data"
    echo ""
    echo "服务地址:"
    echo "  Web App:    https://${SERVER_HOST}:${LISTEN_PORT}/"
    echo "  API Server: https://${SERVER_HOST}:${LISTEN_PORT}/v1/"
    echo "  健康检查:   https://${SERVER_HOST}:${LISTEN_PORT}/health"
    echo ""
    echo "常用命令:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose logs -f happy-server  # 查看 server 日志"
    echo "  docker compose logs -f happy-webapp  # 查看 webapp 日志"
    echo "  docker compose logs -f caddy         # 查看 Caddy 日志"
    echo "  docker compose restart               # 重启服务"
    echo "  docker compose down                  # 停止服务"
    echo "  docker compose up -d                 # 启动服务"
    echo ""
    echo "备份数据:"
    echo "  cp -r $INSTALL_DIR/data /path/to/backup/"
    echo ""
    echo "CLI 连接:"
    echo "  HAPPY_SERVER_URL=https://${SERVER_HOST}:${LISTEN_PORT} happy daemon start"
    echo ""
    if [ -f "$HAPPY_DIR/access.key" ]; then
        echo "认证凭证: $HAPPY_DIR/access.key"
        echo ""
    fi
    echo "=============================================="
}

# 主函数
main() {
    echo ""
    echo "=============================================="
    echo "       Happy Server 自动化安装脚本"
    echo "=============================================="
    echo ""

    check_sudo
    detect_os

    echo ""
    echo "即将安装 Happy Server，需要以下组件:"
    echo "  - Docker"
    echo "  - Docker Compose"
    echo "  - Git"
    echo ""

    if [ "$AUTO_YES" = true ]; then
        log_info "使用 -y 参数，跳过确认"
    else
        echo -n "是否继续? [Y/n]: "
        read_tty -r CONFIRM
        if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
            log_info "安装已取消"
            exit 0
        fi
    fi

    install_basic_tools
    install_git
    install_docker

    # 需要重新加载 docker 组权限
    if [ -n "$SUDO" ]; then
        log_warn "Docker 已安装，但可能需要重新登录才能无 sudo 使用"
    fi

    clone_happy_server_repository
    clone_happy_repository
    create_data_directories
    configure_environment
    create_docker_compose
    create_dockerfile
    create_entrypoint
    create_caddyfile

    start_services
    generate_access_key
    verify_installation
    show_summary
}

# 运行主函数
main "$@"
