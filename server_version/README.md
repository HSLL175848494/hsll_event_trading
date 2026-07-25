# HSLL Linux 客户端网页投影

本项目不再包含服务器版业务逻辑。服务器直接运行正式 Linux Electron 客户端，再通过 Xvfb、Openbox、x11vnc 和 noVNC 把客户端窗口投影到网页。

因此信号轮询、订阅权益、UID 校验、自动下单、订单记录和界面升级全部由客户端自身负责，不需要再同步维护服务器 Worker。

## 目录结构

```text
app/client.AppImage        Linux 客户端，由 update-client.sh 安装
data/                      Electron 配置、登录状态、订单数据和 VNC 密码
logs/                      Xvfb、x11vnc、noVNC 和客户端标准输出
config.env                 投影端口和屏幕分辨率
install.sh                 安装 Linux 图形投影依赖
update-client.sh           安装或替换客户端 AppImage
start.sh / stop.sh         启动和停止
status.sh                  查看运行状态
set-password.sh            修改网页连接使用的 VNC 密码
```

旧的 Node.js、Playwright、Google Chrome、`src/`、`public/`、业务配置和网页仪表盘已经删除。

## 一、安装服务器依赖

把本项目上传到 Linux 服务器后执行：

```bash
cd server-worker
sudo bash install.sh
```

如果服务器上正在运行旧 Node/Playwright 版本，应先在覆盖旧文件之前执行旧版的 `bash stop.sh`，再上传本项目。若旧文件已经被覆盖但旧进程仍在运行，最简单可靠的处理方式是先重启服务器，再继续安装。

安装脚本只安装：

- Xvfb
- Openbox（负责最大化、焦点和模态窗口）
- x11vnc
- noVNC / websockify
- Electron AppImage 需要的基础图形库和中文字体

不再安装 Node.js、Playwright 或独立 Google Chrome。

首次安装会生成一个 8 位 VNC 密码并打印在终端中。请立即保存。

客户端通过 AppImage 的解压运行模式启动，以兼容未安装 FUSE 的精简云服务器。
由于普通用户解压出的 `chrome-sandbox` 无法具有 root setuid 权限，启动参数会禁用
Electron Chromium 沙箱。请仅运行可信的正式客户端，并严格限制 noVNC 端口的访问范围。

## 三、安装客户端

将构建出的 AppImage 上传到服务器，例如 `/tmp/hsll-client.AppImage`，然后执行：

```bash
bash update-client.sh /tmp/hsll-client.AppImage
```

脚本会停止旧进程、校验文件是 Linux ELF/AppImage，并原子替换为：

```text
app/client.AppImage
```

## 四、启动和访问

必须使用普通用户启动，不要使用 sudo：

```bash
bash start.sh
```

默认访问地址：

```text
http://服务器公网IP:8787/vnc.html?autoconnect=1&resize=scale&path=websockify
```

浏览器会要求输入 VNC 密码。连接成功后看到的就是完整 Linux Electron 客户端，操作方式与本地软件一致。

服务器重启后不会自动启动，需要再次执行 `bash start.sh`。

## 五、常用操作

```bash
# 查看状态
bash status.sh

# 停止
bash stop.sh

# 修改 VNC 密码；修改时会自动停止客户端
bash set-password.sh

# 升级客户端；升级时会自动停止客户端
bash update-client.sh /tmp/new-client.AppImage

# 静态检查项目是否仍有旧 Worker 文件或引用
bash check.sh
```

## 配置

首次安装会创建 `config.env`：

```bash
WEB_HOST=0.0.0.0
WEB_PORT=8787
SCREEN_WIDTH=1280
SCREEN_HEIGHT=720
```

默认虚拟屏幕与客户端主窗口均为 `1280×720`（16:9），客户端会铺满整个远程画面。浏览器窗口不是 16:9 时，noVNC 会按比例缩放并留出空白区域，不会拉伸客户端界面。

修改后需要停止并重新启动。

客户端数据保存在：

```text
data/xdg-config/order-reminder/
```

其中包含客户端配置、订单数据库、免责声明状态和加密后的 API Token。服务器使用 Electron 的 `basic` 密码存储后端，以便没有桌面密钥环的云服务器也能保存 Token；因此必须保护项目目录和服务器账号权限。

## 网络安全

noVNC/VNC 本身不提供 HTTPS 传输。公网使用时至少应做到：

- 云安全组只向自己的固定公网 IP 开放 TCP 8787。
- 不要开放 TCP 5900。
- 不要开放客户端内部使用的 TCP 5001。
- 更推荐将 `WEB_HOST` 改为 `127.0.0.1`，通过 SSH 隧道访问：

```bash
ssh -L 8787:127.0.0.1:8787 用户名@服务器IP
```

然后访问：

```text
http://127.0.0.1:8787/vnc.html?autoconnect=1&resize=scale&path=websockify
```

也可以在 8787 前配置带 HTTPS 和额外认证的 Nginx 反向代理。

## 卸载

停止进程并保留客户端数据：

```bash
bash uninstall.sh
```

同时删除客户端配置、登录状态、订单数据、VNC 密码和日志：

```bash
bash uninstall.sh --purge-data
```

`app/client.AppImage` 和脚本始终保留。需要彻底移除时，退出项目目录后删除整个 `server-worker` 文件夹。
