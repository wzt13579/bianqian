# 便签 (Note Sticker)

轻量桌面便签工具（WPF / .NET 8，Windows）。原项目「番茄钟便签」已精简为纯便签工具，参考 [好用便签](https://www.haoyong333.com/) 的桌面端体验。

L 站佬友链接：https://linux.do/

## 主要功能

- 多段便签：编辑多段文本，可手动或定时自动轮播
- 排版自适应：单行居中、多行首行缩进；窗口缩放时字号自动跟随
- 字体 / 字号 / 文字颜色 全部可在托盘菜单中设置
- 三种背景效果：毛玻璃 / 磨砂 / 苹果风边缘渐变
- 透明度 0~100% 任意调节，背景主色可改
- 托盘常驻：显示/隐藏窗口、上一段/下一段便签、外观调节
- 全局快捷键：`显示/隐藏`、`置顶`、`固定`、`上一段`、`下一段` 共 5 项可自定义（默认均为空）
- 窗口置顶 / 固定模式（不可拖拽防误触）/ 滚轮缩放
- 关闭时最小化到托盘（可关闭此行为）
- 开机自启动

## 运行方式

1. 直接运行根目录 `TomatoNoteTimer.exe`（已打包好放在 [Release](https://github.com/xiaoshengyvlin/Zako-Pomodoro-timer/releases)）。
2. 首次运行会自动创建运行时目录：`config`、`data`、`logs`。
3. 如需恢复初始化状态，删除以上运行时目录后重新启动即可。

## 体积说明

- **自包含单文件**（无需安装运行时）：体积较大（约 70MB+）
- **框架依赖单文件**（需安装 .NET 8 Desktop Runtime）：体积较小（约 3~6MB）

框架依赖单文件示例：

```powershell
dotnet publish .\TomatoNoteTimer\TomatoNoteTimer.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
```

## 开发

环境要求：

- Windows 10/11
- .NET SDK 8.0+

构建命令：

```powershell
dotnet build .\TomatoNoteTimer\TomatoNoteTimer.csproj -c Release
```

直接运行（开发调试）：

```powershell
dotnet run --project .\TomatoNoteTimer\TomatoNoteTimer.csproj -c Debug
```

## 仓库内容说明

```text
TomatoNoteTimer/        项目源码目录
icon.ico                图标源文件（编译时内嵌进 EXE）
TomatoNoteTimer.exe     发布产物（非源码）
README.md               说明文档
LICENSE                 开源许可证
```

## 配置文件位置

运行后在程序所在目录会生成：

```text
config/app.json             外观、置顶、透明度、快捷键等
config/notes.json           字体、字号、轮播间隔
data/notes_content.json     便签段落内容、当前显示索引
logs/app.log                运行日志
```

## ps. 你说的游戏我也玩了，感觉一般，没有那么好玩，也可能是因为没有你......
