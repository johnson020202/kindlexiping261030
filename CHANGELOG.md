# Changelog

## 0.1.2 — 2026-10-31

修复 0.1.1 部署后仍不生效的路径错误。真机 `install.log` 证实 ABI 修复已生效
（日志首行输出 `device: soft-float (armel)`），随后卡在下一条：

```
toggle.sh: .: line 26: can't open '.../kindlexiping261030/blanket_renderers.sh': No such file or directory
```

- **修复：`toggle.sh` 与 `daemon.sh` 的 source 路径。** 两个脚本都写成
  `. "$BASE/blanket_renderers.sh"`，但该文件实际位于 `scripts/` 子目录，
  于是脚本刚启动就退出，屏幕无任何变化。
- **修复：`daemon.sh` 的 `BASE` 定义。** 它取脚本自身目录（即 `scripts/`），
  导致 `$BASE/state/`、`$BASE/bin/` 全部指向不存在的位置；改为取父目录。
- **修复：`toggle.sh` 启动 `daemon.sh` 的路径**，同样少了 `scripts/`。
- **新增：缺文件时明确报错。** `toggle.sh` 在启动时检查依赖文件，缺失即在屏幕上
  显示「安装不完整 / 缺少：xxx」，并写 `launcher.log`，不再静默失败。
- **新增：`install.log` 分段。** 每次运行写入 `===== run <时间> =====`，多次重试
  不再混在一起；`toggle.sh` 返回非零时会记录 `FAILED: ...`。
- **新增两条测试防回退**：`test_script_paths_exist_in_deployed_layout` 校验每个
  `$BASE` 引用都能在部署布局中解析；`test_sourcing_includes_scripts_dir` 直接
  锁定本次具体回归。两条都已实测能在注入原 bug 时失败并指出行号。

## 0.1.1 — 2026-10-31

修复在真机（Kindle Paperwhite 3，固件 5.16.2.1.1）上完全无法运行的问题。

- **修复：二进制 ABI 不匹配。** 0.1.0 打包的 4 个程序全是硬浮点（`e_flags=0x5000400`），而该机是软浮点 armel 用户态、没有 `/lib/ld-linux-armhf.so.3`，因此全部无法 exec，且不产生任何可见错误。
  - `daily-index`、`kindlexiping-reader` 改用 arm-linux-musleabi 重新编译为**全静态**二进制，无动态段、无未定义符号，彻底摆脱设备 glibc 2.20 的版本约束。
  - `screensaver_shield` 必须动态链接设备自带的 `libX11.so.6`，改按 glibc 2.20 构建，实测仅要求 `GLIBC_2.4`/`GLIBC_2.12`。
  - `fbink_hf` 改为直接采用越狱载荷中的 `kindlepw2/bin/fbink`，与设备上正在运行的 `/mnt/us/libkh/bin/fbink` 逐字节一致。
  - 移除 `screensaver_draw`：从未被任何脚本调用，绘图由 `draw.sh` 直接调 fbink 完成。
- **新增：ABI 双闸校验。** `tools/build_kindle_bin.sh` 编译后校验 `e_flags`，`tools/package_kindle.py` 打包前再校验一次；任一处发现硬浮点即报错退出，不会再让不兼容的二进制进入发布包。
- **修复：`RUNME.sh` 独占导致静默失败。** `RUNME.sh` 是多个 Kindle 项目共用的单槽，此前直接覆盖它，并且 `exec >>` 指向未创建目录时会让脚本静默退出。
  - 改为分发器：只遍历执行 `extensions/kindlexiping261030/runme.d/*.sh`，启用逻辑移入 `runme.d/10-enable.sh`。
  - 链回旧 `RUNME.sh` 默认关闭：设备上留存的版本常是 USB 联网引导脚本，`useUsbForNetwork` 会卸载安装正在写入的 U 盘卷。需要时用 `KINDLE_RUNME_CHAIN=` 显式开启。
- **修复：错误提示不可见。** `toggle.sh` 增加 ABI 自检，二进制与设备不符时在屏幕上提示「二进制架构不符」，而不是只显示「未能启用」。
- **文档：** 记录机型实测信息（PW3 第 7 代、armv7l、软浮点）、ABI 判据、重建方式与验收边界。

## 0.1.0 — 2026-10-31

- 首版：70 部中国古典作品 + 30 部朱生豪译莎士比亚，共 100 部、5,000 条，每部 50 条。
- 1072×1448 得意黑锁屏，正文、书名作者、日期时间分区排版。
- 每日按日期确定性选择；上一句、下一句独立浏览。
- Kindle 休眠事件屏保、原生触控翻句、恢复原厂屏保。
- 电脑端书架、搜索、键盘/触摸翻句、锁屏 PNG 导出。
- 完整离线图片包、安装/卸载说明、一键 AI 入口。
