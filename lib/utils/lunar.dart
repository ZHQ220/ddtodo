/// 农历工具（1900–2100）。
///
/// 用「年位表 + 天文常数修正」查表法实现，不依赖任何第三方包：
///   * [lunarYearBits]：1900–2100 共 201 项，每项编码一年的月序信息，
///     低 4 位 = 闰月月份（0 表示无闰月），第 5–16 位（从高到低）= 正月..腊月
///     的大小月（1 = 30 天 / 0 = 29 天）。
///   * [anchorDay]：1900-01-31（农历 1900 年正月初一）的儒略式天数 40。
///   * [solarTermInfo]：24 节气的分钟偏移表，用 [solarTermDay] 的高阶公式换算，
///     精度对 1900–2100 足够（个别年份边界日可能有 ±1 天误差）。
///
/// 节气表仅用于：
///   1. 日历格「寒露 / 霜降 / 立春」这类文字标注；
///   2. 节日识别（清明）。
class LunarInfo {
  const LunarInfo({
    required this.lunarYear,
    required this.lunarMonth,
    required this.lunarDay,
    required this.isLeapMonth,
    this.solarTerm,
  });

  final int lunarYear;
  final int lunarMonth;
  final int lunarDay;
  final bool isLeapMonth;

  /// 当天恰好是某个节气时给出节气名，否则为 null。
  final String? solarTerm;

  /// 中文数字（初一、十二、廿三、三十）。
  static const List<String> _dayNames = [
    '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
    '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
    '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
  ];

  static const List<String> _monthNames = [
    '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊',
  ];

  static const List<String> _gan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  static const List<String> _zhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  static const List<String> _animals = [
    '鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪',
  ];

  String get dayName => _dayNames[(lunarDay - 1).clamp(0, 29)];

  /// 正月初一显示月份名，其余显示日名 —— 与主流日历 App 一致。
  String get dayLabel => lunarDay == 1 ? monthName : dayName;

  String get monthName => '${isLeapMonth ? '闰' : ''}${_monthNames[(lunarMonth - 1).clamp(0, 11)]}月';

  String get ganzhiYear {
    final offset = (lunarYear - 4) % 60;
    final i = offset < 0 ? offset + 60 : offset;
    return '${_gan[i % 10]}${_zhi[i % 12]}';
  }

  String get zodiac => _animals[(lunarYear - 4) % 12 < 0
      ? ((lunarYear - 4) % 12) + 12
      : (lunarYear - 4) % 12];

  /// 传统节日（按农历），没有则返回 null。
  String? get festival {
    if (isLeapMonth) return null;
    const map = <String, String>{
      '1-1': '春节',
      '1-15': '元宵节',
      '2-2': '龙抬头',
      '5-5': '端午节',
      '7-7': '七夕',
      '7-15': '中元节',
      '8-15': '中秋节',
      '9-9': '重阳节',
      '12-8': '腊八节',
      '12-23': '小年',
    };
    return map['$lunarMonth-$lunarDay'];
  }

  @override
  String toString() => '$lunarYear-$lunarMonth-$lunarDay${isLeapMonth ? '(闰)' : ''}';
}

/// 公历节日与固定纪念日。
class SolarFestival {
  const SolarFestival._();

  static const Map<String, String> _map = {
    '1-1': '元旦',
    '2-14': '情人节',
    '3-8': '妇女节',
    '3-12': '植树节',
    '4-1': '愚人节',
    '5-1': '劳动节',
    '5-4': '青年节',
    '6-1': '儿童节',
    '7-1': '建党节',
    '8-1': '建军节',
    '9-10': '教师节',
    '10-1': '国庆节',
    '12-24': '平安夜',
    '12-25': '圣诞节',
  };

  static String? of(int month, int day) => _map['$month-$day'];
}

/// 农历主工具。全部方法都是纯函数，可在 build 中安全调用。
class LunarUtil {
  LunarUtil._();

