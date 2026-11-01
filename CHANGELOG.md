# Changelog

## 0.1.5 — 2026-11-01

两个改动：唤醒后自动回到界面（不再停在锁屏海报），以及每次息屏随机换一张海报。
两者均已在真机（PW3，5.16.2.1.1）上确认。

### 唤醒后停在海报

锁屏海报由 FBInk 直接写入 `/dev/fb0`，位于 X 服务之下；X 仍认为自己的窗口内容完好，
唤醒时不产生任何重绘请求，电子墨水屏保留最后写入的像素。每次触摸只让框架认定一小块
区域变脏，因此表现为「点一点、唤醒一点」。

真机取证（休眠帧与唤醒帧逐字节比对）：155 万像素中仅左上角 114×26 的时钟区域
（922 像素，0.06%）不同。时钟是唯一被判定为脏的区域，所以也是唯一被重绘的区域。

原先负责重绘的 `xredraw` 与 `screensaver_shield` 在设备上从未运行过：

- `screensaver_shield` 的 `main()` 第一句即向 stderr 打印 `starting`，而 stderr 正是
  重定向进 `custom_ss.log` 的；该日志全文没有这条记录，说明它未执行到 `main()`。
- 每次 `outOfScreenSaver` 之后紧跟的 `Segmentation fault` 即为其崩溃留痕。
- 二者是当时项目中仅有的**动态链接**产物（链接时以桩 `libX11.so.6` 占位）；其余能
  正常工作的 `fbink`、`daily-index`、`kindlexiping-reader` 全是静态 musl。

- **新增 `xscreen`（静态 musl，`native/xscreen.c`）。** 不链接 libX11，直接通过本地
  socket 讲 X11 协议。唤醒时先把一个全屏 override-redirect 窗口映射再销毁，让服务器
  向被它遮挡的窗口发 Expose；然后校验结果。旧实现额外遍历窗口树发 `ClearArea`，那一步
  在真机上把界面擦白了：中部墨量 10.91% → 0.00%，只剩状态栏与底部导航条。原因是
  Kindle 主界面不像普通 X 客户端那样响应 Expose 重绘，被清掉的区域就永久留白。
  **`ClearArea` 已移除，不得再用于此设备。**
- **唤醒结果可证伪。** 判定同时要求「画面与海报的整帧差异 ≥ 5%」且「中部墨量
  ≥ 0.5%」。只比对前者会把纯白屏误判成恢复成功，从而跳过兜底；只比对后者则会把
  仍停在海报判成正常。
- **兜底走框架自身接口。** 重绘判定失败（返回 2）时调用
  `com.lab126.appmgrd start app://com.lab126.booklet.home` 让框架把界面带回来。
- **移除 `xredraw`、`screensaver_shield`。** 构建、安装与打包脚本都会清理，避免旧包
  残留的可执行文件被误当成现行实现。
- **修复 `kindlexiping-reader` 退出时的重绘。** 原先调用 `/mnt/us` 上的程序，而该分区
  是 `noexec` 的 FAT，根本无法执行；改为调用 `/var/tmp/kindlexiping-bin/xscreen`。

### 守护进程活不过「点击启用」

点「开启每日锁屏」后屏幕显示「已启用」，但休眠仍回落原生海报，`custom_ss.log` 里
没有任何新实例的启动记录。

- 根因：`toggle.sh` 用 `&` 把守护进程挂在启动它的 shell 下，而 Kindle 执行文档用的是
  短命 shell，显示完提示即退出，整个进程组收到挂断信号；`daemon.sh` 里的
  `trap 'cleanup; exit 0' HUP` 使守护进程随之自我清理。
- 修法：SIGHUP 不再致命（只记日志继续运行）；用 `setsid` 完全脱离调用者进程组；
  启用后记录成功/失败，并在稍后复查进程是否仍存活。
- 新增启动首行日志 `starting pid=… parent=…`。此前「根本没启动」与「启动后立刻死」
  无法从日志区分，正是这一盲区让问题多拖了一轮。

### 每次息屏随机换一张

原先按日期做确定性选取，同一天内每次休眠都是同一句。

- `daily-index random TOTAL BOOKS LAST`：从 `/dev/urandom` 取随机数，并避开上一次所在的
  书籍块，使书名与正文一起变化。数据文件按每 50 条同一本书连续排布。
- 翻阅页手动选的句子只在**下一次**息屏生效一次，之后回到随机轮换（原先会锁定整天，
  导致随机被永久打断）。
- 不使用 busybox 的随机工具：该设备的 `awk` 已证实会段错误。

### 验证

真机（PW3）：启用后 `custom_ss.log` 出现新实例的 `READY`；休眠显示本项目海报且每次
变化；唤醒回到书架界面。

离线：`daily-index random` 连续 100 次抽取，相邻两次同书 0 次；1000 次抽样覆盖全部
100 本书；边界（仅一本书、`count=1`、非法参数）返回正确结果或错误码。`xscreen` 用
最小模拟 X 服务做真实协议握手：窗口树遍历、成功/失败/连不上 X 三条路径的返回码均正确。
产物均为 ELF32 ARM 软浮点、无 `PT_INTERP`（真静态），10 项单元测试通过。

### 联网维护（可选）

`emergency.sh` 交给 hotfix 的开机任务执行以启动 Wi-Fi SSH，`tools/deploy_over_wifi.sh`
用于联网部署。设备处于 USB 大容量存储模式时会关闭无线电，因此该路径需在设备唤醒且
未插 USB 时使用。此部分未在真机上确认过。

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
