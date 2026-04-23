# 便签 Bianqian

一款基于 **Flutter Windows Desktop** 的轻量化桌面便签软件，UI 风格参考 **Windows 11 Fluent Design**。

> 当前为 **第一阶段** —— 已完成项目骨架、窗口管理、系统托盘、本地存储、主界面与编辑器。

---

## ✨ 已实现特性

| 模块 | 说明 |
| --- | --- |
| 多便签管理 | 三栏：导航 / 列表 / 编辑器，置顶/搜索/软删除 |
| **拖拽排序** | 列表项整行拖拽（`ReorderableListView`），按 `sortIndex` 持久化 |
| **数据导入/导出** | 全量 JSON 打包导出/导入；单条便签 Markdown 文件导出 |
| **Markdown 实时预览** | 编辑 / 预览 / 分屏 三种视图模式（`flutter_markdown`） |
| **便签分离独立窗口** | 列表悬停 → "分离" 按钮，独立桌面窗口（`desktop_multi_window`） |
| **贴边隐藏** | 拖到屏幕顶/左/右边缘自动收起为 6px 细条，鼠标悬停恢复 |
| **分类系统** | 标签（Tags）：导航栏分组、编辑器内 Chips、重命名/删除 |
| **回收站** | 软删除→回收站；可恢复 / 永久删除 / 一键清空 |
| 富文本工具栏 | Markdown：加粗、斜体、列表、待办勾选框 |
| 本地存储 | Hive NoSQL，写入 `ApplicationSupportDirectory` |
| 无边框窗口 | `window_manager` + 自定义标题栏 |
| 始终置顶 | 主窗口与每个分离窗口独立切换 |
| 窗口透明度 | 标题栏滑杆 0.4–1.0 |
| 系统托盘 | `tray_manager`，右键菜单 / 关闭隐藏 |
| 快捷键 | `Ctrl+S` 保存（自动保存）、`Ctrl+N` 新建 |

## 🗂 目录结构（Clean Architecture）

```
lib/
├── main.dart                       # 入口：路由 主窗口 / 子窗口
├── models/                         # 数据模型层
│   ├── note.dart                   # Note 实体
│   └── note_adapter.dart           # 手写 Hive TypeAdapter
├── services/                       # 服务层（基础设施）
│   ├── storage_service.dart        # Hive 初始化与 Box 管理
│   ├── note_repository.dart        # 便签数据访问 + 标签 + 回收站
│   ├── window_service.dart         # 窗口管理 (置顶/透明度/隐藏)
│   ├── multi_window_service.dart   # 便签分离独立窗口
│   ├── edge_hide_service.dart      # 贴边隐藏（吸附 + 恢复）
│   └── tray_service.dart           # 系统托盘
├── providers/
│   └── providers.dart              # Riverpod Providers (DI + 状态 + 导航)
├── theme/
│   └── app_theme.dart              # Fluent 主题 + 便签配色
├── views/                          # 视图层
│   ├── home_view.dart              # 主面板 (3 栏)
│   ├── note_editor_view.dart       # 编辑器 + 标签条
│   ├── trash_view.dart             # 回收站只读详情
│   └── detached_note_window.dart   # 独立桌面窗口 App 根
└── widgets/                        # 可复用组件
    ├── custom_title_bar.dart
    ├── edge_hide_overlay.dart      # 贴边状态下 UI 感应层
    └── note_card.dart              # 列表卡片（含分离按钮）
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

### 3. 图标资源（已内置）

- `assets/icons/tray.ico` —— 系统托盘图标
- `assets/icons/app_icon.png` —— App Logo
- `windows/runner/resources/app_icon.ico` —— Windows 任务栏 / exe 图标

> 已使用项目自带的 `favicon.ico` 与 `bianqian.png`。替换它们后请运行 `flutter clean` 让 Windows 资源重新生成。

### 4. 运行

```powershell
flutter run -d windows
```

## 🔭 后续阶段（Roadmap）

- [x] 「便签分离」—— 独立桌面窗口
- [x] 贴边隐藏（吸附 + 鼠标悬停恢复）
- [x] 标签分类 / 回收站
- [x] 拖拽排序（`ReorderableListView`）
- [x] 数据导入导出（JSON / Markdown）
- [x] Markdown 实时渲染预览
- [ ] 提醒事件 + 系统通知（基于 `reminderTime`）
- [ ] 暗色主题切换 UI
- [ ] 在便签中插入图片 / 附件
- [ ] 多设备同步（WebDAV / 自建后端）

## 🧰 关键依赖版本

```yaml
fluent_ui: ^4.9.2              # Fluent Design 组件
flutter_riverpod: ^2.5.1       # 状态管理
hive: ^2.2.3                   # 本地 NoSQL
window_manager: ^0.4.2         # 桌面窗口
tray_manager: ^0.2.3           # 系统托盘
desktop_multi_window: ^0.2.0   # 便签分离独立窗口
screen_retriever: ^0.2.0       # 贴边隐藏需要屏幕尺寸
```

## 💡 关键实现细节

### 便签分离独立窗口
- 主进程通过 `DesktopMultiWindow.createWindow(jsonArgs)` 启动子窗口；
  `main()` 接收 `args = ['multi_window', windowId, jsonArgs]` 进入子窗口模式。
- 子窗口与主窗口共享同一 Hive Box（同进程），Riverpod 是子窗口独立 Container。
- 子窗口标题栏的拖拽 / 最大化 / 置顶通过本进程的 `windowManager` 单例完成
  （在子 FlutterEngine 中会绑定到子窗口的原生句柄）。
- "收回主面板" 按钮通过 `DesktopMultiWindow.invokeMethod(0, 'reattach', ...)`
  通知主窗口重置 `note.isDetached = false`。

### 贴边隐藏（EdgeHideService）
1. 监听 `WindowListener.onWindowMoved` / `onWindowResize`。
2. 取主显示器尺寸，判断窗口是否进入 `snapThreshold(6px)` 边缘。
3. 命中后保存原 `Rect`，把窗口缩成 6px 细条贴边，并强制置顶。
4. UI 层 `EdgeHideOverlay` 监听 `hiddenSideStream`，当处于隐藏态时
   渲染一个全窗口 `MouseRegion`，鼠标进入即调用 `restore()` 恢复原 Rect。

### 标签 + 回收站
- 标签是 `Note.tags: List<String>` 上的虚拟分组，所有 CRUD 通过
  `NoteRepository` 的 `setTags / renameTag / deleteTag` 实现。
- 回收站 = `Note.isDeleted = true` 的过滤集合；编辑器禁用，仅展示恢复 / 永久删除。
