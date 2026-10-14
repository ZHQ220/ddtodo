import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/models.dart';

/// 圆形勾选控件：未完成是空心圆环，完成是实心青绿圆 + 白色对勾。
///
/// 对应图 2 里子任务前面的那个圆点圆环。
class TaskCheckCircle extends StatelessWidget {
  const TaskCheckCircle({
    super.key,
    required this.checked,
    this.onTap,
    this.size = 22,
    this.color,
  });

  final bool checked;
  final VoidCallback? onTap;
  final double size;

  /// 勾选后的填充色，默认主题青绿；父任务可选班次色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppColors.primary;
    return InkResponse(
      onTap: onTap,
      radius: size,
      containedInkWell: false,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: checked ? fill : Colors.transparent,
              border: Border.all(
                color: checked ? fill : const Color(0xFFBFC6CC),
                width: 1.8,
              ),
            ),
            child: checked
                ? Icon(Icons.check, size: size * 0.68, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

/// 编号方块（图 2 里任务标题左侧的 1 / 2 / 3 小方块）。
class NumberBadge extends StatelessWidget {
  const NumberBadge({
    super.key,
    required this.number,
    this.color,
    this.size = 24,
  });

  final int number;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.tint(c, 0.10),
        border: Border.all(color: c, width: 1.4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: size * 0.55,
          height: 1.0,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

/// 班次色块（日历格里的小条）。
class ShiftChip extends StatelessWidget {
  const ShiftChip({
    super.key,
    required this.shift,
    this.dense = false,
    this.onTap,
  });

  final ShiftType shift;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.fromHex(shift.colorHex);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 2 : 4,
          vertical: dense ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          shift.name,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: dense ? 8.5 : 10,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: AppColors.onColor(color),
          ),
        ),
      ),
    );
  }
}

/// 圆形色点（班次颜色选择器 / 图例）。
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    this.selected = false,
    this.size = 26,
    this.onTap,
  });

  final Color color;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: size,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppColors.textPrimary, width: 2.2)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 小药丸标签（「重复」「⏰ 10:00」这类）。
class PillTag extends StatelessWidget {
  const PillTag({
    super.key,
    required this.text,
    this.icon,
    this.color,
    this.onTap,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint(c, 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: c),
              const SizedBox(width: 3),
            ],
            Text(
              text,
              style: TextStyle(fontSize: 11.5, color: c, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态占位。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.text,
    this.icon = Icons.inbox_outlined,
    this.padding = const EdgeInsets.symmetric(vertical: 36),
  });

  final String text;
  final IconData icon;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFFC7CDD3)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗里用的区块标题。
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 全项目统一的输入框样式（白底、圆角描边、聚焦变青绿）。
///
/// 刻意不通过 `ThemeData.inputDecorationTheme` 提供：Flutter 3.3x 起该字段的
/// 类型从 `InputDecorationTheme` 变成了 `InputDecorationThemeData`，写哪一个
/// 都会在另一半版本上编译失败；改成显式传 decoration，任何版本都成立。
InputDecoration appInputDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool dense = true,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    isDense: dense,
    hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border(AppColors.divider),
    enabledBorder: border(AppColors.divider),
    focusedBorder: border(AppColors.primary, 1.4),
  );
}
