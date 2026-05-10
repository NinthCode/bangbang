# bangbang

个人常用脚本集合。

## 脚本列表

### `auto_gost.sh`

全平台智能 Gost 代理管家，用于在 Alpine、Debian、Ubuntu 上交互式部署、重新配置或卸载 Gost SOCKS5 代理服务。

主要功能：

- 自动识别 Alpine/OpenRC 与 Debian、Ubuntu/systemd 环境。
- 自动安装运行所需依赖。
- 下载并安装 Gost v2.11.5。
- 交互式配置 SOCKS5 用户名、密码、端口和访问白名单。
- 自动写入系统服务并配置开机启动。
- 支持重新配置已有服务或彻底卸载服务。

### `auto_realm.sh`

Realm 转发配置管家，用于在 Alpine、Debian、Ubuntu 上安装 Realm，并通过菜单管理多条转发配置。

主要功能：

- 自动识别 Alpine/OpenRC 与 Debian、Ubuntu/systemd 环境。
- 自动下载并安装 `zhboner/realm` 最新 Linux Release。
- 创建 `/etc/realm/config.toml` 并使用 `realm -c` 启动。
- 支持查看、新增、删除多条转发配置。
- 支持 TCP 转发，单条规则可选择启用 UDP 转发。
- 支持为单条转发配置允许访问的 IPv4/CIDR；不设置时默认允许所有 IP。
- 支持重新安装/更新 Realm，或彻底卸载 Realm、服务和配置。

## 使用方式

Gost 代理脚本：

```sh
chmod +x auto_gost.sh
sudo ./auto_gost.sh
```

按提示输入用户名、密码、端口和白名单 IP。密码留空时脚本会自动生成随机密码；白名单留空表示放行所有来源。

Realm 转发脚本：

```sh
chmod +x auto_realm.sh
sudo ./auto_realm.sh
```

首次运行会安装 Realm 并引导新增第一条转发配置。后续再次运行脚本，可通过菜单查看、新增、删除转发配置，或重新安装/更新 Realm。

## 注意事项

- 脚本会安装系统依赖、写入服务文件、修改 iptables 规则，需要 root 权限运行。
- 当前脚本固定下载 Gost v2.11.5 的 Linux amd64 构建。
- 代理账号、密码和端口会写入本机系统服务配置中，请注意目标机器的文件权限和登录权限。
- 白名单留空会放行所有来源，公网机器建议配置白名单。
- `auto_realm.sh` 会把转发规则保存到 `/etc/realm/endpoints.db`，并自动渲染 `/etc/realm/config.toml`，不建议手动编辑这两个文件。
- Realm 脚本的访问白名单通过 iptables 的 `AUTO_REALM` chain 管理。某条规则设置允许 IP 后，除白名单 IP 外的来源会被拒绝访问该监听端口；白名单留空则不限制该端口来源。
- 如果目标机器已经存在 `/etc/realm/config.toml` 但没有 `endpoints.db`，脚本会先备份旧配置，并尝试导入简单的 `[[endpoints]] listen/remote` 规则；无法安全导入时会停止，避免覆盖旧配置。
- Realm 转发配置中的远端域名或 IP 会保存在目标机器配置文件中，这是转发功能所需信息。

## 推送前安全检查

当前仓库内容未包含硬编码的真实代理密码、访问令牌、私钥、Cookie 或固定服务器 IP。`auto_gost.sh` 中的用户名、密码、端口和白名单均来自运行时输入或随机生成；`auto_realm.sh` 中的转发规则也来自运行时输入。

MIT License.
