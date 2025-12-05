#!/bin/bash
set -e

############################################
# 必须用 root 执行
############################################
if [[ $EUID -ne 0 ]]; then
  echo "本脚本需要 root 权限，请使用：sudo bash $0"
  exit 1
fi

############################################
#              配置区域（可修改）
############################################
APP_DIR=/root/scash-manager          # 源代码目录
DATA_DIR=/opt/scash-manager-data     # 数据目录（持久化）
IMAGE_NAME=scash-manager             # 镜像名
CONTAINER_NAME=scash-manager         # 容器名
HOST_PORT=8080                       # 对外访问端口
GIT_REPO="https://github.com/syl19880203/scash-manager.git"
UPGRADE_BIN=/usr/local/bin/scash-manager-upgrade.sh
############################################

echo "====================================="
echo "     SCASH MANAGER 管理脚本"
echo "====================================="

############################################
# 系统信息检测（OS + 架构）
############################################
OS_NAME=$(uname -s)
ARCH=$(uname -m)

echo "系统信息检测："
echo "  操作系统: $OS_NAME"
echo "  架构类型: $ARCH"
echo ""

if [[ "$OS_NAME" == "Linux" ]]; then
  if [[ "$ARCH" == "x86_64" ]]; then
    echo "✔ 检测到：Linux x86_64（常见服务器架构）"
    echo "  → 推荐矿工：cpuminer-scash（算力高） 或 SRBMiner-MULTI"
  elif [[ "$ARCH" =~ ^arm|^aarch64 ]]; then
    echo "⚠ 检测到：Linux ARM 架构（例如 R86S / RK3568 / 树莓派）"
    echo "  → cpuminer-scash 只有 x86_64 版本，在 ARM 上无法运行。"
    echo "  → 推荐矿工：SRBMiner-MULTI（支持 ARM）。"
  else
    echo "⚠ 检测到未知 Linux 架构：$ARCH"
    echo "  → 建议优先使用 SRBMiner-MULTI，兼容性更好。"
  fi
elif [[ "$OS_NAME" == "Darwin" ]]; then
  echo "⚠ 检测到：macOS（Darwin）"
  echo "  → 本一键脚本的自动安装仅支持 Linux + apt（Debian/Ubuntu）。"
  echo "  → 建议在 Linux 服务器上运行此脚本；macOS 请手动使用 Docker Desktop 部署。"
  echo "-------------------------------------"
  exit 1
else
  echo "⚠ 未知系统：$OS_NAME，本脚本仅支持 Linux + apt 环境。"
  echo "-------------------------------------"
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "⚠ 未检测到 apt，此脚本仅适用于 Debian/Ubuntu 及其衍生发行版。"
  echo "-------------------------------------"
  exit 1
fi

############################################
# CPU 指令集检测（决定 cpuminer 是否推荐）
############################################
CPU_CLASS="unknown"
ENABLE_CPUMINER="no"

if [[ -r /proc/cpuinfo ]]; then
  echo ""
  echo "正在检测 CPU 指令集（用于判断是否适合运行 cpuminer-scash）..."

  CPU_FLAGS=$(grep -m1 -i "flags" /proc/cpuinfo | cut -d: -f2- | tr ' ' '\n' | sort -u | tr '\n' ' ')
  echo "  CPU flags: $CPU_FLAGS"
  echo ""

  SUPPORT_AVX2=$(echo "$CPU_FLAGS" | grep -wo avx2 || true)
  SUPPORT_AVX=$(echo "$CPU_FLAGS" | grep -wo avx || true)
  SUPPORT_AES=$(echo "$CPU_FLAGS" | grep -wo aes || true)

  if [[ -n "$SUPPORT_AVX2" && -n "$SUPPORT_AES" ]]; then
    CPU_CLASS="high"
    ENABLE_CPUMINER="yes"
    echo "✔ 检测结果：CPU 支持 AVX2 + AES"
    echo "  → 完全兼容 cpuminer-scash（推荐使用 cpuminer 作为 CPU 矿工）。"
  elif [[ -n "$SUPPORT_AVX" && -n "$SUPPORT_AES" ]]; then
    CPU_CLASS="mid"
    ENABLE_CPUMINER="yes"
    echo "✔ 检测结果：CPU 支持 AVX + AES（但不支持 AVX2）"
    echo "  → 可以运行 cpuminer-scash，但性能略低。SRBMiner 也可以作为备选。"
  else
    CPU_CLASS="low"
    ENABLE_CPUMINER="no"
    echo "❌ 检测结果：CPU 不支持 AVX/AES 组合"
    echo "  → 不建议使用 cpuminer-scash，极大概率出现 Illegal instruction。"
    echo "  → 强烈推荐：在 scash-manager 中只使用 SRBMiner-MULTI。"
  fi
