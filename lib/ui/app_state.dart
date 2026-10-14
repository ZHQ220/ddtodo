import 'package:flutter/material.dart';

import '../core/date_utils.dart';
import '../core/settings_service.dart';
import '../data/db.dart';
import '../data/shift_repository.dart';
import '../data/task_repository.dart';
import '../data/template_repository.dart';
import '../models/models.dart';
import '../utils/lunar.dart';

/// 全局状态：持有各仓库，管理「当前查看的月份 / 选中的日期」，并对外提供
/// 日历渲染需要的派生数据（班次、任务数量、农历小字）。
class AppState extends ChangeNotifier {
  AppState._(
    this.settings,
    this.shifts,
    this.templates,
    this.tasks,
  );

  final SettingsService settings;
  final ShiftRepository shifts;
  final TemplateRepository templates;
  final TaskRepository tasks;

  static AppState? _instance;

  static AppState get instance {
    final s = _instance;
    if (s == null) {
      throw StateError('AppState 尚未初始化');
    }
    return s;
  }

  /// 应用启动时调用：打开数据库、加载仓库、播种预置数据。
  static Future<AppState> boot() async {
    await Db.open();
    final settings = await SettingsService.load();
    final shifts = ShiftRepository(settings);
    final templates = TemplateRepository();
    final tasks = TaskRepository(shifts, templates);

    await shifts.load();
    await templates.load();

    final state = AppState._(settings, shifts, templates, tasks);
    _instance = state;
    await state.settings.markInitialized();

    // 用户要求：选过日期的话，下次打开恢复上次看的那一天（含它所在的月份）；
    // 从来没选过（首次启动）才默认今天。
    final restored = DayUtil.tryParseIso(settings.lastDate ?? '');
    if (restored != null) {
      state._selectedDate = DayUtil.dateOnly(restored);
      state._visibleMonth = DayUtil.firstOfMonth(state._selectedDate);
    }
    return state;
  }

  // ------------------------------------------------------------ 日期状态

  DateTime _selectedDate = DayUtil.today();
  DateTime _visibleMonth = DayUtil.firstOfMonth(DayUtil.today());

  DateTime get selectedDate => _selectedDate;
  DateTime get visibleMonth => _visibleMonth;

  List<DailyTask> _selectedDayTasks = [];
  List<DailyTask> get selectedDayTasks => _selectedDayTasks;

  /// 日历格里的农历小字缓存（日期 iso → 文本）。
  final Map<String, String> _lunarCache = {};

  /// 任务数量缓存（日期 iso → 未完成数量）；null 表示尚未加载。
  Map<String, int>? _counts;
  bool _loadingTasks = false;
  bool _reloadQueued = false;
  bool get loadingTasks => _loadingTasks;

  /// 打卡数据是否已就绪。
  bool get hasCounts => _counts != null;

  Future<void> selectDate(DateTime date) async {
    _selectedDate = DayUtil.dateOnly(date);
    _visibleMonth = DayUtil.firstOfMonth(_selectedDate);
    await settings.setLastDate(DayUtil.iso(_selectedDate));
    notifyListeners();
    await loadSelectedDay();
  }

  Future<void> loadSelectedDay() async {
    _selectedDayTasks = await tasks.ensureAndLoad(_selectedDate);
    notifyListeners();
  }

  /// 切换到上/下个月。
  Future<void> shiftMonth(int delta) async {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    notifyListeners();
    await loadMonth();
  }

  Future<void> goToMonth(DateTime month) async {
    _visibleMonth = DayUtil.firstOfMonth(month);
    notifyListeners();
    await loadMonth();
  }

  Future<void> goToToday() async {
    _selectedDate = DayUtil.today();
    _visibleMonth = DayUtil.firstOfMonth(_selectedDate);
    notifyListeners();
    await loadMonth();
    await loadSelectedDay();
  }

