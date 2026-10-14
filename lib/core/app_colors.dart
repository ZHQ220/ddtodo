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
  /// 这里用整型 alpha 的 `withAlpha`，而不是 `withOpacity`：后者从 3.27 起被标记
  /// deprecated，更新版本里可能已被彻底移除，一旦移除就是「方法不存在」的编译错误。
  /// `withAlpha(int)` 是长期稳定 API，新旧版本都能编译。
  static Color tint(Color c, [double opacity = 0.16]) =>
      Color.alphaBlend(c.withAlpha((opacity * 255).round()), Colors.white);

  /// 与 [palette] 一一对应的十六进制字符串（顺序必须与 palette 完全一致）。
  static const List<String> paletteHex = <String>[
    '#E5484D', // 1 红
    '#2FB344', // 2 绿
    '#3B82F6', // 3 蓝
    '#F59E0B', // 4 橙
    '#8B5CF6', // 5 紫
    '#00A8A8', // 6 青
    '#EC4899', // 7 粉
    '#0EA5E9', // 8 天蓝
    '#84CC16', // 9 黄绿
    '#6B7280', // 10 灰
  ];

  /// 颜色 → 十六进制字符串。
  ///
  /// 不再通过 `Color.value` 反推（该 getter 3.27 起 deprecated，新版可能已移除），
  /// 而是按调色板索引直接取常量：不依赖任何版本敏感的 API。
  /// 全项目调用点都只传入 [palette] 里的颜色；万一传入别的颜色，回落到主色。
  static String toHex(Color c) {
    final i = palette.indexOf(c);
    if (i >= 0 && i < paletteHex.length) return paletteHex[i];
    return '#1F9E8F';
  }

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
