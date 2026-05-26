# Nginx Docker 离线安装说明

本安装包用于在 Linux + systemd 的 x86_64 服务器上离线安装 nginx Docker 服务。

## 安装

解压安装包后，在安装包目录中执行：

```bash
sudo ./install.sh
```

安装完成后，服务会注册为 `nginx-docker.service`，管理命令会安装为 `/usr/local/bin/nginx-docker`。

## 服务管理

```bash
sudo nginx-docker status
sudo nginx-docker start
sudo nginx-docker stop
sudo nginx-docker restart
sudo nginx-docker reload
sudo nginx-docker logs
sudo nginx-docker configtest
```

也可以使用 systemd：

```bash
sudo systemctl status nginx-docker.service
sudo systemctl restart nginx-docker.service
```

## 安装前配置

如需调整默认端口、安装目录、服务名或容器名，可在执行安装前编辑 `package.conf`。

默认配置：

- HTTP 端口：`80`
- HTTPS 端口：`443`
- 安装目录：`/opt/nginx-docker`
- 服务名：`nginx-docker`
- 容器名：`nginx-server`

如需替换默认站点内容，可在安装前调整 `nginx/` 目录下的配置和页面文件。

## 卸载

在安装包目录中执行：

```bash
sudo ./uninstall.sh
```

默认卸载不会删除 `/opt/nginx-docker` 中的配置、页面和日志。如需同时删除部署目录：

```bash
sudo REMOVE_DATA=1 ./uninstall.sh
```

卸载脚本不会删除 Docker 本身，避免影响服务器上的其他容器。

## 环境要求

- Linux + systemd
- x86_64 架构
- root 权限
- 服务器内核需支持 Docker 运行所需能力，例如 cgroups 和 overlayfs
