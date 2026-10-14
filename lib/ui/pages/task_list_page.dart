import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../app_state.dart';
import '../widgets/common.dart';
import 'day_detail_sheet.dart';

/// 任务清单页。
///
/// 默认视图是「今天」：今天需要完成的任务（默认只看未完成），
/// 支持三层缩进与勾选联动（子任务全勾 → 父任务自动完成）。
/// 切到「全部」可以跨日期查看、搜索历史任务。
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
  bool _todayOnly = true;
  bool _hideCompleted = true;
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
    final today = DayUtil.today();
    final List<DailyTask> tasks;
    if (_keyword.trim().isNotEmpty) {
      tasks = await state.tasks.search(_keyword);
    } else if (_todayOnly) {
      // ensureAndLoad：先按模板补齐今天的任务，再返回当天的全部任务。
      tasks = await state.tasks.ensureAndLoad(today);
    } else {
      tasks = await state.tasks.tasksInRange(
        DayUtil.addDays(today, -180),
        DayUtil.addDays(today, 180),
      );
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _toggle(DailyTask task) async {
    await state.tasks.toggle(task);
    await _load();
    await state.refreshCounts();
  }

  Future<void> _openDay(DateTime date) async {
    await state.selectDate(date);
    if (!mounted) return;
    await showDayDetailSheet(context, state, date);
    await _load();
  }

  bool _matches(DailyTask t) => !_hideCompleted || !t.isCompleted;

  List<DailyTask> _childrenOf(List<DailyTask> all, DailyTask parent) {
    final id = parent.id;
    if (id == null) return const [];
    return all.where((t) => t.parentId == id).toList();
  }

  /// 该任务自己或它的某个下级还需要完成（用于「只看未完成」时保留父任务行）。
  bool _needsWork(List<DailyTask> all, DailyTask task, [int depth = 0]) {
    if (_matches(task)) return true;
    if (depth > 3) return false;
    return _childrenOf(all, task).any((c) => _needsWork(all, c, depth + 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toolbar(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(child: _todayOnly ? _todayBody() : _allBody()),
      ],
    );
  }

  // ======================================================== 顶部工具栏

  Widget _toolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              _segment('今天', true),
              const SizedBox(width: 8),
              _segment('全部', false),
              const Spacer(),
              const Text('只看未完成', style: TextStyle(fontSize: 12.5)),
              Switch(
                value: _hideCompleted,
                onChanged: (v) => setState(() => _hideCompleted = v),
              ),
            ],
          ),
          if (!_todayOnly) ...[
            const SizedBox(height: 2),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _keyword = v;
                _load();
              },
              decoration: appInputDecoration(
                hintText: '搜索全部任务标题…',
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
          ],
        ],
      ),
    );
  }

  Widget _segment(String label, bool today) {
    final selected = _todayOnly == today;
    return GestureDetector(
      onTap: () {
        if (selected) return;
        setState(() {
          _todayOnly = today;
          if (today) {
            _keyword = '';
            _searchController.clear();
          }
        });
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.tint(AppColors.primary, 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ======================================================== 今天

  Widget _todayBody() {
    final today = DayUtil.today();
    final all = _tasks;
    final shift = state.tasks.shiftOfDay(today);
    final accent = shift == null ? AppColors.primary : AppColors.fromHex(shift.colorHex);
    final roots = all.where((t) => t.parentId == null && _needsWork(all, t)).toList();
    // 拖动排序要照顾「被隐藏（已完成）的同级任务」：它们保持原来的位置。
    final allRoots = all.where((t) => t.parentId == null).toList()
      ..sort((a, b) {
        final d = a.sortOrder.compareTo(b.sortOrder);
        return d != 0 ? d : (a.id ?? 0).compareTo(b.id ?? 0);
      });

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _todayHeader(today, shift, accent),
          if (roots.isEmpty)
            _emptyToday()
          else
            // 顶层任务卡可以长按拖动排序（只影响当天）。
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              onReorder: (oldIndex, newIndex) =>
                  _reorderAmongVisible(allRoots, roots, oldIndex, newIndex),
              children: [
                for (var i = 0; i < roots.length; i++)
                  KeyedSubtree(
                    key: ValueKey('card-${roots[i].id}'),
                    child: _card(all, roots[i], i + 1, accent),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _todayHeader(DateTime today, ShiftType? shift, Color accent) {
    final total = _tasks.length;
    final done = _tasks.where((t) => t.isCompleted).length;
    final ratio = total == 0 ? 0.0 : done / total;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.tint(accent, 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '今天 · ${today.month}月${today.day}日 星期${DayUtil.weekdayShort[(today.weekday - 1) % 7]}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (shift != null) PillTag(text: shift.name, color: accent),
              const Spacer(),
              Text(
                '$done/$total',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              IconButton(
                tooltip: '打开当天详情',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => _openDay(today),
                icon: const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: Colors.white,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyToday() {
    final allDone = _tasks.isNotEmpty && _tasks.every((t) => t.isCompleted);
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: EmptyHint(
        text: allDone
            ? '今天的任务都完成啦 🎉'
            : '今天还没有任务\n可以在「班次任务模板」里配置，或打开当天详情添加独立事项',
        icon: allDone ? Icons.celebration_outlined : Icons.inbox_outlined,
      ),
    );
  }

  // ======================================================== 全部

  Widget _allBody() {
    final all = _tasks;
    final groups = <String, List<DailyTask>>{};
    for (final task in all) {
      if (!_matches(task)) continue;
      final key = task.date ?? task.shiftDate ?? '未定日期';
      groups.putIfAbsent(key, () => []).add(task);
    }
    final keys = groups.keys.toList()..sort();

    if (keys.isEmpty) {
      return const EmptyHint(text: '没有匹配的任务', icon: Icons.search_off);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: keys.length,
        itemBuilder: (context, index) => _dayGroup(all, keys[index], groups[keys[index]]!),
      ),
    );
  }

  Widget _dayGroup(List<DailyTask> all, String iso, List<DailyTask> list) {
    final date = DayUtil.tryParseIso(iso);
    final shift = date == null ? null : state.tasks.shiftOfDay(date);
    final accent = shift == null ? AppColors.primary : AppColors.fromHex(shift.colorHex);
    final roots = list.where((t) => t.parentId == null).toList();
    final done = roots.where((t) => t.isCompleted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: accent,
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
                Text(shift.name, style: TextStyle(fontSize: 11.5, color: accent)),
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
                  onPressed: () => _openDay(date),
                  icon: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        for (var i = 0; i < roots.length; i++)
          _card(all, roots[i], i + 1, accent),
      ],
    );
  }

  // ======================================================== 任务卡

  /// 一张任务卡：编号方块 + 标题 + 下级（子任务 / 孙任务）。
  ///
  /// 每一层的兄弟任务都能长按拖动排序（只影响这一天）。
  Widget _card(
    List<DailyTask> all,
    DailyTask root,
    int number,
    Color accent,
  ) {
    final shiftColor = root.shiftTypeId == null
        ? accent
        : AppColors.fromHex(
            state.shifts.byId(root.shiftTypeId)?.colorHex ?? '#1F9E8F');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(root, 0, shiftColor, number: number),
          _childList(all, root, 1, shiftColor),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 某个任务的下一层（整层可长按拖动排序，最多三层）。
  Widget _childList(List<DailyTask> all, DailyTask parent, int depth, Color accent) {
    if (depth > 2) return const SizedBox.shrink();
    final children = _childrenOf(all, parent);
    if (children.isEmpty) return const SizedBox.shrink();

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      onReorder: (oldIndex, newIndex) =>
          _reorderSiblings(children, oldIndex, newIndex),
      children: [
        for (final child in children)
          KeyedSubtree(
            key: ValueKey('task-${child.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(child, depth, accent, outline: true),
                _childList(all, child, depth + 1, accent),
              ],
            ),
          ),
      ],
    );
  }

  /// 拖动结束：按新顺序重排这一层的兄弟任务（只影响这一天）。
  Future<void> _reorderSiblings(
    List<DailyTask> siblings,
    int oldIndex,
    int newIndex,
  ) =>
      _reorderAmongVisible(siblings, siblings, oldIndex, newIndex);

  /// 拖动结束：[visible] 是界面上真正能拖的那些（可能因为「只看未完成」少了几条），
  /// [allSiblings] 是这一层的**全部**任务 —— 被隐藏的那些保持原来的槽位不动，
  /// 这样重新编号后 `sort_order` 不会和隐藏项撞车。
  Future<void> _reorderAmongVisible(
    List<DailyTask> allSiblings,
    List<DailyTask> visible,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final order = [...visible];
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);

    final visibleIds = order.map((t) => t.id).toSet();
    final merged = <DailyTask>[];
    var cursor = 0;
    for (final item in allSiblings) {
      if (visibleIds.contains(item.id)) {
        merged.add(order[cursor++]);
      } else {
        merged.add(item);
      }
    }
    await state.tasks.reorderSiblings(merged);
    if (!mounted) return;
    await _load();
    await state.refreshCounts();
  }

  Widget _row(
    DailyTask task,
    int depth,
    Color accent, {
    int number = 0,
    bool outline = false,
  }) {
    final indent = depth == 0 ? 12.0 : 20.0 + depth * 16;
    final fontSize = depth == 0 ? 14.5 : (depth == 1 ? 13.5 : 12.5);
    final color = depth == 0 ? AppColors.textPrimary : AppColors.textSecondary;

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, depth == 0 ? 10 : 1, 6, depth == 0 ? 8 : 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (number > 0) ...[
            NumberBadge(number: number, color: accent),
            const SizedBox(width: 10),
          ] else if (outline && depth == 1) ...[
            const Icon(Icons.subdirectory_arrow_right,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
          ],
          TaskCheckCircle(
            checked: task.isCompleted,
            size: depth == 0 ? 22.0 : (depth == 1 ? 20.0 : 18.0),
            color: accent,
            onTap: () => _toggle(task),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.35,
                    color: color,
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
        ],
      ),
    );
  }
}
