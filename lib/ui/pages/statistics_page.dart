import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../app_state.dart';
import '../widgets/common.dart';

/// 统计页：当月任务完成情况 + 班次分布 + 未来 7 天趋势。
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.state});

  final AppState state;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  AppState get state => widget.state;

  late DateTime _month = DayUtil.firstOfMonth(DayUtil.today());
  bool _loading = true;
  List<DailyTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _month;
    final to = DayUtil.addDays(DateTime(_month.year, _month.month + 1, 1), -1);
    await state.tasks.ensureRange(from, to);
    final tasks = await state.tasks.tasksInRange(from, to);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _shiftMonth(int delta) async {
    _month = DateTime(_month.year, _month.month + delta, 1);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final roots = _tasks.where((t) => t.parentId == null).toList();
    final done = roots.where((t) => t.isCompleted).length;
    final rate = roots.isEmpty ? 0.0 : done / roots.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          _monthSelector(),
          const SizedBox(height: 12),
          _overviewCard(done, roots.length, rate),
          const SizedBox(height: 12),
          _shiftDistribution(),
          const SizedBox(height: 12),
          _trendCard(),
        ],
      ),
    );
  }

  Widget _monthSelector() {
    return Row(
      children: [
        IconButton(
          onPressed: () => _shiftMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${_month.year} 年 ${_month.month} 月',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        IconButton(
          onPressed: () => _shiftMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
        const Spacer(),
        TextButton(
          onPressed: () async {
            _month = DayUtil.firstOfMonth(DayUtil.today());
            await _load();
          },
          child: const Text('回到本月'),
        ),
      ],
    );
  }

  Widget _overviewCard(int done, int total, double rate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当月任务完成情况',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('$done', '已完成'),
              _metric('${total - done}', '未完成'),
              _metric('${(rate * 100).toStringAsFixed(0)}%', '完成率'),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: AppColors.tint(AppColors.primary, 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _shiftDistribution() {
    final days = <ShiftType, int>{};
    final last = DayUtil.addDays(DateTime(_month.year, _month.month + 1, 1), -1);
    var cursor = _month;
    while (!cursor.isAfter(last)) {
      final shift = state.tasks.shiftOfDay(cursor);
      if (shift != null) {
        days[shift] = (days[shift] ?? 0) + 1;
      }
      cursor = DayUtil.addDays(cursor, 1);
    }
    if (days.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const EmptyHint(
          text: '本月还没有排班规则\n到「设置 → 排班规则管理」新建一个周期',
          icon: Icons.event_note,
          padding: EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }

    final max = days.values.reduce((a, b) => a > b ? a : b);
    final entries = days.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当月班次分布',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      entry.key.name,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: max == 0 ? 0 : entry.value / max,
                        minHeight: 12,
                        backgroundColor: AppColors.tint(
                          AppColors.fromHex(entry.key.colorHex),
                          0.12,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.fromHex(entry.key.colorHex),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${entry.value} 天',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final today = DayUtil.today();
    final days = [for (var i = 0; i < 7; i++) DayUtil.addDays(today, i)];
    final totalByDay = <DateTime, int>{};
    for (final day in days) {
      final iso = DayUtil.iso(day);
      final list = _tasks.where((t) => t.date == iso && t.parentId == null).toList();
      totalByDay[day] = list.length;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '未来 7 天任务量',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${totalByDay[day] ?? 0}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          height: ((totalByDay[day] ?? 0) * 8).clamp(4, 72).toDouble(),
                          decoration: BoxDecoration(
                            color: AppColors.tint(AppColors.primary, 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${day.month}/${day.day}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
