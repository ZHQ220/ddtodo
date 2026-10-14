import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../core/holidays.dart';
import '../app_state.dart';
import '../widgets/common.dart';
import 'day_detail_sheet.dart';

/// 月视图日历页。
///
/// 视觉参考图 1：顶部「日程概览 yyyy年M月」，下面是 7 列日期格，
/// 每格包含日期数字、农历（节日 / 节气优先）、班次色块、未完成任务数圆点。
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  /// 起始页要对齐「当前应该显示的月份」：打开 App 时如果恢复的是上次选中的
  /// 日期（可能在别的月份），固定从今天那页开始会让标题和格子对不上。
  late final PageController _controller =
      PageController(initialPage: _pageOfMonth(widget.state.visibleMonth));

  AppState get state => widget.state;

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) state.loadMonth();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// PageView 的页码 → 月份（以 600 为「今天所在月」）。
  DateTime _monthOfPage(int page) {
    final base = DayUtil.firstOfMonth(DayUtil.today());
    return DateTime(base.year, base.month + (page - 600), 1);
  }

  int _pageOfMonth(DateTime month) {
    final base = DayUtil.firstOfMonth(DayUtil.today());
    final diff = (month.year - base.year) * 12 + (month.month - base.month);
    return 600 + diff;
  }

  Future<void> _openDay(DateTime date) async {
    await state.selectDate(date);
    if (!mounted) return;
    await showDayDetailSheet(context, state, date);
  }

  @override
  Widget build(BuildContext context) {
    // 本页自己也监听一次全局状态：左右滑月时 `AppState.notifyListeners()`
    // 会让标题（visibleMonth）与每格的任务数量圆点（_counts）立刻重画，
    // 不依赖外层容器是否重建了这一页。
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _body(),
    );
  }

  Widget _body() {
    return Column(
      children: [
        _header(),
        _weekHeader(),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (page) async {
              final month = _monthOfPage(page);
              if (!DayUtil.isSameDay(month, state.visibleMonth)) {
                await state.goToMonth(month);
              }
            },
            itemBuilder: (context, page) {
              final month = _monthOfPage(page);
              return _MonthGrid(
                month: month,
                state: state,
                weekdays: _weekdays,
                onTapDay: _openDay,
                onLongPressDay: (date) => _changeShift(date),
              );
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- 顶部标题

  Widget _header() {
    final month = state.visibleMonth;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    '日程概览',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${month.year}年${month.month}月',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                state.isTodaySelected
                    ? '今天 · ${DayUtil.iso(DayUtil.today())}'
                    : '已选 ${DayUtil.iso(state.selectedDate)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '回到今天',
            onPressed: () async {
              await state.goToToday();
              if (_controller.hasClients) {
                _controller.jumpToPage(_pageOfMonth(state.visibleMonth));
              }
            },
            icon: const Icon(Icons.today_outlined, color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: '排班规则',
            onPressed: () => Navigator.of(context).pushNamed('/shifts'),
            icon: const Icon(Icons.tune, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _weekHeader() {
    final mondayFirst = state.settings.weekStartMonday;
    final names = mondayFirst
        ? _weekdays
        : [..._weekdays.sublist(6), ..._weekdays.sublist(0, 6)];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  names[i],
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 长按某天：直接弹窗切换这一天的班次（单天覆盖，不二次确认）。
  Future<void> _changeShift(DateTime date) async {
    final picked = await showShiftPicker(context, state, date);
    if (picked == null || !mounted) return;
    if (picked == -1) {
      await state.shifts.setException(date, null);
    } else {
      await state.shifts.setException(date, picked);
    }
    await state.refreshAll();
  }
}

/// 一个月的日期格。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.state,
    required this.weekdays,
    required this.onTapDay,
    required this.onLongPressDay,
  });

  final DateTime month;
  final AppState state;
  final List<String> weekdays;
  final Future<void> Function(DateTime) onTapDay;
  final Future<void> Function(DateTime) onLongPressDay;

  @override
  Widget build(BuildContext context) {
    final mondayFirst = state.settings.weekStartMonday;
    final first = DayUtil.firstOfMonth(month);
    final daysInMonth = DayUtil.daysInMonth(month);

    // 本月第一天相对周首的空位数。
    var offset = (first.weekday - (mondayFirst ? DateTime.monday : DateTime.sunday)) % 7;
    if (offset < 0) offset += 7;

    final totalCells = ((offset + daysInMonth) / 7).ceil() * 7;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.62,
              ),
              itemCount: totalCells,
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(month.year, month.month, dayNumber);
                return _DayCell(
                  date: date,
                  state: state,
                  onTap: () => onTapDay(date),
                  onLongPress: () => onLongPressDay(date),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.state,
    required this.onTap,
    required this.onLongPress,
  });

  final DateTime date;
  final AppState state;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final selected = state.isSelected(date);
    final today = DayUtil.isSameDay(date, DayUtil.today());
    final shift = state.shiftForCell(date);
    final shiftColor = shift == null ? null : AppColors.fromHex(shift.colorHex);
    final count = state.taskCount(date);
    final weekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    // 法定节假日「休」/ 调休上班「班」小角标（普通周末不标）。
    final holiday = Holidays.badgeOf(date);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: const BorderSide(color: AppColors.divider, width: 0.6),
            bottom: const BorderSide(color: AppColors.divider, width: 0.6),
          ),
          color: selected && shiftColor != null
              ? AppColors.tint(shiftColor, 0.10)
              : (selected ? AppColors.tint(AppColors.primary, 0.08) : null),
        ),
        padding: const EdgeInsets.fromLTRB(2, 5, 2, 3),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 日期数字
                Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: today ? AppColors.tint(AppColors.primary, 0.22) : null,
                      border: selected
                          ? Border.all(color: AppColors.primary, width: 1.4)
                          : null,
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.05,
                        fontWeight: today || selected ? FontWeight.w700 : FontWeight.w500,
                        color: today || selected
                            ? AppColors.primary
                            : (weekend ? const Color(0xFF8A6A4A) : AppColors.textPrimary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                // 农历 / 节日 / 节气
                Center(
                  child: Text(
                    state.lunarLabel(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, height: 1.1, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 3),
                // 班次色块
                if (shift != null) ShiftChip(shift: shift, dense: true),
                const Spacer(),
                // 任务数量圆点（未完成）
                if (count > 0)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.only(right: 3, bottom: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                      decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.primary, 0.16),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (holiday != null)
              Positioned(
                top: 0,
                right: 0,
                child: _HolidayBadge(text: holiday),
              ),
          ],
        ),
      ),
    );
  }
}

/// 日历格右上角的小角标：「休」（法定节假日）或「班」（调休上班）。
///
/// 独立占角落，不挤占农历/节气那行小字。
class _HolidayBadge extends StatelessWidget {
  const _HolidayBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isRest = text == '休';
    final color = isRest ? const Color(0xFFE5484D) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1.8, vertical: 0.5),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
