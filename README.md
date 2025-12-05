# SCASH Manager 一键部署脚本

这是用于部署 [SCASH Manager](https://github.com/syl19880203/scash-manager) 的一键安装 / 升级脚本。

脚本特点：

- 自动检测系统（Linux + x86_64 / ARM）
- 自动检测 CPU 指令集（是否支持 AVX / AVX2 / AES）
- 根据 CPU 能力自动提示是否适合使用 `cpuminer-scash`
- 一键完成：
  - 安装 Docker + curl（Debian / Ubuntu 系）
  - 克隆或更新 `scash-manager` 源码
  - 构建 Docker 镜像并打版本号标签
  - 启动容器（挂载数据目录、时区信息、SRBMiner 路径）
  - 生成独立升级脚本：`/usr/local/bin/scash-manager-upgrade.sh`
- 内置菜单：
  - `1) 新安装 / 初始化部署`
  - `2) 只升级（已有环境）`

---

## 使用环境要求

- 操作系统：**Linux（Debian / Ubuntu 及其衍生版）**
- 包管理器：`apt`
- 需要 root 权限（或 `sudo`）

脚本会自动安装：

- `docker.io`
- `curl`

---

## 一、快速开始（推荐给普通用户）

### 1. 下载脚本

```bash
curl -sSL https://raw.githubusercontent.com/syl19880203/scash-manager-installer/main/install_scash_manager.sh -o install_scash_manager.sh
chmod +x install_scash_manager.sh
