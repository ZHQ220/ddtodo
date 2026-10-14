import 'date_utils.dart';

/// 法定节假日 / 调休上班日的标记类型。
enum HolidayKind {
  /// 法定节假日放假（日历格显示「休」）。
  rest,

  /// 调休上班的周末（日历格显示「班」）。
  work;

  /// 日历格上的小角标文字。
  String get badge => this == HolidayKind.rest ? '休' : '班';
}

/// 中国法定节假日表（含调休上班日）。
///
/// 数据来源：国务院办公厅《关于××年部分节假日安排的通知》
///  * 2025 年：国办发明电〔2024〕7 号（2024-11-12）
///  * 2026 年：国办发明电〔2025〕7 号（2025-11-04）
///
/// 只内置**已正式公布**的年份：查不到的年份一律返回 null，
/// 日历格照旧显示农历/节气，不会瞎猜。
class Holidays {
  Holidays._();

  /// 「放假」区间，写成 `起始日..结束日`（含首尾）；单日可只写一个。
  static const List<String> _restRanges = [
    // ---------------------------------------------------------- 2025 年
    '2025-01-01', // 元旦
    '2025-01-28..2025-02-04', // 春节（1/28 除夕）
    '2025-04-04..2025-04-06', // 清明节
    '2025-05-01..2025-05-05', // 劳动节
    '2025-05-31..2025-06-02', // 端午节
    '2025-10-01..2025-10-08', // 国庆节 + 中秋节
    // ---------------------------------------------------------- 2026 年
    '2026-01-01..2026-01-03', // 元旦
    '2026-02-15..2026-02-23', // 春节（2/15 腊月二十八）
    '2026-04-04..2026-04-06', // 清明节
    '2026-05-01..2026-05-05', // 劳动节
    '2026-06-19..2026-06-21', // 端午节
    '2026-09-25..2026-09-27', // 中秋节
    '2026-10-01..2026-10-07', // 国庆节
  ];

  /// 「调休上班」的日子（通常是周末补班）。
  static const List<String> _workDays = [
    // 2025 年
    '2025-01-26', '2025-02-08', '2025-04-27', '2025-09-28', '2025-10-11',
    // 2026 年
    '2026-01-04', '2026-02-14', '2026-02-28', '2026-05-09', '2026-09-20',
    '2026-10-10',
  ];

  /// 已内置的年份（升序）。
  static final List<int> years = _build().keys
      .map((iso) => int.parse(iso.substring(0, 4)))
      .toSet()
      .toList()
    ..sort();

  static Map<String, HolidayKind>? _cache;

  static Map<String, HolidayKind> _build() {
    final cached = _cache;
    if (cached != null) return cached;

    final map = <String, HolidayKind>{};
    for (final range in _restRanges) {
      for (final iso in _expand(range)) {
        map[iso] = HolidayKind.rest;
      }
    }
    for (final iso in _workDays) {
      map[iso] = HolidayKind.work;
    }
    _cache = map;
    return map;
  }

  /// 查询某天是不是法定节假日 / 调休上班日；普通日子（含普通周末）返回 null。
  static HolidayKind? of(DateTime date) => _build()[DayUtil.iso(date)];

  /// 日历格上要显示的小角标文字（`休` / `班`），没有则返回 null。
  static String? badgeOf(DateTime date) => of(date)?.badge;

  /// 把 `2025-01-28..2025-02-04` 展开成日期字符串列表。
  static List<String> _expand(String range) {
    final dots = range.indexOf('..');
    if (dots < 0) return [range];

    final start = _parse(range.substring(0, dots));
    final end = _parse(range.substring(dots + 2));
    final result = <String>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      result.add(DayUtil.iso(cursor));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return result;
  }

  static DateTime _parse(String iso) {
    final parts = iso.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}
