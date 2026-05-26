# Nginx Docker 离线安装包

本项目用于制作一个完全离线的 nginx Docker 安装包。目标服务器无需访问互联网，执行安装脚本后即可完成 Docker、Docker Compose、nginx 镜像、nginx 配置、systemd 服务和管理命令的部署。

## 目录结构

```text
nginx-offline-installer/
  install.sh                 # 离线安装脚本
  uninstall.sh               # 卸载脚本
  manage.sh                  # 服务管理脚本，安装后复制为 /usr/local/bin/nginx-docker
  docker-compose.yml         # nginx 容器编排文件
  package.conf               # 安装参数配置
  assets/
    docker/
      docker-x86_64.tgz      # x86_64 Docker 离线二进制包
    compose/
      docker-compose-linux-x86_64
      docker-compose-linux-x86_64.sha256
    images/
      nginx-stable.tar.gz    # nginx 镜像包
  nginx/
    nginx.conf               # nginx 主配置
    conf.d/default.conf      # 默认站点配置
    html/index.html          # 默认首页
  systemd/
    containerd.service
    docker.service
    docker.socket
    nginx-docker.service
  scripts/
    build-package.sh         # 离线打包脚本，不联网下载
```

## 离线资产

项目使用以下离线文件：

- `docker-28.1.1.tgz`：x86_64 Docker 28.1.1 静态二进制包。
- `docker-compose-linux-x86_64`：x86_64 Docker Compose 离线二进制。
- `docker-compose-linux-x86_64.sha256`：Docker Compose 官方 sha256 校验文件。
- `nginx_stable.tar.gz`：通过 `docker save` 导出的 nginx 镜像压缩包。

`scripts/build-package.sh` 会把这些文件整理到安装包内的标准位置：

- `assets/docker/docker-x86_64.tgz`
- `assets/compose/docker-compose-linux-x86_64`
- `assets/compose/docker-compose-linux-x86_64.sha256`
- `assets/images/nginx-stable.tar.gz`

安装脚本会将 Compose 安装到 `/usr/local/lib/docker/cli-plugins/docker-compose`，并创建 `/usr/local/bin/docker-compose` 软链，兼容 `docker compose` 和 `docker-compose` 两种调用方式。

## 构建离线安装包

将 `docker-28.1.1.tgz`、`docker-compose-linux-x86_64`、`docker-compose-linux-x86_64.sha256` 和 `nginx_stable.tar.gz` 放在 `nginx-offline-installer/` 的上一级目录，或提前放到 `assets/` 的标准位置，然后执行：

```bash
cd nginx-offline-installer
./scripts/build-package.sh
```

构建完成后，离线安装包会生成到：

```text
dist/nginx-offline-installer-<version>.tar.gz
```

默认命令会生成完整开发包。如果需要发布给安装人员，使用发布模式生成精简包：

```bash
./scripts/build-package.sh --release
```

发布模式会排除 `scripts/`、`.git*`、`dist/`、`.DS_Store` 等非安装文件，并将包内 `README.md` 替换为仅包含安装说明的版本。

可选环境变量：

- `PACKAGE_VERSION`：安装包版本号，默认使用当前日期时间。
- `PACKAGE_NAME`：安装包名称，默认 `nginx-offline-installer`。

## 安装

将 `dist/nginx-offline-installer-<version>.tar.gz` 复制到目标服务器，解压后执行：

```bash
sudo ./install.sh
```

安装脚本会执行以下操作：

- 检查是否为 root 用户执行。
- 检查操作系统、CPU 架构和 systemd 环境。
- 校验 `SHA256SUMS` 中记录的 Docker、Docker Compose 和 nginx 镜像资产完整性。
- 检查本地 Docker 是否可用。
- 如果 Docker 不存在，则用安装包内 Docker 28.1.1 离线安装。
- 从安装包内安装或覆盖 Docker Compose，确保使用包内版本。
- 启动并启用 Docker 相关 systemd 服务。
- 导入安装包内的 `nginx-stable.tar.gz` 镜像。
- 将 nginx 配置、站点文件和 Compose 文件部署到 `/opt/nginx-docker`。
- 注册并启用 `nginx-docker.service`。
- 安装管理命令 `/usr/local/bin/nginx-docker`。
- 安装完成后启动 nginx 容器服务。

## 服务管理

安装完成后，可使用以下命令管理服务：

```bash
sudo nginx-docker status
sudo nginx-docker start
sudo nginx-docker stop
sudo nginx-docker restart
sudo nginx-docker reload
sudo nginx-docker logs
sudo nginx-docker configtest
```

也可以直接使用 systemd：

```bash
sudo systemctl status nginx-docker.service
sudo systemctl restart nginx-docker.service
```

## 卸载

停止服务、取消注册 systemd 服务并删除管理命令：

```bash
sudo ./uninstall.sh
```

默认卸载不会删除 `/opt/nginx-docker` 中的配置、页面和日志。如果需要同时删除部署目录：

```bash
sudo REMOVE_DATA=1 ./uninstall.sh
```

卸载脚本不会删除 Docker 本身，避免影响目标服务器上其他容器。

## 常见配置

默认参数位于 `package.conf`：

- HTTP 端口：`80`
- HTTPS 端口：`443`
- 安装目录：`/opt/nginx-docker`
- systemd 服务名：`nginx-docker`
- 容器名：`nginx-server`
- nginx 镜像标签：`nginx:stable`

常见修改点：

- 修改端口：编辑 `package.conf` 中的 `HTTP_PORT` 和 `HTTPS_PORT`。
- 修改默认站点：编辑 `nginx/conf.d/default.conf`。
- 替换静态页面：替换 `nginx/html/` 下的文件。
- 配置 HTTPS：将证书放入安装后的 `/opt/nginx-docker/nginx/certs/`，并在 nginx 站点配置中引用。
- 修改安装目录或服务名：编辑 `package.conf` 后再执行安装。

## 适用环境与限制

- 目标服务器要求 Linux + systemd。
- 当前离线包只包含 x86_64 Docker 和 Docker Compose，暂不支持 aarch64。
- 目标服务器需要具备运行 Docker 的内核能力，例如 cgroups、overlayfs 等。
- 如果目标服务器已有可用 Docker，安装脚本会优先复用现有 Docker。
- 安装脚本会从离线包安装或覆盖 Docker Compose，确保使用包内版本。
- 当前不自动配置防火墙规则；如服务器启用了防火墙，需要自行放通 `80/443` 或自定义端口。
- 当前预留 HTTPS 挂载目录，但不自动签发或生成证书。
