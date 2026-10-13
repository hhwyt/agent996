# agent996

一些实用的 AI agent skill，适用于 Claude Code、Codex 等支持 `SKILL.md` 的 agent。

## Skills

| Skill | 作用 |
|---|---|
| [codex-deepseek-fork](skills/codex-deepseek-fork/SKILL.md) | 在 macOS 上从 Codex 桌面 App 分出一个独立的 **DeepSeek App**：Dock 显示 DeepSeek 自己的名字和图标，可以和原 Codex 同时运行，配置和历史各自独立，模型配置取自 [CC Switch](https://github.com/farion1231/cc-switch)。 |

## 安装

把 skill 放进 agent 的 skills 目录，例如 Claude Code：

```bash
git clone https://github.com/hhwyt/agent996.git
cp -R agent996/skills/codex-deepseek-fork ~/.claude/skills/
```

然后对 agent 说「帮我从 Codex fork 一个 DeepSeek App」。也可以不经过 agent，直接运行：

```bash
bash ~/.claude/skills/codex-deepseek-fork/scripts/install.sh
```

## 说明

- DeepSeek 的 logo 不包含在本仓库中。安装时会从 DeepSeek 官方仓库 [deepseek-ai/DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2) 下载并生成图标。DeepSeek 名称和 logo 归其所有者所有。
- 本项目与 OpenAI、DeepSeek 无关，也没有获得它们的认可。

## License

[MIT](LICENSE)