  /// 加载当前月份的日历数据。
  ///
  /// 性能取舍：月视图需要「当天任务数量圆点」，但按需求不能预生成多年数据。
  /// 折中方案 —— 只为**当前可见的这一个月**按需实例化（约 30 天），
  /// 且在首次渲染之后再补算，不阻塞 UI。
  Future<void> loadMonth() async {
    if (_loadingTasks) {
      // 正在加载时又滑到了别的月份（快速滑动）：记一笔，等这一轮结束后再补一轮。
      // 否则新滑到的那一个月会永远没有数量圆点。
      _reloadQueued = true;
      return;
    }
    _loadingTasks = true;
    notifyListeners();

    do {
      _reloadQueued = false;
      // 每一轮都重新读 _visibleMonth：滑动很快时它可能已经又变了。
      final from = DayUtil.firstOfMonth(_visibleMonth);
      final to = DayUtil.addDays(DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1), -1);

      await tasks.ensureRange(from, to);
      _counts = await tasks.countsByDate(from, to);
      _lunarCache.clear();
    } while (_reloadQueued);

    _loadingTasks = false;
    notifyListeners();
  }

  /// 强制刷新（增删任务后调用）。
  Future<void> refreshAll() async {
    _lunarCache.clear();
    await loadMonth();
    await loadSelectedDay();
  }

  /// 班次任务模板改动后调用：立刻把「今天及以后」的任务补齐 / 同步，并刷新界面。
  ///
  /// 用户要求：保存模板后返回日历就能看到那一天的任务；过去的日子保持原样。
  /// 切换排班周期时也走这里：班次变了的那些天会把旧班次遗留的未完成任务清掉，
  /// 换成新周期的任务清单。
  Future<void> syncTemplateChanges() async {
    final today = DayUtil.today();
    final monthEnd = DayUtil.addDays(
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1), -1);
    final todayMonthEnd =
        DayUtil.addDays(DateTime(today.year, today.month + 1, 1), -1);
    final to = monthEnd.isAfter(todayMonthEnd) ? monthEnd : todayMonthEnd;
    await tasks.syncTemplateChanges(from: today, until: to);
    await refreshAll();
  }

  /// 顶部「刷新」按钮：重新从数据库读取班次与模板，再把「今天及以后」的清单
  /// 按模板重算一遍，最后重算当前月份的数量圆点。
  ///
  /// 旧实现只调用 `refreshAll()`：数据没变时界面看不出任何变化，用户会以为按钮
  /// 按了没反应。这里改成一次真正的重载，并在界面上给出「已刷新」提示。
  Future<void> hardRefresh() async {
    await shifts.load();
    await templates.load();
    await syncTemplateChanges();
    await refreshCounts();
  }

  /// 任务数据变化后的轻量刷新：不重新实例化，只重算数量与当天列表。
  Future<void> refreshCounts() async {
    final from = DayUtil.firstOfMonth(_visibleMonth);
    final to = DayUtil.addDays(DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1), -1);
    _counts = await tasks.countsByDate(from, to);
    notifyListeners();
  }

  // ------------------------------------------------------- 日历派生数据

  /// 日历格的小字：节日 / 节气 / 农历日。
  String lunarLabel(DateTime date) {
    final key = DayUtil.iso(date);
    final cached = _lunarCache[key];
    if (cached != null) return cached;
    final text = LunarUtil.cellSubtitle(date);
    _lunarCache[key] = text;
    return text;
  }

  /// 该日期格显示的班次。
  ///
  /// 一天一个班次；夜班（如 22:00 → 次日 07:30）算在**结束那一天**，
  /// 所以 14 号夜班只会显示在 14 号，13 号不会出现晚班。
  ShiftType? shiftForCell(DateTime date) => tasks.shiftOfDay(date);

  /// 手动指定「从现在起用哪一条排班周期」（从今天生效，过去不变）。
  ///
  /// 之后打开某天时会按新周期重新对账：班次变了的那些天会把旧班次遗留的
  /// 未完成任务清掉，并生成新班次的任务。
  Future<void> activateCycle(ShiftCycle cycle) async {
    await settings.setActiveCycle(cycle.id, from: DayUtil.iso(DayUtil.today()));
    await syncTemplateChanges();
  }

  /// 未完成任务数量；0 表示不显示圆点。
  int taskCount(DateTime date) => _counts?[DayUtil.iso(date)] ?? 0;

  bool isSelected(DateTime date) => DayUtil.isSameDay(date, _selectedDate);
  bool get isTodaySelected => DayUtil.isSameDay(_selectedDate, DayUtil.today());

  /// 帮助方法：解析 `yyyy-MM-dd`。
  static DateTime? parse(String? iso) => iso == null ? null : DayUtil.tryParseIso(iso);
}
