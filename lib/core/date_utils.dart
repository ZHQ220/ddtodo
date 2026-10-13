import 'package:flutter/material.dart';

/// 全局日期工具。
///
/// 数据库里所有日期都以 `yyyy-MM-dd` 字符串存储（SQLite 没有原生 DATE 类型，
/// 字符串形式既可直接比较又能被索引）。
class DayUtil {
  DayUtil._();

  static const List<String> weekdayShort = ['一', '二', '三', '四', '五', '六', '日'];

  /// 归一到当天零点，避免 DateTime 的时分秒参与相等性判断。
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime today() => dateOnly(DateTime.now());

  /// `2025-10-06`
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parseIso(String s) {
    final parts = s.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static DateTime? tryParseIso(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return parseIso(s);
    } catch (_) {
      return null;
    }
  }

  /// 周一为一周的第一天（与图 1 的表头一致）。
  static DateTime mondayOf(DateTime d) =>
      dateOnly(d).subtract(Duration(days: dateOnly(d).weekday - 1));

  static int daysBetween(DateTime a, DateTime b) =>
      dateOnly(b).difference(dateOnly(a)).inDays;

  static DateTime addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  /// 包含首尾的日期区间。
  static List<DateTime> rangeInclusive(DateTime from, DateTime to) {
    final out = <DateTime>[];
    var cur = dateOnly(from);
    final last = dateOnly(to);
    while (!cur.isAfter(last)) {
      out.add(cur);
      cur = addDays(cur, 1);
    }
    return out;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// `10月6日 周一`
  static String label(DateTime d) =>
      '${d.month}月${d.day}日 周${weekdayShort[d.weekday - 1]}';

  /// `10月`
  static String monthLabel(DateTime d) => '${d.month}月';

  /// 该月第一天
  static DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  /// 该月天数
  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;
}
