import 'package:flutter/material.dart';

/// 候选颜色池：用户可在「设置 → 班次类型」里为任意班次（含预置班次）挑选这 10 种颜色。
///
/// 使用 `Color(0xFFRRGGBB)` 而不是 `Color.fromARGB`，以保证在 Flutter 3.27 前后
/// 的版本上都能编译（新版把 `value` 换成浮点通道，旧构造器被标记为 deprecated）。
class AppColors {
  AppColors._();

  /// 主色：取自参考截图的青绿色。
  static const Color primary = Color(0xFF1F9E8F);
  static const Color primaryDark = Color(0xFF178578);
  static const Color primaryLight = Color(0xFF7FD4C8);

  /// 页面背景与卡片
  static const Color scaffold = Color(0xFFF5F6F7);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE8EAEC);

  /// 文本
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  /// 系统日历导入项的专用灰色
  static const Color imported = Color(0xFF8A8F98);

  /// 危险操作（恢复出厂、删除全部数据）用的红色
  static const Color danger = Color(0xFFE5484D);

  /// 10 种候选班次色（按顺序即默认分配顺序）
  static const List<Color> palette = <Color>[
    Color(0xFFE5484D), // 1 红
    Color(0xFF2FB344), // 2 绿
    Color(0xFF3B82F6), // 3 蓝
    Color(0xFFF59E0B), // 4 橙
    Color(0xFF8B5CF6), // 5 紫
    Color(0xFF00A8A8), // 6 青
    Color(0xFFEC4899), // 7 粉
    Color(0xFF0EA5E9), // 8 天蓝
    Color(0xFF84CC16), // 9 黄绿
    Color(0xFF6B7280), // 10 灰
  ];

  /// 色块的背景（颜色的淡色版），用于日历格内的班次条。
  ///
  /// 这里用 `withOpacity`（在 3.27+ 上已 deprecated 但仍可用）而不是
  /// `withValues`，是为了让同一份代码能在 Flutter 3.24 与 3.38 上都能编译。
  // ignore: deprecated_member_use
  static Color tint(Color c, [double opacity = 0.16]) =>
      Color.alphaBlend(c.withOpacity(opacity), Colors.white);

  // ignore: deprecated_member_use
  static String toHex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color fromHex(String hex, {Color fallback = primary}) {
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return fallback;
    return Color(v);
  }

  /// 浅色/深色文字的自适应：根据背景亮度决定用白字还是深色字。
  static Color onColor(Color background) =>
      background.computeLuminance() > 0.62 ? textPrimary : Colors.white;
}
