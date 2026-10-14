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
    final shifts = ShiftRepository();
    final templates = TemplateRepository();
    final tasks = TaskRepository(shifts, templates);

    await shifts.load();
    await templates.load();

    final state = AppState._(settings, shifts, templates, tasks);
    _instance = state;
    await state.settings.markInitialized();
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
    if (_loadingTasks) return;
    _loadingTasks = true;
    notifyListeners();

    final from = DayUtil.firstOfMonth(_visibleMonth);
    final to = DayUtil.addDays(DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1), -1);

    await tasks.ensureRange(from, to);
    _counts = await tasks.countsByDate(from, to);
    _lunarCache.clear();

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
  Future<void> syncTemplateChanges() async {
    final to = DayUtil.addDays(
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1), -1);
    await tasks.syncTemplateChanges(from: DayUtil.today(), until: to);
    await refreshAll();
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

  /// 该日期格显示的班次（跨天班次——下班时间早于上班时间的——归属结束日）。
  ShiftType? shiftForCell(DateTime date) => tasks.effectiveShiftOfDay(date);

  /// 该日期「开始上班」的班次（单天覆盖弹窗里显示当前值用）。
  ShiftType? startingShift(DateTime date) => tasks.shiftOfDay(date);

  /// 未完成任务数量；0 表示不显示圆点。
  int taskCount(DateTime date) => _counts?[DayUtil.iso(date)] ?? 0;

  bool isSelected(DateTime date) => DayUtil.isSameDay(date, _selectedDate);
  bool get isTodaySelected => DayUtil.isSameDay(_selectedDate, DayUtil.today());

  /// 帮助方法：解析 `yyyy-MM-dd`。
  static DateTime? parse(String? iso) => iso == null ? null : DayUtil.tryParseIso(iso);
}
