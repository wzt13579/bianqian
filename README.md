# 便签 Bianqian

一款基于 **Flutter Windows Desktop** 的轻量化桌面便签软件，UI 风格参考 **Windows 11 Fluent Design**。

> 当前为 **第一阶段** —— 已完成项目骨架、窗口管理、系统托盘、本地存储、主界面与编辑器。

---

## ✨ 已实现特性

| 模块 | 说明 |
| --- | --- |
| 多便签管理 | 列表 + 编辑器双栏，置顶/搜索/软删除 |
| 富文本工具栏 | Markdown：加粗、斜体、列表、待办勾选框 |
| 本地存储 | Hive NoSQL，写入 `ApplicationSupportDirectory` |
| 分类系统 | 数据模型预留 `tags` 字段（UI 待第二阶段） |
| 无边框窗口 | `window_manager` + 自定义标题栏 |
| 始终置顶 | 一键切换 |
| 窗口透明度 | 标题栏滑杆 0.4–1.0 |
| 系统托盘 | `tray_manager`，右键菜单 / 关闭隐藏 |
| 快捷键 | `Ctrl+S` 保存（自动保存）、`Ctrl+N` 新建 |

## 🗂 目录结构（Clean Architecture）

```
lib/
├── main.dart                # 入口：初始化 Hive / 窗口 / 托盘
├── models/                  # 数据模型层
│   ├── note.dart            # Note 实体
│   └── note_adapter.dart    # 手写 Hive TypeAdapter
├── services/                # 服务层（基础设施）
│   ├── storage_service.dart # Hive 初始化与 Box 管理
│   ├── note_repository.dart # 便签数据访问 (Repository)
│   ├── window_service.dart  # 窗口管理 (置顶/透明度/隐藏)
│   └── tray_service.dart    # 系统托盘
├── providers/
│   └── providers.dart       # Riverpod Providers (DI + 状态)
├── theme/
│   └── app_theme.dart       # Fluent 主题 + 便签配色
├── views/                   # 视图层
│   ├── home_view.dart       # 主面板 (列表 + 编辑器)
│   └── note_editor_view.dart
└── widgets/                 # 可复用组件
    ├── custom_title_bar.dart
    └── note_card.dart
```

## 🚀 运行

### 1. 启用 Windows 开发者模式（**重要**）

`flutter pub get` 会提示：
```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```
请运行：
```powershell
start ms-settings:developers
```
打开「开发人员模式」后再继续。

### 2. 安装依赖

```powershell
flutter pub get
```

### 3. 准备托盘图标

把任意 ICO 文件放到 `assets/icons/tray.ico`（Windows 平台必需，缺失时不会崩溃但托盘图标为空）。可以从 [icoconvert.com](https://icoconvert.com/) 在线生成。

### 4. 运行

```powershell
flutter run -d windows
```

## 🔭 后续阶段（Roadmap）

- [ ] 「便签分离」—— 将单条便签拉成独立桌面窗口（multi_window 方案）
- [ ] 贴边隐藏（窗口靠近屏幕边缘自动收起为侧边条）
- [ ] 提醒事件 + 系统通知
- [ ] 分类/标签 UI 与回收站
- [ ] 拖拽排序
- [ ] 数据导入导出（JSON / Markdown）
- [ ] 暗色主题切换 UI

## 🧰 关键依赖版本

```yaml
fluent_ui: ^4.9.2          # Fluent Design 组件
flutter_riverpod: ^2.5.1   # 状态管理
hive: ^2.2.3               # 本地 NoSQL
window_manager: ^0.4.2     # 桌面窗口
tray_manager: ^0.2.3       # 系统托盘
```
