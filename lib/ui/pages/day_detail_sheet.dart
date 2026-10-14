import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../models/models.dart';
import '../../utils/lunar.dart';
import '../app_state.dart';
import '../widgets/common.dart';

/// 底部上滑的「当日详情」弹窗。
///
/// 视觉参考图 2：青绿头部日期条 + 白色卡片列表
/// （班次任务集 / 独立事项）+ 右下悬浮「+」。
Future<void> showDayDetailSheet(BuildContext context, AppState state, DateTime date) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DayDetailSheet(state: state, date: DayUtil.dateOnly(date)),
  );
}

class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({super.key, required this.state, required this.date});

  final AppState state;
  final DateTime date;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  AppState get state => widget.state;
  DateTime get date => widget.date;
  bool _loading = true;
  List<DailyTask> _shiftTasks = [];
  List<DailyTask> _customTasks = [];

  final Set<int> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tasks = await state.tasks.ensureAndLoad(date);
    if (!mounted) return;
    setState(() {
      _shiftTasks = tasks.where((t) => !t.isCustom).toList();
      _customTasks = tasks.where((t) => t.isCustom).toList();
      _loading = false;
    });
  }

  /// 当天归属的班次（夜班算在结束那一天）。
  ShiftType? get shift => state.tasks.shiftOfDay(date);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.9;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 90),
                            children: [
                              if (_shiftTasks.isEmpty && _customTasks.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 40),
                                  child: EmptyHint(
                                    text: '今天还没有任务\n点右下角「+」新增独立事项，或在设置里配置班次任务模板',
                                    icon: Icons.checklist_rtl,
                                  ),
                                ),
                              _shiftSection(),
                              _customSection(),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 18,
                          bottom: 18,
                          child: FloatingActionButton(
                            heroTag: 'add-task',
                            onPressed: _addTask,
                            child: const Icon(Icons.add, size: 28),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 头部

  Widget _header() {
    final s = shift;
    final color = s == null ? AppColors.primary : AppColors.fromHex(s.colorHex);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.18)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                '${date.year}年${date.month}月${date.day}日 星期${DayUtil.weekdayShort[(date.weekday - 1) % 7]}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '切换当天班次',
                onPressed: _pickShift,
                icon: const Icon(Icons.swap_horiz, color: Colors.white),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'clear-day') _clearDay();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'clear-day', child: Text('清空当天任务')),
                ],
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              LunarUtil.description(date),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(56),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        s == null ? '未排班（点击切换）' : s.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (s != null && (s.startTime != null || s.endTime != null)) ...[
                  const SizedBox(width: 8),
                  Text(
                    // 夜班（22:00 → 次日 07:30）标出「次日」，一眼看出时间跨了午夜。
                    '${s.startTime ?? '--:--'} — '
                    '${s.startsPreviousDay ? '次日 ' : ''}${s.endTime ?? '--:--'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
                if (state.shifts.exceptionOf(date) != null) ...[
                  const SizedBox(width: 8),
                  const Text(
                    '单天覆盖',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- 班次任务卡片

  Widget _shiftSection() {
    if (_shiftTasks.isEmpty) return const SizedBox.shrink();
    final roots = _shiftTasks.where((t) => t.parentId == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('班次任务', trailing: '${_doneCount(_shiftTasks)}/${_shiftTasks.length}'),
        for (var i = 0; i < roots.length; i++)
          _taskCard(roots[i], number: i + 1),
      ],
    );
  }

  Widget _customSection() {
    if (_customTasks.isEmpty) return const SizedBox.shrink();
    final roots = _customTasks.where((t) => t.parentId == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('独立事项', trailing: '${_doneCount(_customTasks)}/${_customTasks.length}'),
        for (var i = 0; i < roots.length; i++)
          _taskCard(roots[i], number: 0, accent: AppColors.textSecondary),
      ],
    );
  }

  Widget _sectionLabel(String text, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  int _doneCount(List<DailyTask> list) =>
      list.where((t) => t.parentId == null && t.isCompleted).length;

  /// 当天的全部任务（两个板块合起来，用于找父子关系）。
  List<DailyTask> get _allTasks => [..._shiftTasks, ..._customTasks];

  /// 某个任务的直接下级。
  List<DailyTask> _childrenOf(DailyTask parent) {
    final id = parent.id;
    if (id == null) return const [];
    return _allTasks.where((t) => t.parentId == id).toList();
  }

  /// 任务所处层级：顶层 = 0（决定缩进，以及还能不能再加下级）。
  int _depthOf(DailyTask task) {
    final all = _allTasks;
    var depth = 0;
    var cursor = task;
    var guard = 0;
    while (cursor.parentId != null && guard++ < 8) {
      DailyTask? parent;
      for (final t in all) {
        if (t.id == cursor.parentId) {
          parent = t;
          break;
        }
      }
      if (parent == null) break;
      cursor = parent;
      depth++;
    }
    return depth;
  }

  /// 某个任务的全部下级（层级从 1 开始），最多三层：任务 → 子任务 → 孙任务。
  List<MapEntry<DailyTask, int>> _descendantsOf(DailyTask root,
      [int depth = 1]) {
    final result = <MapEntry<DailyTask, int>>[];
    if (depth > 2) return result;
    for (final child in _childrenOf(root)) {
      result.add(MapEntry(child, depth));
      result.addAll(_descendantsOf(child, depth + 1));
    }
    return result;
  }

  Future<void> _toggle(DailyTask task) async {
    await state.tasks.toggle(task);
    await _load();
    await state.refreshCounts();
  }

  /// 一张任务卡（「编号方块 + 标题 + 重复/提醒标签 + 可收起的下级」）。
  /// [number] 大于 0 时显示左上角的编号方块（0 表示不显示）；
  /// [accent] 覆盖强调色 —— 班次任务用所属班次色，独立事项用灰色。
  Widget _taskCard(DailyTask task, {int number = 0, Color? accent}) {
    final shiftColor = accent ??
        (task.shiftTypeId == null
            ? AppColors.primary
            : AppColors.fromHex(
                state.shifts.byId(task.shiftTypeId)?.colorHex ?? '#1F9E8F'));
    final collapsed = _collapsed.contains(task.id);
    final descendants = _descendantsOf(task);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (number > 0) ...[
                  NumberBadge(number: number, color: shiftColor),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (task.templateId != null)
                            const PillTag(text: '重复', icon: Icons.autorenew),
                          if (task.remindTime != null)
                            PillTag(
                              text: task.remindTime!,
                              icon: Icons.alarm,
                              color: AppColors.textSecondary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                TaskCheckCircle(
                  checked: task.isCompleted,
                  size: 24,
                  color: shiftColor,
                  onTap: () => _toggle(task),
                ),
                _menu(task),
              ],
            ),
          ),
          if (descendants.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 6),
              child: GestureDetector(
                onTap: () => setState(() {
                  final id = task.id;
                  if (id == null) return;
                  if (collapsed) {
                    _collapsed.remove(id);
                  } else {
                    _collapsed.add(id);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        collapsed ? '展开' : '收起',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed)
              for (final entry in descendants)
                _childRow(entry.key, entry.value, shiftColor),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 一行下级任务（缩进随层级增加；第 3 层的孙任务不能再往下加）。
  Widget _childRow(DailyTask child, int depth, Color accent) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.0 + depth * 14, 0, 4, 2),
      child: Row(
        children: [
          TaskCheckCircle(
            checked: child.isCompleted,
            size: depth == 1 ? 20.0 : 18.0,
            color: accent,
            onTap: () => _toggle(child),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              child.title,
              style: TextStyle(
                fontSize: depth == 1 ? 14 : 13,
                height: 1.4,
                color: depth == 1 ? AppColors.textPrimary : AppColors.textSecondary,
                decoration: child.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          _menu(child, compact: true),
        ],
      ),
    );
  }

  Widget _menu(DailyTask task, {bool compact = false}) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: compact ? 17 : 19,
      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _rename(task);
            break;
          case 'remind':
            await _setRemind(task);
            break;
          case 'add-child':
            await _addChild(task);
            break;
          case 'to-template':
            await _toTemplate(task);
            break;
          case 'delete':
            await _delete(task);
            break;
        }
      },
      itemBuilder: (context) {
        final depth = _depthOf(task);
        return [
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'remind', child: Text('设置提醒时间')),
          if (depth < 2)
            PopupMenuItem(
              value: 'add-child',
              child: Text(depth == 0 ? '添加子任务' : '添加孙任务'),
            ),
          const PopupMenuItem(value: 'to-template', child: Text('一键转为模板任务')),
          const PopupMenuItem(value: 'delete', child: Text('删除此任务（仅今天）')),
        ];
      },
    );
  }

  // ------------------------------------------------------------ 交互

  Future<void> _pickShift() async {
    final result = await showShiftPicker(context, state, date);
    if (result == null) return;
    await state.shifts.setException(date, result == -1 ? null : result);
    // 这一天的班次变了：让这天重新按新班次对账（旧班次留下的未完成任务会被清掉）。
    await state.tasks.refreshDay(date);
    await state.refreshAll();
    await _load();
  }

  /// 清空当天全部任务（右上角「···」菜单）。
  ///
  /// 用户要求：一键清空、清空前先确认、清空后当天不再自动补回来。
  Future<void> _clearDay() async {
    final count = _allTasks.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当天没有任务')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空当天任务'),
        content: Text(
          '确定清空 ${date.year}年${date.month}月${date.day}日 的 $count 条任务吗？'
          '清空后当天不会自动补回来（第二天照常生成）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await state.tasks.clearDay(date);
    await state.refreshAll();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清空当天的 $count 条任务')),
    );
  }

  Future<void> _rename(DailyTask task) async {
    final text = await _promptText('重命名任务', task.title);
    if (text == null || text.trim().isEmpty) return;
    await state.tasks.renameTask(task.id!, text.trim());
    await _load();
  }

  Future<void> _setRemind(DailyTask task) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(task.remindTime) ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await state.tasks.setRemind(task.id!, text);
    await _load();
  }

  Future<void> _addChild(DailyTask parent) async {
    final text = await _promptText(
      _depthOf(parent) == 0 ? '新增子任务' : '新增孙任务',
      '',
    );
    if (text == null || text.trim().isEmpty) return;
    await state.tasks.addChildTask(parent: parent, title: text.trim());
    await _load();
    await state.refreshCounts();
  }

  Future<void> _delete(DailyTask task) async {
    await state.tasks.deleteTask(task);
    await _load();
    await state.refreshCounts();
  }

  Future<void> _toTemplate(DailyTask task) async {
    final target = await showShiftPicker(context, state, date, title: '把「${task.title}」附加到哪个班次的模板？');
    if (target == null) return;
    final shiftId = target == -1 ? null : target;
    if (shiftId == null) {
      _toast('请选择一个班次');
      return;
    }
    await state.templates.insert(shiftTypeId: shiftId, title: task.title);
    _toast('已加入模板：${state.shifts.byId(shiftId)?.name ?? ''}（明天起按模板生成）');
  }

  Future<void> _addTask() async {
    final created = await showAddTaskDialog(context, state, date);
    if (created == true) {
      await _load();
      await state.refreshCounts();
    }
  }

  Future<String?> _promptText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: appInputDecoration(hintText: '请输入内容'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static TimeOfDay? _parseTime(String? text) {
    if (text == null || !text.contains(':')) return null;
    final parts = text.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }
}

