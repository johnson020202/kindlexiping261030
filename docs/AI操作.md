# 一键 AI 操作本项目

## 双击

在 Finder 中双击 `AI.command`。它会打开已登录的 Codex CLI，并把项目根目录和 `AI_BOOTSTRAP.md` 作为工作上下文。

## 命令行

```sh
./ai.sh                 # 打开交互式 Codex，并载入项目约束
./ai.sh "给内容库增加 10 部..."  # 直接把任务交给 Codex
```

脚本不会把 API key、密码或 GitHub token 写入项目。它只调用你本机已经登录的 `codex` CLI；如果未安装，会提示安装地址。

## AI 的工作约束

见 `AGENTS.md` 与 `AI_BOOTSTRAP.md`：

- 不编造名著原文；新增内容必须能从底本定位。
- 不把未在真机验证的锁屏/触控写成“已通过”。
- 修改后运行 `make test`；修改排版数据后运行 `make kindle-data` 和 `make package`。
- 发版必须递增 `VERSION`、更新 `CHANGELOG.md`、打 `v<版本>` 标签并上传对应 Release 资产。
- 不提交 `source-cache/`、`build/`、密钥、Kindle 日志或含个人信息的文件。
