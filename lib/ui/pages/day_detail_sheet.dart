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
/// （班次任务集 / 独立事项 / 导入的系统日历事项）+ 右下悬浮「+」。
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
  List<DailyTask> _importedTasks = [];

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
      _shiftTasks = tasks
          .where((t) => t.source == TaskSource.app && !t.isCustom)
          .toList();
      _customTasks = tasks
          .where((t) => t.source == TaskSource.app && t.isCustom)
          .toList();
      _importedTasks = tasks.where((t) => t.source == TaskSource.calendar).toList();
      _loading = false;
    });
  }

  ShiftType? get shift => state.tasks.effectiveShiftOfDay(date);

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
                              if (_shiftTasks.isEmpty && _customTasks.isEmpty && _importedTasks.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 40),
                                  child: EmptyHint(
                                    text: '今天还没有任务\n点右下角「+」新增独立事项，或在设置里配置班次任务模板',
                                    icon: Icons.checklist_rtl,
                                  ),
                                ),
                              _shiftSection(),
                              _customSection(),
                              _importedSection(),
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
    final lunar = LunarUtil.fromSolar(date);
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
              lunar.description(date),
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
                    '${s.startTime ?? '--:--'} — ${s.endTime ?? '--:--'}'
                    '${s.crossDay ? '（跨天）' : ''}',
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
          _taskCard(
            roots[i],
            _shiftTasks.where((t) => t.parentId == roots[i].id).toList(),
            number: i + 1,
          ),
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
          _taskCard(
            roots[i],
            _customTasks.where((t) => t.parentId == roots[i].id).toList(),
            number: 0,
            accent: AppColors.textSecondary,
          ),
      ],
    );
  }

  Widget _importedSection() {
    if (_importedTasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('系统日历导入', trailing: '${_importedTasks.length} 条'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _importedTasks.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 44),
                _importedTile(_importedTasks[i]),
              ],
            ],
          ),
        ),
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

  /// 一张任务卡（图 2 里的「编号方块 + 标题 + 重复标签 + 收起的子任务」）。
  Widget _taskCard(DailyTask task, List<DailyTask> children) {
    final shiftColor = task.shiftTypeId == null
        ? AppColors.primary
        : AppColors.fromHex(state.shifts.byId(task.shiftTypeId)?.colorHex ?? '#1F9E8F');
    final number = _shiftTasks
            .where((t) => t.parentId == null)
            .toList()
            .indexOf(task) +
        1;
    final collapsed = _collapsed.contains(task.id);

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
                  onTap: () async {
                    await state.tasks.toggle(task);
                    await _load();
                    await state.refreshCounts();
                  },
                ),
                _menu(task),
              ],
            ),
          ),
          if (children.isNotEmpty) ...[
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
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 0, 12, 2),
                  child: Row(
                    children: [
                      TaskCheckCircle(
                        checked: child.isCompleted,
                        onTap: () async {
                          await state.tasks.toggle(child);
                          await _load();
                          await state.refreshCounts();
                        },
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          child.title,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.textPrimary,
                            decoration:
                                child.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      _menu(child, compact: true),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _importedTile(DailyTask task) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          TaskCheckCircle(
            checked: task.isCompleted,
            size: 20,
            onTap: () async {
              await state.tasks.toggle(task);
              await _load();
              await state.refreshCounts();
            },
          ),
          const SizedBox(width: 6),
          const Icon(Icons.event_available_outlined, size: 15, color: AppColors.imported),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: AppColors.imported,
                decoration: task.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
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
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'remind', child: Text('设置提醒时间')),
        if (task.parentId == null) const PopupMenuItem(value: 'add-child', child: Text('添加子任务')),
        const PopupMenuItem(value: 'to-template', child: Text('一键转为模板任务')),
        const PopupMenuItem(value: 'delete', child: Text('删除此任务（仅今天）')),
      ],
    );
  }

  // ------------------------------------------------------------ 交互

  Future<void> _pickShift() async {
    final result = await showShiftPicker(context, state, date);
    if (result == null) return;
    await state.shifts.setException(date, result == -1 ? null : result);
    await state.refreshAll();
    await _load();
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
    final text = await _promptText('新增子任务', '');
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
                            '${s.startTime ?? '--:--'} - ${s.endTime ?? '--:--'}'
                            '${s.crossDay ? ' · 跨天（任务归属结束日）' : ''}',
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
