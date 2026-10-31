# 栖息 · kindlexiping261030

把 Kindle 的休眠锁屏变成一页安静的名著摘抄：每天一句，手动可翻上一句、下一句。

首版收录 **100 部作品 × 50 条 = 5,000 条**简体中文内容：

- 70 部中国古典名著与人文经典（原文经 OpenCC 简繁转换）
- 30 部朱生豪译莎士比亚戏剧（公版译文）

每条内容都保留完整作品名、作者、章节/段落定位和来源文件校验值，不使用 AI 生成或改写原文。书目与底本边界见 [docs/内容与来源.md](docs/内容与来源.md)。

![锁屏预览](preview.png)

## 功能

- **每日一句**：按本地日期用固定哈希选择，同一天重复休眠仍是同一句，不需要联网。
- **上一句 / 下一句**：电脑阅读器可直接翻句；Kindle 解锁后可进入独立翻句页。
- **得意黑排版**：正文上方、书名作者右下方、日期时间左下方；大字距、宽留白。
- **实时日期时间**：Kindle 每次休眠时用设备本地时间重绘左下角，不显示上一次的时间。
- **离线**：5,000 条正文、得意黑字体和绘制脚本随安装包提供；锁屏在设备休眠时动态绘制，不再随包携带 5,000 张 PNG（安装包约十几 MB，而不是数百 MB）。
- **可更新**：修改内容只需替换 `data.tsv`，无需重渲染整批图片。
- **可回退**：不改 Kindle 系统文件；关闭脚本会恢复原厂锁屏，重启也会恢复原厂行为。
- **书架与搜索**：电脑阅读器可浏览 100 部作品并直接跳到任一本书。
- **一键 AI**：双击 `AI.command`，把本项目交给已登录的 Codex CLI 继续维护。

## 电脑上阅读

```sh
make serve
# 打开 http://127.0.0.1:8765/web/
```

生成当天锁屏预览：

```sh
make preview
# 输出 preview.png
```

生成静态预览图（开发用）：

```sh
make preview
# 输出 preview.png
```

## Kindle 安装

完整包下载：[Releases](https://github.com/johnson020202/kindlexiping261030/releases/latest)

详细步骤与越狱边界见 [docs/越狱与安装.md](docs/越狱与安装.md)。

1. 连接 Kindle，运行 `./tools/install_kindle.sh`（或在电脑上解压发布包后复制 `extensions/` 与 `documents/` 到 Kindle 根目录）。
2. 安全弹出后，在 Kindle 搜索框输入 `;log runme` 并回车，启用每日锁屏。
3. 打开书库里的「栖息 · 开启每日锁屏」可再次启用；「栖息 · 关闭并恢复」恢复原厂锁屏；「栖息 · 翻阅」进入解锁后的翻句页。

> 真机锁屏必须由设备上的 root 入口触发一次；从 USB 存储侧无法代替按键/搜索操作。当前已连接的设备为 **Kindle Paperwhite 3（第 7 代）**，固件 **5.16.2.1.1**，低于上游屏保引擎声明的 5.16.3 起测版本，因此本项目在该机上的锁屏生效状态必须实测后确认，见文末“验收记录”。

> **二进制必须是软浮点。** 这台设备没有 `/lib/ld-linux-armhf.so.3`，硬浮点程序会 exec 失败且无明显报错。重建用 `./tools/build_kindle_bin.sh`，它和 `tools/package_kindle.py` 都会拒绝硬浮点产物。详见 [docs/越狱与安装.md](docs/越狱与安装.md)。

### 安全边界

- 只写入 `/mnt/us/extensions/kindlexiping261030/` 和 `/mnt/us/documents/`，不修改系统分区。
- 运行时把可执行文件复制到 `/var/tmp`，不依赖 FAT 分区的执行权限。
- 不安装开机自启；重启后需要再次运行启用脚本。屏保引擎保留上游的恢复路径。
- `RUNME.sh` 是多个 Kindle 项目共用的单槽，本项目安装的是分发器，只执行自己的 `runme.d/`，不覆盖其他项目的入口；链回旧 `RUNME.sh` 默认关闭，避免触发会卸载 U 盘卷的 USB 联网脚本。

## 开发

```sh
make kindle-bin  # 交叉编译设备端二进制并校验软浮点 ABI
make content   # 重新下载/校验底本并生成 content/books.json
make kindle-data # 生成设备端动态排版数据 kindle/data.tsv
make preview   # 生成当天预览
make test      # 内容、字形、索引、脚本检查
make package   # 生成 dist/ 离线安装包（含 ABI 校验）
```

依赖：Python 3.9+、Pillow、fontTools、opencc-python-reimplemented；Node 仅用于本地静态服务器。

## 版本

当前版本见 [VERSION](VERSION)，升级记录见 [CHANGELOG.md](CHANGELOG.md)。后续每次发布按语义版本递增，并同步新的 GitHub Release：

```sh
./tools/release.sh 0.1.1 "本次修改说明"
```

发布脚本会更新版本文件、运行测试、提交、打 `v<版本>` 标签并推送。若发布失败，不会把本地改动说成已经上线。

## 字体与许可

- 得意黑 Smiley Sans © atelier-anchor，SIL Open Font License 1.1，许可证见 `assets/fonts/OFL.txt`。
- 屏保引擎基于 [chengandre/kindle-custom-screensaver](https://github.com/chengandre/kindle-custom-screensaver) v0.6.0（MIT），FBInk（GPL-3.0-or-later），见 `kindle/` 内许可文件。
- 本项目代码采用 MIT；**不主张底层古籍/译文数字底本的额外版权**。发布或再分发内容前请按 `docs/内容与来源.md` 核对来源与地区版权状态。

## 验收记录

- [x] 100 部、5,000 条，每部 50 条，全库去重
- [x] 得意黑字形覆盖检查通过
- [x] 紧凑动态锁屏数据生成（`kindle/data.tsv`）
- [x] 浏览器「上一句 / 下一句」实测生效
- [x] Kindle 原生 reader 编译为 ARM 静态可执行文件
- [ ] Kindle 真机休眠锁屏生效（需设备端执行一次 `;log runme`）
- [ ] Kindle 真机翻句触控（需解锁后打开「翻阅」）

未完成的真机项不会被“安装包已生成”替代。
