---
name: codex-deepseek-fork
description: 在 macOS 上从 Codex 桌面 App 分出一个独立的「DeepSeek App」：Dock 和菜单栏显示 DeepSeek 自己的名字和图标，可以和原 Codex 同时运行，配置目录、历史各自独立，模型配置取自 CC Switch 里的 DeepSeek（或任意 Codex provider）。原 Codex 和 ~/.codex 完全不动。当用户说「fork 一个 DeepSeek App / Codex 多开 / Codex 同时用 DeepSeek 和 OpenAI / 用 Codex App 跑 DeepSeek / 给 Codex 分身配 CC Switch」时使用。
---

# Codex → DeepSeek App 分身

## 原理
- **独立的名字和图标**：Dock 和菜单栏显示的是 app 包 Info.plist 里的名字，所以必须有一个独立的 app 包。用 APFS clone（`cp -c`）复制 Codex.app，几乎不占磁盘空间。然后改 Info.plist（名字、bundle id、图标），再做 ad-hoc 重签名。
- **独立运行**：主程序换成一个小包装脚本 `codex-fork-launcher`，它设置以下内容后再 `exec` 原程序：
  - `CODEX_HOME=~/.codex-deepseek`：配置和历史分开。
  - `CODEX_ELECTRON_USER_DATA_PATH` 加 `--user-data-dir`：Electron 和 Chromium 的数据目录分开，同时跳过单实例锁。只设环境变量不够，不加这个参数的话，Chromium 会把启动请求转交给正在运行的原 Codex。
  - `CODEX_SPARKLE_ENABLED=false`：关掉自动更新，否则 Sparkle 会把官方版装到分身上，名字又会变回去。
  - `--use-mock-keychain`：重签名后的 app 每次启动都会弹窗，索要原 Codex 的 "Codex Storage Key" 钥匙串项，加上这个参数就不会弹了。
- **CC Switch**：它的 Codex 配置只能写到一个目录，没法同时管理两个 Codex。所以这里把 CC Switch 当作**配置来源**：脚本把其中的 DeepSeek provider 导出到 `~/.codex-deepseek`。在 CC Switch 里怎么切换主 Codex，都不会影响分身。

## 前置条件
1. macOS（APFS 磁盘），已安装 Codex 桌面 App（bundle id `com.openai.codex`，可能叫 Codex.app 或 ChatGPT.app）。
2. 已安装 [CC Switch](https://github.com/farion1231/cc-switch)，并在 **Codex** 分类下添加过一个名为 `DeepSeek` 的 provider（用预设，填好 API Key 即可，**不需要**启用或切换到它）。
3. 系统自带的 `python3`。

## 安装
```bash
bash ~/.claude/skills/codex-deepseek-fork/scripts/install.sh
```
大约 10 秒。可选参数：
- `--name DeepSeek`：App 名称，同时决定 `~/.codex-<name小写>` 目录。图标规则：名称是 DeepSeek 时，安装时从 DeepSeek 官方仓库下载矢量 logo 生成图标；其他名称，或者下载失败时，用 `assets/<name>.icns`；这个文件也没有就沿用 Codex 图标
- `--provider DeepSeek`：CC Switch 里 Codex provider 的名字
- 环境变量 `CODEX_APP=/path/to/Codex.app`：自动查找失败时手动指定

同样的方法可以做 Kimi、GLM 等分身：`--name Kimi --provider Kimi`。

安装后得到：
| 东西 | 位置 |
|---|---|
| 分身 App | `/Applications/DeepSeek.app`（bundle id `local.codex-fork.deepseek`） |
| 配置目录 `CODEX_HOME` | `~/.codex-deepseek`（`config.toml`、`auth.json`、会话历史） |
| Electron/Chromium 数据 | `~/Library/Application Support/Codex (DeepSeek)` |
| 和主 Codex 共享 | `AGENTS.md`、`skills`、`prompts`、`agents`、`rules`（软链接到 `~/.codex` 里的同名项，存在才链接） |

## 日常维护
- **在 CC Switch 里改了 DeepSeek 配置**（换 Key、换模型）：执行
  `python3 ~/.claude/skills/codex-deepseek-fork/scripts/sync_config.py`，然后 ⌘Q 退出分身再打开。
- **原 Codex 更新后**：分身不会自动更新。重新跑一次 `install.sh`，它会关掉分身、用新版重新 clone，历史和配置都保留。

## 验证
1. Dock 和菜单栏显示 **DeepSeek** 和 DeepSeek 鲸鱼图标；左下角账户显示 `deepseek`，模型显示 `DeepSeek V4 Flash`；Recents 和主 Codex 不同。
2. 发一句话能正常回复。
3. 命令行快速验证（不留会话记录）：
   ```bash
   CODEX_HOME=~/.codex-deepseek /Applications/DeepSeek.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex exec --ephemeral --skip-git-repo-check "Reply with exactly one word: pong"
   ```

## 图标
`scripts/make_deepseek_icon.sh` 在安装时下载 DeepSeek 官方矢量 logo（[deepseek-ai/DeepSeek-V2 `figures/logo.svg`](https://github.com/deepseek-ai/DeepSeek-V2/blob/da42dcd40b41803c68a712ddd210eeb10e71e598/figures/logo.svg)，固定到具体 commit），取出其中的鲸鱼标志，放到 macOS 标准的白色圆角底板上，用系统自带的 `sips` 和 `iconutil` 生成 `.icns`。skill 本身不包含 DeepSeek 的 logo 文件。离线或下载失败时，退回 `assets/DeepSeek.icns`（蓝底 DS）。

## 坑（都实测踩过）
- **401 `Authentication Fails (governor)`**：CC Switch 第三方 Codex 模板里写的是 `requires_openai_auth = false`，Codex 因此不会带上 auth.json 里的 Key。`sync_config.py` 会自动改成 `true`，CC Switch 数据库不动。如果在主 Codex 里通过 CC Switch 切到 DeepSeek 也遇到 401，是同一个原因，需要在 CC Switch 里手动编辑成 `true`。
- **启动后一闪就没了，或者跳到了原 Codex**：没有传 `--user-data-dir`；或者上次异常退出后留下了 `SingletonLock`，`install.sh` 会清理掉。
- **钥匙串弹窗 "想要使用 Codex Storage Key"**：缺少 `--use-mock-keychain`。代价是分身自己的浏览器数据只用固定 key 加密，反正它的 API Key 本来就明文存在 `auth.json` 里。
- **重签名用的是 ad-hoc、不开 hardened runtime**：OpenAI 的 team 绑定 entitlements（钥匙串组、app group）在 ad-hoc 签名下无效，所以全部去掉。分身里依赖这些的功能（ChatGPT 账号登录、Computer Use 共享服务等）可能用不了；只用 API Key 跑模型不受影响。
- App 运行时会往 `~/.codex-deepseek/config.toml` 追加 `[mcp_servers.*]` 和项目信任等段落。重新同步会覆盖这些内容，下次启动会自动补回，项目信任要重新点一次。
- 用 AppleScript 测试时，中文输入法会吞掉按键，非 ASCII 字符会变成 `a`。要测就用剪贴板粘贴，或者直接用上面的 CLI 验证。

## 卸载（手动执行，会删除分身的历史）
```bash
rm -rf /Applications/DeepSeek.app ~/.codex-deepseek "$HOME/Library/Application Support/Codex (DeepSeek)"
```
