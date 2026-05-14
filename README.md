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

### `auto_codex.sh`

Codex 快速配置管家，用于在 Debian、Ubuntu、macOS 上安装、更新、配置、切换 Profile 或卸载 Codex CLI。

主要功能：

- 自动识别 Debian、Ubuntu、macOS 环境。
- 使用 `nvm` 安装和管理 Node.js/npm，不使用发行版仓库里的旧版 `nodejs npm`。
- 自动检查 `curl`、`git`、`node`、`npm` 等基础依赖；缺失或 npm 版本过低时先询问再安装/更新。
- 使用 `npm install -g @openai/codex` 安装或更新 Codex CLI。
- 支持快速写入、导入或通过 `codex login` 生成 `$HOME/.codex/auth.json`。
- 支持快速写入 `$HOME/.codex/config.toml` 的常用参数，如 `approval_policy`、`sandbox_mode`、`model_reasoning_effort`。
- 支持快速配置第三方 API Provider，仅覆盖 `model`、`model_provider` 和目标 `[model_providers.<name>]`，不会清空其它 Codex 配置。
- 支持交互式写入 `[features]` 开关。
- 支持把 `auth.json` 和 `config.toml` 保存为多套 Profile，并可快速列出、切换或删除 Profile。
- 支持 `npm uninstall -g @openai/codex` 卸载 Codex CLI，并可选择是否删除 Codex 配置目录。

## 使用方式

Gost 代理脚本：

```sh
chmod +x auto_gost.sh
sudo ./auto_gost.sh
```

也可以直接从 GitHub 下载并执行：

```sh
wget -O - https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_gost.sh | sudo bash
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_gost.sh | sudo bash
```

按提示输入用户名、密码、端口和白名单 IP。密码留空时脚本会自动生成随机密码；白名单留空表示放行所有来源。

Realm 转发脚本：

```sh
chmod +x auto_realm.sh
sudo ./auto_realm.sh
```

也可以直接从 GitHub 下载并执行：

```sh
wget -O - https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_realm.sh | sudo bash
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_realm.sh | sudo bash
```

首次运行会安装 Realm 并引导新增第一条转发配置。后续再次运行脚本，可通过菜单查看、新增、删除转发配置，或重新安装/更新 Realm。

Codex 配置脚本：

```sh
chmod +x auto_codex.sh
./auto_codex.sh
```

也可以直接从 GitHub 下载并执行：

```sh
wget -O - https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_codex.sh | sudo bash
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_codex.sh | bash
```

按菜单选择安装/更新 Codex、快速设置 `auth.json`、快速设置 `config.toml`、快速配置第三方 API、配置 `[features]`、管理 Profile 或卸载 Codex。Debian/Ubuntu 上安装 `curl`、`git`、`bash`、`ca-certificates` 等基础依赖时可能需要使用 root 权限；Node.js/npm 由当前用户的 `nvm` 管理。

## 注意事项

- 脚本会安装系统依赖、写入服务文件、修改 iptables 规则，需要 root 权限运行。
- 当前脚本固定下载 Gost v2.11.5 的 Linux amd64 构建。
- 代理账号、密码和端口会写入本机系统服务配置中，请注意目标机器的文件权限和登录权限。
- 白名单留空会放行所有来源，公网机器建议配置白名单。
- `auto_realm.sh` 会把转发规则保存到 `/etc/realm/endpoints.db`，并自动渲染 `/etc/realm/config.toml`，不建议手动编辑这两个文件。
- Realm 脚本的访问白名单通过 iptables 的 `AUTO_REALM` chain 管理。某条规则设置允许 IP 后，除白名单 IP 外的来源会被拒绝访问该监听端口；白名单留空则不限制该端口来源。
- 如果目标机器已经存在 `/etc/realm/config.toml` 但没有 `endpoints.db`，脚本会先备份旧配置，并尝试导入简单的 `[[endpoints]] listen/remote` 规则；无法安全导入时会停止，避免覆盖旧配置。
- Realm 转发配置中的远端域名或 IP 会保存在目标机器配置文件中，这是转发功能所需信息。
- `auto_codex.sh` 会把 Codex 配置保存到 `${CODEX_HOME:-$HOME/.codex}`。写入 `auth.json` 或 `config.toml` 前会自动生成 `.bak.<时间戳>` 备份。
- 第三方 API 快速配置只更新 `model`、`model_provider` 和对应的 `[model_providers.<name>]` 块；`approval_policy`、`sandbox_mode`、`[features]` 等其它配置会保留。
- Codex Profile 保存在 `${CODEX_HOME:-$HOME/.codex}/profiles/<Profile 名称>`，切换 Profile 时会先备份当前生效配置，再复制目标 Profile。
- `auth.json` 可能包含 API Key 或登录令牌，请注意本机文件权限、备份文件和 Profile 目录的访问权限。

## 推送前安全检查

当前仓库内容未包含硬编码的真实代理密码、访问令牌、私钥、Cookie 或固定服务器 IP。`auto_gost.sh` 中的用户名、密码、端口和白名单均来自运行时输入或随机生成；`auto_realm.sh` 中的转发规则也来自运行时输入。

MIT License.