  /// 1900–2100 农历年编码表。
  ///
  /// 索引 = year - 1900。数值为十六进制，含义见 [LunarInfo] 文档。
  static const List<int> lunarYearBits = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
    0x09ad0, 0x055d2, 0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540,
    0x0d6a0, 0x0ada2, 0x095b0, 0x14977, 0x04970, 0x0a4b0, 0x0b4b5, 0x06a50,
    0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, 0x06566, 0x0d4a0,
    0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
    0x0a950, 0x0b557, 0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573,
    0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, 0x0aea6, 0x0ab50, 0x04b60, 0x0aae4,
    0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, 0x096d0, 0x04dd5,
    0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
    0x0ab60, 0x09570, 0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58,
    0x05ac0, 0x0ab60, 0x096d5, 0x092e0, 0x0c960, 0x0d954, 0x0d4a0, 0x0da50,
    0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, 0x0a950, 0x0b4a0,
    0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
    0x0ea65, 0x0d530, 0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0,
    0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, 0x0b5a0, 0x056d0, 0x055b2, 0x049b0,
    0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, 0x14b63, 0x09370,
    0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0,
    0x0a6d0, 0x055d4, 0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50,
    0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, 0x0b273, 0x06930, 0x07337, 0x06aa0,
    0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, 0x0e968, 0x0d520,
    0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
    0x0d520,
  ];

  /// 1900-01-31 对应的「年内第 N 天」基准（与常见农历算法的 40 对齐）。
  static const int anchorDay = 40;
  static const int minYear = 1900;
  static const int maxYear = 2100;

  static const List<String> solarTermNames = [
    '小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
    '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑',
    '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
  ];

  /// 24 节气相对 1900-01-06 小寒的分钟偏移（经典常数表）。
  static const List<int> _solarTermInfo = [
    0, 21208, 42467, 63836, 85337, 107014, 128867, 150921,
    173149, 195551, 218072, 240693, 263343, 285989, 308563, 331033,
    353350, 375494, 397447, 419210, 440795, 462224, 483532, 504758,
  ];

  // ------------------------------------------------------------ 基础解码

  /// 闰月月份，0 表示该年无闰月。
  static int leapMonth(int year) {
    _checkYear(year);
    return lunarYearBits[year - minYear] & 0xf;
  }

  /// 闰月天数（无闰月返回 0）。
  static int leapMonthDays(int year) {
    final leap = leapMonth(year);
    if (leap == 0) return 0;
    return (lunarYearBits[year - minYear] & 0x10000) != 0 ? 30 : 29;
  }

  /// 第 [month] 个农历月的天数（不含闰月）。
  static int monthDays(int year, int month) {
    _checkYear(year);
    if (month < 1 || month > 12) {
      throw ArgumentError('month 必须在 1..12，收到 $month');
    }
    return (lunarYearBits[year - minYear] & (0x10000 >> month)) != 0 ? 30 : 29;
  }

  /// 农历一年的总天数。
  static int yearDays(int year) {
    _checkYear(year);
    var sum = 348; // 12 * 29
    final bits = lunarYearBits[year - minYear];
    for (var i = 0x8000; i > 0x8; i >>= 1) {
      if ((bits & i) != 0) sum += 1;
    }
    return sum + leapMonthDays(year);
  }

  static void _checkYear(int year) {
    if (year < minYear || year > maxYear) {
      throw ArgumentError('农历表仅支持 $minYear–$maxYear 年，收到 $year');
    }
  }

  // -------------------------------------------------------------- 转换

  /// 公历 → 农历。
  static LunarInfo fromSolar(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    var offset = d.difference(DateTime(1900, 1, 31)).inDays;

    var year = minYear;
    var temp = 0;
    for (year = minYear; year <= maxYear && offset > 0; year++) {
      temp = yearDays(year);
      offset -= temp;
    }
    if (offset < 0) {
      offset += temp;
      year -= 1;
    }

    final leap = leapMonth(year);
    var isLeap = false;
    var month = 1;
    for (month = 1; month <= 12 && offset >= 0; month++) {
      // 闰月排在该月之后
      if (leap > 0 && month == leap + 1 && !isLeap) {
        month -= 1;
        isLeap = true;
        temp = leapMonthDays(year);
      } else {
        temp = monthDays(year, month);
      }
      if (isLeap && month == leap + 1) {
        isLeap = false;
      }
      if (offset < temp) break;
      offset -= temp;
    }
    if (offset == 0 && leap > 0 && month == leap + 1) {
      isLeap = !isLeap;
      if (isLeap) {
        month -= 1;
      }
    }

    return LunarInfo(
      lunarYear: year,
      lunarMonth: month,
      lunarDay: offset + 1,
      isLeapMonth: isLeap,
      solarTerm: solarTermOf(d),
    );
  }

  /// 公历 → 农历的便捷入口。
  static LunarInfo of(DateTime date) => fromSolar(date);

  // -------------------------------------------------------------- 节气

  /// 某年第 [index]（0 = 小寒 … 23 = 冬至）个节气的公历日期。
  static DateTime solarTermDate(int year, int index) {
    final base = DateTime(1900, 1, 6, 2, 5);
    final millis = base.millisecondsSinceEpoch +
        (31556925974.7 * (year - 1900)).round() +
        (_solarTermInfo[index] * 60000);
    final t = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    // 该换算基于 UTC，加 8 小时得到北京时间所在日。
    final beijing = t.add(const Duration(hours: 8));
    return DateTime(beijing.year, beijing.month, beijing.day);
  }

  /// 当天若为节气日则返回节气名。
  static String? solarTermOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (final index in [d.month * 2 - 2, d.month * 2 - 1]) {
      if (index < 0 || index >= 24) continue;
      final term = solarTermDate(d.year, index);
      if (term.year == d.year && term.month == d.month && term.day == d.day) {
        if (index == 6) return '清明';
        return solarTermNames[index];
      }
    }
    return null;
  }

  // ------------------------------------------------------- 日历格显示文字

  /// 日历格里显示的小字：优先节日 > 节气 > 农历日。
  static String cellSubtitle(DateTime date) {
    final lunar = fromSolar(date);
    final solarFestival = SolarFestival.of(date.month, date.day);
    if (solarFestival != null) return solarFestival;
    final lunarFestival = lunar.festival;
    if (lunarFestival != null) return lunarFestival;
    if (lunar.solarTerm != null) return lunar.solarTerm!;
    return lunar.dayLabel;
  }

  /// 当日完整描述，用于详情页标题下方。
  static String description(DateTime date) {
    final lunar = fromSolar(date);
    final buf = StringBuffer('农历${lunar.monthName}${lunar.dayName}');
    buf.write(' · ${lunar.ganzhiYear}年【${lunar.zodiac}】');
    final f = lunar.festival ?? SolarFestival.of(date.month, date.day);
    if (f != null) buf.write(' · $f');
    if (lunar.solarTerm != null) buf.write(' · ${lunar.solarTerm}');
    return buf.toString();
  }
}
