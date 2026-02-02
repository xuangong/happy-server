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
if [ "$AUTO_YES" = false ] && [ ! -t 0 ]; then
    exec < /dev/tty
fi

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
        read REPO_URL
        REPO_URL=${REPO_URL:-$DEFAULT_REPO}

        echo -n "请输入安装目录 [$DEFAULT_INSTALL_DIR]: "
        read INSTALL_DIR
        INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
    fi

    if [ -d "$INSTALL_DIR" ]; then
        log_warn "目录 $INSTALL_DIR 已存在"
        if [ "$AUTO_YES" = true ]; then
            log_info "使用现有目录"
            return 0
        else
            echo -n "是否删除并重新克隆? [y/N]: "
            read CONFIRM
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

# 生成随机密钥
generate_secret() {
    openssl rand -base64 32
}

# 配置环境变量
configure_environment() {
    echo ""
    log_info "配置服务参数"

    # 生成 HANDY_MASTER_SECRET
    DEFAULT_MASTER_SECRET=$(generate_secret)

    if [ "$AUTO_YES" = true ]; then
        MASTER_SECRET="$DEFAULT_MASTER_SECRET"
        LISTEN_PORT=8080
    else
        echo ""
        echo "HANDY_MASTER_SECRET 用于签发认证 token"
        echo -n "请输入 HANDY_MASTER_SECRET [$DEFAULT_MASTER_SECRET]: "
        read MASTER_SECRET
        MASTER_SECRET=${MASTER_SECRET:-$DEFAULT_MASTER_SECRET}

        # 监听端口
        echo -n "请输入监听端口 [8080]: "
        read LISTEN_PORT
        LISTEN_PORT=${LISTEN_PORT:-8080}
    fi

    # 保存配置到 .env 文件
    cat > "$INSTALL_DIR/.env" << EOF
# Happy Server 配置
HANDY_MASTER_SECRET=$MASTER_SECRET
LISTEN_PORT=$LISTEN_PORT

# 数据库
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/handy
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=handy

# Redis
REDIS_URL=redis://redis:6379

# S3/MinIO
S3_HOST=minio
S3_PORT=9000
S3_USE_SSL=false
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin
S3_BUCKET=happy
S3_PUBLIC_URL=http://localhost:9000/happy

# Server
PORT=3005
NODE_ENV=production

# Webapp
WEBAPP_SERVER_URL=http://localhost:$LISTEN_PORT
WEBAPP_PORT=8888
EOF

    log_success "环境配置已保存到 $INSTALL_DIR/.env"
}

