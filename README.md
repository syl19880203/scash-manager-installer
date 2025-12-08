

# SCASH Manager 一键部署脚本

这是用于部署 [SCASH Manager](https://github.com/syl19880203/scash-manager) 的一键安装 / 升级脚本。
<img width="2256" height="1062" alt="image" src="https://github.com/user-attachments/assets/d61b6e11-1191-469e-8a8e-f043fc131a3a" />

<img width="1796" height="1028" alt="image" src="https://github.com/user-attachments/assets/77e9146c-9214-4c09-9e6c-8f76560d0c6f" />

脚本视频介绍：https://youtu.be/99IEb8OfxVU

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

如果您喜欢这个程序，可以对我的项目进行打赏，支持开发者，谢谢！
钱包地址：scash1qdvdy4ea0v6dpw6kxnxgffsr2h3tsgf0f55z589

找我可以在https://t.me/+vsa1TnPuAaphM2U1
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

chmod +x install_scash_manager.sh



2. 运行脚本
sudo ./install_scash_manager.sh


然后根据提示选择：

1 → 首次安装 / 初始化部署

2 → 已安装情况下，只做升级

3 → 退出

二、SRBMiner 与 cpuminer 的支持说明

脚本会自动检测 CPU 指令集，例如：

支持 AVX2 + AES → 非常适合使用 cpuminer-scash

仅支持 AVX + AES → 可以用 cpuminer-scash，也可选 SRBMiner

不支持 AVX / AES 组合 → 不建议使用 cpuminer-scash，只推荐 SRBMiner-MULTI

典型情况：

云服务器 / 物理机，支持 AVX2：

推荐：cpuminer-scash 为主，SRBMiner 为辅。

老旧 CPU / 某些虚拟 CPU / ARM 设备（R86S、RK3568、树莓派）：

只能使用 SRBMiner-MULTI，cpuminer-scash 会报 Illegal instruction 或无法运行。

三、SRBMiner 目录约定（可选）

如果你打算使用 SRBMiner，建议在宿主机放置：

/opt/SRBMiner-Multi/SRBMiner-MULTI


脚本默认会将该目录挂载到容器内：

-v /opt/SRBMiner-Multi:/opt/SRBMiner-Multi


在 SCASH Manager 管理面板中配置 SRBMiner 路径为：

/opt/SRBMiner-Multi/SRBMiner-MULTI

四、升级方式

只要项目已经部署过，以后升级只需运行：

sudo ./install_scash_manager.sh
# 选择 2：只升级（已有环境）


或者直接调用自动生成的升级脚本：

sudo scash-manager-upgrade.sh


升级脚本会执行：

停止旧容器

git pull 拉取最新代码

重新构建镜像并打版本号

使用相同的数据目录和配置重新启动容器

五、注意事项

本脚本 不会删除你的数据目录（默认为 /opt/scash-manager-data）。

请使用 root 或 sudo 运行脚本，否则安装 Docker / 写入 /usr/local/bin 会失败。

ARM 设备（例如 R86S）不支持 x86_64 版本的 cpuminer-scash，请务必在面板中使用 SRBMiner-MULTI。



