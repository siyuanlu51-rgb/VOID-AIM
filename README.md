# VOID//AIM

基于 Godot 4.7.2 的独立 Windows 3D 瞄准训练器，附早期零依赖网页版本。

## 下载与运行

在本仓库的 **Releases** 下载 `VOID-AIM-Portable-Windows-x64.zip`，解压后双击 `VOID-AIM.exe`。无需安装 Godot 或浏览器。

系统要求：64 位 Windows 10/11，支持 OpenGL 3.3 的显卡。程序会在 EXE 所在目录保存 `void_aim.cfg`，请解压到可写目录运行。

## 功能

- 3D 靶场、第一人称手枪、后坐、枪口火光、曳光弹和程序化音效。
- 单目标、六目标与不限时训练；得分、命中率、连击和历史成绩。
- 五轮随机变色反应测试及平均反应时间。
- 灵敏度、FOV、目标大小、目标颜色、训练时长和主音量设置。
- 准星形状、长度、粗细、间距、RGB 颜色和透明度调整及实时预览。

## 操作

| 操作 | 功能 |
| --- | --- |
| 移动鼠标 | 瞄准 |
| 鼠标左键 | 射击 |
| Esc | 暂停并打开设置 |
| Alt + Enter | 切换窗口/全屏 |
| 按住 Tab | 查看当前和历史成绩 |

## 源码与开发

- `project/`：Godot 原生版工程，入口为 `project/project.godot`。
- `legacy-web/`：早期网页原型，可打开 `index.html`，或启动静态服务器。
- `project/export_presets.cfg`：Windows x64 导出配置，默认导出至 `build/VOID-AIM.exe`。

使用 Godot 4.7.2 导入工程即可编辑和运行。导出需要相应版本的 Windows 导出模板。

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path project -- --self-test
Godot_v4.7.2-stable_win64_console.exe --headless --path project --export-release "Windows Desktop" build/VOID-AIM.exe
```

## 成品校验

`VOID-AIM-Portable-Windows-x64.zip` 包含可直接运行的程序和中文说明，不包含个人训练配置或运行日志。

SHA-256：`5419588136a8a38e0ab49e967c8b4d769d6d0fd143e44339c2125de1d2a8d1ce`

2026-11-01 源码内置无界面自检返回 `VOID_AIM_SELF_TEST_OK`。成品压缩包已通过完整性校验；本次未重新验证图形界面及实际游玩体验。
