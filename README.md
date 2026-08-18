# DJI 4G VoHive Docker

将大疆 4G 模块一代（Quectel EG25-G）的 USB ID 修改为 `2c7c:0125`，然后使用已发布的 Docker 镜像运行 VoHive。

> Docker 镜像仅支持 `linux/amd64`。

## 修改 USB ID

在能直接识别模块的 Debian/Ubuntu 主机或 Linux 虚拟机中执行：

```bash
git clone https://github.com/Nayacco/dji-4g-vohive-docker.git
cd dji-4g-vohive-docker

sudo apt-get update
sudo apt-get install -y usbutils socat kmod udev
sudo bash scripts/set-usb-id.sh
```

需要恢复为大疆的 `2ca3:4006` 时执行：

```bash
sudo bash scripts/restore-usb-id.sh
```

## Docker 配置与启动

使用 GitHub Packages 中发布的镜像，无需自行构建：

```text
ghcr.io/nayacco/dji-4g-vohive-docker:latest
```

首次启动前创建 `vohive/config.yaml`：

```bash
mkdir -p vohive/{data,logs}
vi vohive/config.yaml
```

配置文件内容如下，至少修改 `web.password`：

```yaml
bark:
  enabled: false
  group: vohive
  icon: ""
  level: active
  urls: []
email:
  enabled: false
  from_address: ""
  password: ""
  smtp_host: ""
  smtp_port: 0
  to_addresses: []
  username: ""
feishu:
  app_id: ""
  app_secret: ""
  chat_ids: []
  enabled: false
pushplus:
  channel: wechat
  enabled: false
  token: ""
  topic: ""
qq:
  app_id: ""
  app_secret: ""
  direct_ids: ""
  enabled: false
  group_ids: ""
server:
  port: :7575
telegram:
  admin_id: 0
  base_url: ""
  bot_token: ""
  chat_id: 0
  enabled: false
  proxy: ""
web:
  password: admin
  username: admin
webhook:
  enabled: false
  headers: {}
  retry_max: 3
  secret: ""
  text_template: "{{device_label}} {{text}}"
  timeout_ms: 5000
  urls: []
devices: []
```

保存后限制配置文件权限：

```bash
chmod 600 vohive/config.yaml
```

直接启动容器；本地没有镜像时 Docker 会自动拉取：

```bash
docker run -d \
  --name vohive \
  --restart unless-stopped \
  --network host \
  --privileged \
  -e TZ=Asia/Shanghai \
  -v /dev:/dev \
  -v "$PWD/vohive/config.yaml:/opt/vohive/config/config.yaml" \
  -v "$PWD/vohive/data:/opt/vohive/data" \
  -v "$PWD/vohive/logs:/opt/vohive/logs" \
  ghcr.io/nayacco/dji-4g-vohive-docker:latest
```

查看日志：

```bash
docker logs -f vohive
```

访问 `http://<Linux 主机 IP>:7575`，用户名为 `admin`，密码为配置文件中的 `web.password`。

停止或再次启动：

```bash
docker stop vohive
docker start vohive
```

> 容器需要直接访问 4G 模块，因此使用 host network、privileged 和 `/dev`。建议仅在专用 Linux 主机或虚拟机中运行。