else
  echo "⚠ 无法读取 /proc/cpuinfo，跳过 CPU 指令集检测。默认不推荐 cpuminer。"
  CPU_CLASS="unknown"
  ENABLE_CPUMINER="no"
fi

echo "-------------------------------------"
if [[ "$ENABLE_CPUMINER" == "yes" ]]; then
  echo "总结："
  echo "  → 本机 CPU **适合运行 cpuminer-scash**。"
  echo "  → 你可以在面板中选择 cpuminer 或 SRBMiner。"
else
  echo "总结："
  echo "  → 本机 CPU **不适合运行 cpuminer-scash**。"
  echo "  → 请在面板中选择 **SRBMiner-MULTI** 作为矿工实现。"
fi
echo "-------------------------------------"
echo ""

############################################
# 获取本机访问 IP（默认路由网卡）
############################################
get_ip() {
  # 找到默认路由对应的网卡
  local IFACE
  IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '
    NR==1{
      for(i=1;i<=NF;i++){
        if($i=="dev"){print $(i+1); exit}
      }
    }')

  if [ -n "$IFACE" ]; then
    ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]; exit}'
  else
    # 兜底：取第一个非 127.* 的 IPv4 地址
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

############################################
# 安装 Docker + curl（如未安装）
############################################
ensure_docker_and_curl() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "  -> 未检测到 Docker，正在安装..."
    apt update
    apt install -y docker.io curl
    systemctl enable --now docker
  else
    echo "  -> Docker 已安装，检查 curl..."
    if ! command -v curl >/dev/null 2>&1; then
      apt update
      apt install -y curl
    fi
  fi
}

############################################
# 拉取 / 更新源代码
############################################
fetch_source() {
  echo "[2/4] 获取/更新源代码..."

  if [ -d "$APP_DIR/.git" ]; then
    echo "  -> 源码已存在，执行 git pull..."
    cd "$APP_DIR"
    git pull
  else
    echo "  -> 源码不存在，执行 git clone..."
    mkdir -p "$(dirname "$APP_DIR")"
    git clone "$GIT_REPO" "$APP_DIR"
    cd "$APP_DIR"
  fi
}

############################################
# 构建镜像
############################################
build_image() {
  echo "[3/4] 构建镜像..."

  VERSION=$(date +%Y%m%d-%H%M)

  docker build -t "${IMAGE_NAME}:latest" "$APP_DIR"
  docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:${VERSION}"

  echo "  -> 镜像构建完成"
  echo "     ${IMAGE_NAME}:latest"
  echo "     ${IMAGE_NAME}:${VERSION}"
}

############################################
# 启动容器（通用）
############################################
run_container() {
  echo "[4/4] 启动容器..."

  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

  mkdir -p "$DATA_DIR"

  docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    -p "${HOST_PORT}:8080" \
    -v "${DATA_DIR}":/data \
    -v /opt/SRBMiner-Multi:/opt/SRBMiner-Multi \
    -v /etc/localtime:/etc/localtime:ro \
    -v /etc/timezone:/etc/timezone:ro \
    "${IMAGE_NAME}:latest"

  echo "  -> 容器已启动: $CONTAINER_NAME"
  echo "  -> 如果你打算使用 SRBMiner，请在宿主机放置：/opt/SRBMiner-Multi/SRBMiner-MULTI"
}