/// 新增独立事项对话框。
Future<bool?> showAddTaskDialog(BuildContext context, AppState state, DateTime date) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _AddTaskDialog(state: state, date: date),
  );
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog({required this.state, required this.date});

  final AppState state;
  final DateTime date;

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  TimeOfDay? _remind;
  bool _asTemplate = false;
  int? _templateShiftId;

  @override
  void initState() {
    super.initState();
    _templateShiftId = widget.state.tasks.shiftOfDay(widget.date)?.id;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shifts = widget.state.shifts.activeShiftTypes;
    return AlertDialog(
      title: const Text('新增事项'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: appInputDecoration(hintText: '事项标题，例如：机组启停'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: appInputDecoration(hintText: '备注（可选）'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.alarm, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text('提醒时间', style: TextStyle(fontSize: 13)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _remind ?? const TimeOfDay(hour: 10, minute: 0),
                    );
                    if (picked != null) setState(() => _remind = picked);
                  },
                  child: Text(
                    _remind == null
                        ? '未设置'
                        : '${_remind!.hour.toString().padLeft(2, '0')}:'
                            '${_remind!.minute.toString().padLeft(2, '0')}',
                  ),
                ),
                if (_remind != null)
                  IconButton(
                    iconSize: 18,
                    onPressed: () => setState(() => _remind = null),
                    icon: const Icon(Icons.clear, color: AppColors.textMuted),
                  ),
              ],
            ),
            const Divider(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _asTemplate,
              onChanged: (v) => setState(() => _asTemplate = v),
              title: const Text('同时加入班次模板', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '勾选后，以后每个该班次的日子都会自动生成这条任务',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            if (_asTemplate)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in shifts)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: _templateShiftId == s.id,
                      onSelected: (_) => setState(() => _templateShiftId = s.id),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final remind = _remind == null
        ? null
        : '${_remind!.hour.toString().padLeft(2, '0')}:'
            '${_remind!.minute.toString().padLeft(2, '0')}';

    await widget.state.tasks.addCustomTask(
      date: widget.date,
      title: title,
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      remindTime: remind,
      shiftTypeId: widget.state.tasks.shiftOfDay(widget.date)?.id,
    );

    if (_asTemplate && _templateShiftId != null) {
      await widget.state.templates.insert(
        shiftTypeId: _templateShiftId!,
        title: title,
        remindTime: remind,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }
}

/// 班次选择器。返回：
///  * `null`  —— 用户取消
///  * `-1`    —— 清除单天覆盖（恢复按周期计算）
///  * `其它`  —— 选中的 shift_type.id
Future<int?> showShiftPicker(
  BuildContext context,
  AppState state,
  DateTime date, {
  String title = '切换当天班次',
}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  DayUtil.iso(date),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Text(
            '只影响这一天，不改变排班周期',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in state.shifts.activeShiftTypes)
                  ListTile(
                    leading: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.fromHex(s.colorHex),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    title: Text(s.name),
                    subtitle: (s.startTime != null || s.endTime != null)
                        ? Text(
                            '${s.startTime ?? '--:--'} - ${s.endTime ?? '--:--'}',
                            style: const TextStyle(fontSize: 11.5),
                          )
                        : null,
                    trailing: state.shifts.exceptionOf(date) == s.id
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(s.id),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt, color: AppColors.textSecondary),
                  title: const Text('恢复按排班周期计算'),
                  onTap: () => Navigator.of(ctx).pop(-1),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