# 创建 docker-compose.yaml
create_docker_compose() {
    log_info "创建 docker-compose.yaml..."

    cat > "$INSTALL_DIR/docker-compose.yaml" << 'EOF'
services:
    postgres:
        image: postgres:16-alpine
        container_name: happy-postgres
        restart: always
        environment:
            POSTGRES_USER: ${POSTGRES_USER:-postgres}
            POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
            POSTGRES_DB: ${POSTGRES_DB:-handy}
        volumes:
            - ./data/postgres:/var/lib/postgresql/data
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U postgres -d handy"]
            interval: 5s
            timeout: 5s
            retries: 5

    redis:
        image: redis:7-alpine
        container_name: happy-redis
        restart: always
        command: redis-server --appendonly yes
        volumes:
            - ./data/redis:/data
        healthcheck:
            test: ["CMD", "redis-cli", "ping"]
            interval: 5s
            timeout: 5s
            retries: 5

    minio:
        image: minio/minio
        container_name: happy-minio
        restart: always
        command: server /data --console-address ":9001"
        environment:
            MINIO_ROOT_USER: ${S3_ACCESS_KEY:-minioadmin}
            MINIO_ROOT_PASSWORD: ${S3_SECRET_KEY:-minioadmin}
        volumes:
            - ./data/minio:/data
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
            mc alias set local http://minio:9000 minioadmin minioadmin;
            mc mb -p local/happy || true;
            mc anonymous set download local/happy;
            exit 0;
            "
        restart: "no"

    happy-server:
        build:
            context: .
            dockerfile: Dockerfile
        container_name: happy-server
        restart: always
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
            DATABASE_URL: ${DATABASE_URL:-postgresql://postgres:postgres@postgres:5432/handy}
            REDIS_URL: ${REDIS_URL:-redis://redis:6379}
            S3_HOST: ${S3_HOST:-minio}
            S3_PORT: ${S3_PORT:-9000}
            S3_USE_SSL: ${S3_USE_SSL:-false}
            S3_ACCESS_KEY: ${S3_ACCESS_KEY:-minioadmin}
            S3_SECRET_KEY: ${S3_SECRET_KEY:-minioadmin}
            S3_BUCKET: ${S3_BUCKET:-happy}
            S3_PUBLIC_URL: ${S3_PUBLIC_URL:-http://localhost:9000/happy}
            PORT: ${PORT:-3005}
            NODE_ENV: ${NODE_ENV:-production}
            HANDY_MASTER_SECRET: ${HANDY_MASTER_SECRET}
            METRICS_ENABLED: "true"
            METRICS_PORT: "9090"
        ports:
            - "${LISTEN_PORT:-8080}:3005"
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
                - EXPO_PUBLIC_HAPPY_SERVER_URL=${WEBAPP_SERVER_URL:-http://localhost:8080}
        container_name: happy-webapp
        ports:
            - "${WEBAPP_PORT:-8888}:80"
        restart: always
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

# 生成测试账户和 access.key
generate_access_key() {
    echo ""
    log_info "生成认证凭证"

    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10

    # 检查服务是否正常
    MAX_RETRIES=30
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        if curl -s "http://localhost:${LISTEN_PORT}/health" | grep -q "ok"; then
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

    # 检查是否安装了 node
    if ! command -v node &> /dev/null; then
        log_warn "Node.js 未安装，跳过自动生成 access.key"
        log_info "请手动生成 access.key 或使用 happy-cli auth login"
        return 0
    fi

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
    const port = process.env.LISTEN_PORT || 80;
    const serverUrl = `http://localhost:${port}`;

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

    # 运行脚本生成 access.key
    ACCESS_KEY_CONTENT=$(LISTEN_PORT=$LISTEN_PORT node "$TEMP_SCRIPT" 2>/dev/null)
    rm -f "$TEMP_SCRIPT"

    if [ -n "$ACCESS_KEY_CONTENT" ]; then
        # 询问保存位置
        DEFAULT_HAPPY_DIR="$HOME/.happy"
        if [ "$AUTO_YES" = true ]; then
            HAPPY_DIR="$DEFAULT_HAPPY_DIR"
        else
            echo -n "请输入 Happy CLI 配置目录 [$DEFAULT_HAPPY_DIR]: "
            read HAPPY_DIR
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

    # 检查健康状态
    if curl -s "http://localhost:${LISTEN_PORT}/" | grep -q "Welcome to Happy Server"; then
        log_success "✓ 基础连接正常"
    else
        log_error "✗ 基础连接失败"
    fi

    if curl -s "http://localhost:${LISTEN_PORT}/health" | grep -q "ok"; then
        log_success "✓ 健康检查通过"
    else
        log_error "✗ 健康检查失败"
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
    echo "  API Server: http://localhost:${LISTEN_PORT}/"
    echo "  Web App:    http://localhost:8888/"
    echo "  健康检查:   http://localhost:${LISTEN_PORT}/health"
    echo ""
    echo "常用命令:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose logs -f happy-server  # 查看 server 日志"
    echo "  docker compose logs -f happy-webapp  # 查看 webapp 日志"
    echo "  docker compose restart               # 重启服务"
    echo "  docker compose down                  # 停止服务"
    echo "  docker compose up -d                 # 启动服务"
    echo ""
    echo "备份数据:"
    echo "  cp -r $INSTALL_DIR/data /path/to/backup/"
    echo ""
    echo "CLI 连接:"
    echo "  HAPPY_SERVER_URL=http://localhost:${LISTEN_PORT} happy daemon start"
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
        read CONFIRM
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

    start_services
    generate_access_key
    verify_installation
    show_summary
}

# 运行主函数
main "$@"
