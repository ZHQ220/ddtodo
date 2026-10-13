import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../app_state.dart';
import '../widgets/common.dart';
import 'day_detail_sheet.dart';

/// 任务全局列表页：跨日期查看所有任务，支持搜索与「只看未完成」。
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.state});

  final AppState state;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  AppState get state => widget.state;

  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _hideCompleted = false;
  String _keyword = '';
  List<DailyTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<DailyTask> tasks;
    if (_keyword.trim().isEmpty) {
      tasks = await state.tasks.tasksInRange(
        DayUtil.addDays(DayUtil.today(), -180),
        DayUtil.addDays(DayUtil.today(), 180),
      );
    } else {
      tasks = await state.tasks.search(_keyword);
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Map<String, List<DailyTask>> get _grouped {
    final map = <String, List<DailyTask>>{};
    for (final task in _tasks) {
      if (_hideCompleted && task.isCompleted) continue;
      final key = task.date ?? task.shiftDate ?? '未定日期';
      map.putIfAbsent(key, () => []).add(task);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    final keys = groups.keys.toList()..sort();

    return Column(
      children: [
        _searchBar(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (keys.isEmpty)
          const Expanded(
            child: EmptyHint(text: '没有匹配的任务', icon: Icons.search_off),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  final key = keys[index];
                  final list = groups[key]!;
                  return _dayGroup(key, list);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _searchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              _keyword = v;
              _load();
            },
            decoration: appInputDecoration(
              hintText: '搜索任务标题…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _keyword = '';
                        _load();
                      },
                    ),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 2),
              const Text('只看未完成', style: TextStyle(fontSize: 12.5)),
              Switch(
                value: _hideCompleted,
                onChanged: (v) => setState(() => _hideCompleted = v),
              ),
              const Spacer(),
              Text(
                '共 ${_tasks.length} 条',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayGroup(String iso, List<DailyTask> list) {
    final date = DayUtil.tryParseIso(iso);
    final shift = date == null ? null : state.tasks.effectiveShiftOfDay(date);
    final color = shift == null ? AppColors.primary : AppColors.fromHex(shift.colorHex);
    final roots = list.where((t) => t.parentId == null).toList();
    final done = roots.where((t) => t.isCompleted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                date == null
                    ? iso
                    : '${date.month}月${date.day}日 星期${DayUtil.weekdayShort[(date.weekday - 1) % 7]}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (shift != null) ...[
                const SizedBox(width: 6),
                Text(
                  shift.name,
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
              ],
              const Spacer(),
              Text(
                '$done/${roots.length}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
              if (date != null)
                IconButton(
                  iconSize: 16,
                  tooltip: '查看当天详情',
                  onPressed: () async {
                    await state.selectDate(date);
                    if (!mounted) return;
                    await showDayDetailSheet(context, state, date);
                    await _load();
                  },
                  icon: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        for (final root in roots)
          _taskRow(root, list.where((t) => t.parentId == root.id).toList(), color),
      ],
    );
  }

  Widget _taskRow(DailyTask task, List<DailyTask> children, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                TaskCheckCircle(
                  checked: task.isCompleted,
                  size: 20,
                  color: color,
                  onTap: () async {
                    await state.tasks.toggle(task);
                    await _load();
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: task.source == TaskSource.calendar
                              ? AppColors.imported
                              : AppColors.textPrimary,
                          decoration:
                              task.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (task.remindTime != null)
                        Text(
                          '⏰ ${task.remindTime}',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
                if (task.source == TaskSource.calendar)
                  const Icon(Icons.event_available_outlined,
                      size: 15, color: AppColors.imported),
              ],
            ),
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, bottom: 6),
              child: Column(
                children: [
                  for (final child in children)
                    Row(
                      children: [
                        TaskCheckCircle(
                          checked: child.isCompleted,
                          size: 18,
                          onTap: () async {
                            await state.tasks.toggle(child);
                            await _load();
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            child.title,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              decoration: child.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
