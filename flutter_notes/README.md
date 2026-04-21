# MI 便签 · Flutter 重写版

把 `../`（根目录）的 **MiCode 小米便签** Java 工程用 Flutter 重写的版本，目标平台：**Android + Windows 桌面**，UI 仿原版黄色便签纸风格。

> 原 Java 代码保留在仓库根目录作参考，本工程是独立的 Flutter 项目。

## 已实现功能（标准版）

- 便签列表（按修改时间排序，支持置顶）
- 新建 / 编辑 / 删除 便签
- 文件夹分类（左侧抽屉切换、批量移动、重命名、删除）
- 本地 SQLite 持久化（Android 用 `sqflite`，Windows 用 `sqflite_common_ffi`，统一接口）
- 关键字全文搜索
- **Todo 清单模式**（可勾选、可拖拽排序、与文本模式互转）
- 5 种便签颜色（黄/蓝/白/绿/红，仿原版）
- 本地提醒通知（`flutter_local_notifications`，Android 走系统通知；Windows 不支持系统调度，存进数据库后在编辑页顶部以横幅形式提示）
- 长按多选 → 批量删除 / 批量移动到文件夹

## 目录结构

```
flutter_notes/
├── lib/
│   ├── main.dart                 入口
│   ├── app.dart                  根 Widget + Provider 注入
│   ├── models/
│   │   ├── note.dart             便签模型 + 清单项
│   │   └── folder.dart           文件夹模型
│   ├── data/
│   │   ├── database.dart         跨平台 SQLite 初始化
│   │   └── notes_repository.dart CRUD 仓储
│   ├── state/
│   │   └── notes_store.dart      ChangeNotifier 状态
│   ├── services/
│   │   └── notification_service.dart 本地通知
│   └── ui/
│       ├── theme/
│       │   ├── app_theme.dart
│       │   └── note_colors.dart   5 种便签配色
│       ├── widgets/
│       │   └── note_card.dart     便签卡片
│       └── pages/
│           ├── notes_list_page.dart  主列表
│           ├── note_edit_page.dart   编辑页（文本/清单切换）
│           ├── folders_page.dart     文件夹抽屉
│           └── search_page.dart      搜索
└── pubspec.yaml
```

## 环境要求

- Flutter `3.24.4` 或更新（已用此版本验证）
- Dart `3.5+`
- **Android**：JDK 17、Android SDK（API 21+ 即可，本工程没设特殊 minSdk）
- **Windows**：Visual Studio 2022 + 「使用 C++ 的桌面开发」工作负载（Flutter 桌面构建必需）

## 运行

```powershell
cd flutter_notes
flutter pub get

# Android（连一台手机或开模拟器）
flutter devices
flutter run -d <device-id>

# Windows 桌面
flutter run -d windows
```

> 第一次构建 Android 时 Gradle 会下载较多依赖，国内建议给 Gradle 配镜像（编辑 `android/build.gradle.kts` 或 `~/.gradle/init.gradle`）。

## 打包发布

```powershell
# Android Release APK
flutter build apk --release

# Windows Release exe
flutter build windows --release
# 产物：build\windows\x64\runner\Release\mi_notes_flutter.exe
```

## 与原 Java 项目的功能对照

| 原小米便签功能 | 本 Flutter 版 |
| --- | --- |
| 便签列表 / 新建编辑 | ✅ |
| 文件夹分类 | ✅ |
| 5 种便签底色 | ✅ |
| Todo 清单 | ✅（可勾选 + 拖拽排序）|
| 提醒（AlarmReceiver） | ✅ Android 用系统通知；Windows 用应用内提示 |
| 搜索 | ✅ |
| 桌面小部件（widget 2x/4x） | ❌ 暂未实现（后续可用 `home_widget` 包做） |
| 通话便签 / 联系人 | ❌ 与平台耦合较深，未实现 |
| Google Tasks 同步 | ❌ 旧版 API 已停服 |

## 数据存储位置

- **Android**：应用私有目录 `databases/mi_notes.db`
- **Windows**：`%APPDATA%\net.micode\mi_notes_flutter\mi_notes\mi_notes.db`

## 已知差异 / 后续可扩展

- 富文本编辑器目前只是纯文本，后续可换 `flutter_quill` 之类支持加粗、字号。
- 没有「回收站」UI，删除直接软删除（`is_deleted=1`），需要的话可加一个回收站页面。
- Windows 的提醒走系统通知需要换更新版插件 + Windows 通知 XML 配置，现版本仅作应用内提醒。
