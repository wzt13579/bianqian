import 'package:fluent_ui/fluent_ui.dart';

/// 全局主题与配色（Windows 11 Fluent Design 风格）。
class AppTheme {
  AppTheme._();

  /// 便签可选背景色（柔和马卡龙色）。
  static const List<Color> noteColors = <Color>[
    Color(0xFFFFF8DC), // 米黄
    Color(0xFFFFE4E1), // 浅粉
    Color(0xFFE0FFFF), // 浅青
    Color(0xFFE6E6FA), // 薰衣草
    Color(0xFFF0FFF0), // 蜜瓜绿
    Color(0xFFFFEFD5), // 木瓜橙
    Color(0xFFF5F5DC), // 米白
    Color(0xFFFFFFFF), // 白
  ];

  static FluentThemeData light() {
    return FluentThemeData(
      brightness: Brightness.light,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.standard,
    );
  }

  static FluentThemeData dark() {
    return FluentThemeData(
      brightness: Brightness.dark,
      accentColor: Colors.blue,
      visualDensity: VisualDensity.standard,
    );
  }
}