############################################
# 生成独立升级脚本（方便直接调用）
############################################
generate_upgrade_bin() {
  echo "[*] 写入一键升级脚本: $UPGRADE_BIN"

  cat >"$UPGRADE_BIN" <<EOF
#!/bin/bash
set -e

if [[ \$EUID -ne 0 ]]; then
  echo "本脚本需要 root 权限，请使用：sudo bash \$0"
  exit 1
fi

APP_DIR="$APP_DIR"
DATA_DIR="$DATA_DIR"
IMAGE_NAME="$IMAGE_NAME"
CONTAINER_NAME="$CONTAINER_NAME"
HOST_PORT="$HOST_PORT"

get_ip() {
  IFACE=\$(ip route get 1.1.1.1 2>/dev/null | awk '
    NR==1{
      for(i=1;i<=NF;i++){
        if(\$i=="dev"){print \$(i+1); exit}
      }
    }')

  if [ -n "\$IFACE" ]; then
    ip -4 addr show "\$IFACE" 2>/dev/null | awk '/inet /{split(\$2,a,"/"); print a[1]; exit}'
  else
    hostname -I 2>/dev/null | awk '{print \$1}'
  fi
}

echo "====================================="
echo "   SCASH MANAGER 一键升级脚本"
echo "====================================="

if ! command -v docker >/dev/null 2>&1; then
  echo "[!] 未检测到 docker，请先安装 Docker。"
  exit 1
fi

if [ ! -d "\$APP_DIR/.git" ]; then
  echo "[!] APP_DIR 中未找到 git 仓库：\$APP_DIR"
  echo "    请确认源码目录正确，或先运行安装脚本完成初始化。"
  exit 1
fi

echo "[1/4] 停止旧容器..."
docker stop "\$CONTAINER_NAME" >/dev/null 2>&1 || true
docker rm "\$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "[2/4] 更新源码..."
cd "\$APP_DIR"
git pull

echo "[3/4] 构建新镜像..."
VERSION=\$(date +%Y%m%d-%H%M)
docker build -t "\$IMAGE_NAME:latest" "\$APP_DIR"
docker tag "\$IMAGE_NAME:latest" "\$IMAGE_NAME:\$VERSION"

echo "[4/4] 启动新容器..."
mkdir -p "\$DATA_DIR"
docker run -d \\
  --name "\$CONTAINER_NAME" \\
  --restart unless-stopped \\
  -p "\$HOST_PORT:8080" \\
  -v "\$DATA_DIR":/data \\
  -v /opt/SRBMiner-Multi:/opt/SRBMiner-Multi \\
  -v /etc/localtime:/etc/localtime:ro \\
  -v /etc/timezone:/etc/timezone:ro \\
  "\$IMAGE_NAME:latest"

SERVER_IP=\$(get_ip)

echo ""
echo "====================================="
echo "  ✅ 升级完成！SCASH Manager 已重启"
echo "-------------------------------------"
echo "  当前版本镜像: \$IMAGE_NAME:\$VERSION"
echo "  访问地址:     http://\${SERVER_IP}:\$HOST_PORT"
echo "  数据目录:     \$DATA_DIR"
echo "====================================="
echo ""
EOF

  chmod +x "$UPGRADE_BIN"
}

############################################
# 安装流程（第一次部署 / 重装）
############################################
do_install() {
  echo ">>> 选择：新安装 / 初始化部署"
  echo ""

  ensure_docker_and_curl
  fetch_source
  build_image
  run_container
  generate_upgrade_bin

  SERVER_IP=$(get_ip)

  echo ""
  echo "====================================="
  echo "  🎉 安装完成！SCASH Manager 已启动！"
  echo "-------------------------------------"
  echo "  访问地址: http://${SERVER_IP}:${HOST_PORT}"
  echo "  数据目录: ${DATA_DIR}"
  echo "  升级命令: ${UPGRADE_BIN}"
  echo "-------------------------------------"
  if [[ "$ENABLE_CPUMINER" == "yes" ]]; then
    echo "  CPU 适合 cpuminer-scash：可以在面板中使用 cpuminer 或 SRBMiner。"
  else
    echo "  CPU 不适合 cpuminer-scash：请在面板中选择 SRBMiner-MULTI 作为矿工。"
  fi
  echo "====================================="
  echo ""
}

############################################
# 升级流程（已安装情况下）
############################################
do_upgrade() {
  echo ">>> 选择：只升级（已有环境）"
  echo ""

  if [ -x "$UPGRADE_BIN" ]; then
    # 已经生成过独立升级脚本，直接调用
    "$UPGRADE_BIN"
  else
    # 没有独立升级脚本，就走内置升级流程
    echo "[i] 未找到 ${UPGRADE_BIN}，使用内置升级流程..."

    ensure_docker_and_curl

    if [ ! -d "$APP_DIR/.git" ]; then
      echo "[!] APP_DIR 中未找到 git 仓库：$APP_DIR"
      echo "    请先执行一次“新安装”以完成初始化。"
      exit 1
    fi

    echo "[1/4] 停止旧容器..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

    echo "[2/4] 更新源码..."
    cd "$APP_DIR"
    git pull

    build_image
    run_container
  fi
}

############################################
# 菜单
############################################
echo "请选择要执行的操作："
echo "  1) 新安装 / 初始化部署"
echo "  2) 只升级（已有环境）"
echo "  3) 退出"
echo -n "请输入选项 [1-3]: "
read -r choice

case "$choice" in
  1)
    do_install
    ;;
  2)
    do_upgrade
    ;;
  3)
    echo "已退出。"
    exit 0
    ;;
  *)
    echo "无效选项，已退出。"
    exit 1
    ;;
esac
