import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../models/models.dart';
import '../../services/backup_service.dart';
import '../../services/calendar_service.dart';
import '../app_state.dart';
import '../widgets/common.dart';

// =============================================================== 设置首页

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state, this.onDataChanged});

  final AppState state;

  /// 数据被整体重建（导入备份 / 恢复出厂）后通知外壳刷新各页。
  final VoidCallback? onDataChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        _group('排班'),
        _tile(
          icon: Icons.event_note,
          title: '排班规则管理',
          subtitle: _cycleSummary(),
          route: '/shifts',
        ),
        _tile(
          icon: Icons.checklist,
          title: '班次任务模板',
          subtitle: '共 ${state.templates.total} 条模板任务',
          route: '/templates',
        ),
        _group('数据'),
        _tile(
          icon: Icons.import_export,
          title: '数据导入 / 导出',
          subtitle: 'JSON 全量备份与恢复',
          route: '/data',
        ),
        _tile(
          icon: Icons.calendar_month,
          title: '系统日历同步',
          subtitle: '单向导入：系统日历 → DDtodo',
          route: '/calendar',
        ),
        _group('显示'),
        SwitchListTile(
          secondary: const Icon(Icons.brightness_2_outlined, color: AppColors.primary),
          title: const Text('日历显示农历', style: TextStyle(fontSize: 14.5)),
          subtitle: const Text('日期格下方显示农历、节气与节日',
              style: TextStyle(fontSize: 11.5)),
          value: settings.showLunar,
          onChanged: (v) async {
            await settings.setShowLunar(v);
            setState(() {});
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.view_week_outlined, color: AppColors.primary),
          title: const Text('每周从周一开始', style: TextStyle(fontSize: 14.5)),
          subtitle: const Text('关闭后从周日开始排列', style: TextStyle(fontSize: 11.5)),
          value: settings.weekStartMonday,
          onChanged: (v) async {
            await settings.setWeekStartMonday(v);
            setState(() {});
            await state.refreshCounts();
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined, color: AppColors.primary),
          title: const Text('跨天班次默认归属结束日', style: TextStyle(fontSize: 14.5)),
          subtitle: const Text('如晚班 20:00 → 次日 08:00，任务算在次日清单',
              style: TextStyle(fontSize: 11.5)),
          value: settings.defaultCrossDay,
          onChanged: (v) async {
            await settings.setDefaultCrossDay(v);
            setState(() {});
          },
        ),
        _group('关于'),
        _tile(
          icon: Icons.info_outline,
          title: '关于 DDtodo',
          subtitle: '版本 1.0.0 · 纯本地，无需联网',
          route: '/about',
        ),
      ],
    );
  }

  String _cycleSummary() {
    final cycles = state.shifts.cycles;
    if (cycles.isEmpty) return '尚未设置排班周期';
    final active = state.shifts.activeCycleFor(DayUtil.today());
    if (active == null) return '共 ${cycles.length} 条规则（当前无生效规则）';
    return '当前生效：${active.name}（${active.pattern.length} 天一轮）';
  }

  Widget _group(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontSize: 14.5)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
        onTap: () => Navigator.of(context).pushNamed(route),
      ),
    );
  }
}

// ========================================================== 排班规则管理

class ShiftSettingsPage extends StatefulWidget {
  const ShiftSettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<ShiftSettingsPage> createState() => _ShiftSettingsPageState();
}

class _ShiftSettingsPageState extends State<ShiftSettingsPage> {
  AppState get state => widget.state;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('排班规则管理'),
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [Tab(text: '班次类型'), Tab(text: '周期模式')],
          ),
        ),
        body: TabBarView(
          children: [_shiftTypeTab(), _cycleTab()],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _tab == 0 ? _editShiftType : _editCycle,
          icon: const Icon(Icons.add),
          label: Text(_tab == 0 ? '新增班次' : '新增周期'),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 班次类型

  Widget _shiftTypeTab() {
    final types = state.shifts.shiftTypes;
    if (types.isEmpty) {
      return const EmptyHint(text: '还没有班次类型');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '预置班次可以改颜色、改时间、改名；跨天班次的任务会自动归属到结束日。',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5),
          ),
        ),
        for (final type in types) _shiftTypeTile(type),
      ],
    );
  }

  Widget _shiftTypeTile(ShiftType type) {
    final color = AppColors.fromHex(type.colorHex);
    final time = (type.startTime == null && type.endTime == null)
        ? '未设置时间'
        : '${type.startTime ?? '--:--'} - ${type.endTime ?? '--:--'}'
            '${type.crossDay ? ' · 跨天（任务归属结束日）' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            type.isRest ? Icons.bedtime_outlined : Icons.work_outline,
            size: 18,
            color: AppColors.onColor(color),
          ),
        ),
        title: Row(
          children: [
            Text(type.name, style: const TextStyle(fontSize: 14.5)),
            if (type.isPreset) ...[
              const SizedBox(width: 6),
              const PillTag(text: '预置', color: AppColors.textSecondary),
            ],
            if (type.archived) ...[
              const SizedBox(width: 6),
              const PillTag(text: '已归档', color: AppColors.textMuted),
            ],
          ],
        ),
        subtitle: Text(time, style: const TextStyle(fontSize: 11.5)),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                await _editShiftType(existing: type);
                break;
              case 'restore':
                await state.shifts.restoreShiftType(type.id!);
                setState(() {});
                break;
              case 'delete':
                await _confirmDelete(type);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('编辑')),
            if (type.archived)
              const PopupMenuItem(value: 'restore', child: Text('取消归档')),
            if (!type.archived)
              const PopupMenuItem(value: 'delete', child: Text('删除 / 归档')),
          ],
        ),
        onTap: () => _editShiftType(existing: type),
      ),
    );
  }

  Future<void> _confirmDelete(ShiftType type) async {
    final counts = await state.shifts.templateCountByShift();
    final used = counts[type.id] ?? 0;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${type.name}」？'),
        content: Text(
          used > 0
              ? '该班次还有 $used 条模板任务引用它。删除后会改为「归档」：\n'
                  '· 历史记录仍能正确显示颜色和名称；\n'
                  '· 新建排班时不再出现在选择列表。'
              : '该班次没有被模板或周期引用，会被直接删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await state.shifts.deleteShiftType(type.id!);
    setState(() {});
  }

  Future<void> _editShiftType({ShiftType? existing}) async {
    final result = await showShiftTypeEditor(context, state, existing: existing);
    if (result == null) return;
    if (existing == null) {
      await state.shifts.insertShiftType(result);
    } else {
      await state.shifts.updateShiftType(result);
    }
    setState(() {});
  }

  // ------------------------------------------------------------ 周期模式

  Widget _cycleTab() {
    final cycles = state.shifts.cycles;
    final today = DayUtil.today();
    if (cycles.isEmpty) {
      return const EmptyHint(
        text: '还没有排班周期\n点右下角「新增周期」设置「几天一轮 + 每天什么班」',
        icon: Icons.event_note,
      );
    }
    final sorted = [...cycles]..sort((a, b) => b.startDate.compareTo(a.startDate));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '按生效日期取「最近一条」规则无限循环。改规则只影响今天及以后，不会追溯调整过去的排班。',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5),
          ),
        ),
        for (final cycle in sorted) _cycleTile(cycle, today),
      ],
    );
  }

  Widget _cycleTile(ShiftCycle cycle, DateTime today) {
    final active = state.shifts.activeCycleFor(today);
    final isActive = active?.id == cycle.id;
    final start = DayUtil.tryParseIso(cycle.startDate);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.divider,
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            title: Row(
              children: [
                Text(cycle.name, style: const TextStyle(fontSize: 14.5)),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  const PillTag(text: '生效中'),
                ],
              ],
            ),
            subtitle: Text(
              '生效日期 ${cycle.startDate}（周${start == null ? '?' : DayUtil.weekdayShort[(start.weekday - 1) % 7]}）'
              ' · ${cycle.pattern.length} 天一轮',
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editCycle(existing: cycle);
                } else if (value == 'delete') {
                  await state.shifts.deleteCycle(cycle.id!);
                  setState(() {});
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < cycle.pattern.length; i++)
                  _patternChip(
                    '第${i + 1}天',
                    state.shifts.byId(cycle.pattern[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patternChip(String label, ShiftType? type) {
    final color = type == null ? AppColors.textMuted : AppColors.fromHex(type.colorHex);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(color, 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.tint(color, 0.5)),
      ),
      child: Text(
        '$label ${type?.name ?? '未设置'}',
        style: TextStyle(fontSize: 11.5, color: color),
      ),
    );
  }

  Future<void> _editCycle({ShiftCycle? existing}) async {
    final result = await showCycleEditor(context, state, existing: existing);
    if (result == null) return;
    if (existing == null) {
      await state.shifts.createCycle(
        name: result.name,
        startDate: result.startDate,
        pattern: result.pattern,
      );
    } else {
      await state.shifts.updateCycle(ShiftCycle(
        id: existing.id,
        name: result.name,
        startDate: DayUtil.iso(result.startDate),
        pattern: result.pattern,
      ));
    }
    setState(() {});
    await state.refreshAll();
  }
}

// --------------------------------------------------- 班次类型编辑对话框

Future<ShiftType?> showShiftTypeEditor(
  BuildContext context,
  AppState state, {
  ShiftType? existing,
}) {
  return showDialog<ShiftType>(
    context: context,
    builder: (_) => _ShiftTypeEditor(state: state, existing: existing),
  );
}

class _ShiftTypeEditor extends StatefulWidget {
  const _ShiftTypeEditor({required this.state, this.existing});

  final AppState state;
  final ShiftType? existing;

  @override
  State<_ShiftTypeEditor> createState() => _ShiftTypeEditorState();
}

class _ShiftTypeEditorState extends State<_ShiftTypeEditor> {
  late final TextEditingController _nameController;
  late String _color;
  late bool _crossDay;
  late ShiftKind _kind;
  TimeOfDay? _start;
  TimeOfDay? _end;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _color = e?.colorHex ?? widget.state.shifts.nextPaletteColor();
    _crossDay = e?.crossDay ?? false;
    _kind = e?.kind ?? ShiftKind.custom;
    _start = _parse(e?.startTime);
    _end = _parse(e?.endTime);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static TimeOfDay? _parse(String? text) {
    if (text == null || !text.contains(':')) return null;
    final parts = text.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String? _format(TimeOfDay? time) => time == null
      ? null
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增班次类型' : '编辑班次类型'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: widget.existing == null,
              decoration: appInputDecoration(hintText: '班次名称，例如：夜班'),
            ),
            const SizedBox(height: 14),
            const Text('颜色（10 色可选）', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in AppColors.palette)
                  ColorDot(
                    color: color,
                    size: 28,
                    selected: AppColors.toHex(color).toUpperCase() == _color.toUpperCase(),
                    onTap: () => setState(() => _color = AppColors.toHex(color)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('类型（决定图标与归类）', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in ShiftKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() {
                      _kind = kind;
                      if (kind == ShiftKind.night) _crossDay = true;
                      if (kind == ShiftKind.rest) _crossDay = false;
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('跨天班次', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '例如 20:00 上班、次日 08:00 下班 —— 任务会归属到结束日那天',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _crossDay,
              onChanged: (v) => setState(() => _crossDay = v),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _start ?? const TimeOfDay(hour: 8, minute: 0),
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
                    child: Text('上班 ${_format(_start) ?? '未设置'}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _end ?? const TimeOfDay(hour: 17, minute: 0),
                      );
                      if (picked != null) setState(() => _end = picked);
                    },
                    child: Text('下班 ${_format(_end) ?? '未设置'}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(ShiftType(
              id: widget.existing?.id,
              name: name,
              colorHex: _color,
              isPreset: widget.existing?.isPreset ?? false,
              kind: _kind,
              crossDay: _crossDay,
              startTime: _format(_start),
              endTime: _format(_end),
              sortOrder: widget.existing?.sortOrder ?? 99,
              archived: widget.existing?.archived ?? false,
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// --------------------------------------------------- 排班周期编辑对话框

class CycleDraft {
  const CycleDraft({
    required this.name,
    required this.startDate,
    required this.pattern,
  });

  final String name;
  final DateTime startDate;
  final List<int> pattern;
}

Future<CycleDraft?> showCycleEditor(
  BuildContext context,
  AppState state, {
  ShiftCycle? existing,
}) {
  return showDialog<CycleDraft>(
    context: context,
    builder: (_) => _CycleEditor(state: state, existing: existing),
  );
}

class _CycleEditor extends StatefulWidget {
  const _CycleEditor({required this.state, this.existing});

  final AppState state;
  final ShiftCycle? existing;

  @override
  State<_CycleEditor> createState() => _CycleEditorState();
}

class _CycleEditorState extends State<_CycleEditor> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late List<int> _pattern;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _startDate = DayUtil.tryParseIso(e?.startDate) ?? DayUtil.today();
    _pattern = e == null ? <int>[] : [...e.pattern];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.state.shifts.shiftTypes.where((s) => !s.archived).toList();
    return AlertDialog(
      title: Text(widget.existing == null ? '新增排班周期' : '编辑排班周期'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: appInputDecoration(hintText: '规则名称，例如：两班两倒'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('生效日期', style: TextStyle(fontSize: 13)),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  child: Text(
                    '${DayUtil.iso(_startDate)}'
                    '（周${DayUtil.weekdayShort[(_startDate.weekday - 1) % 7]}）',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.primary, 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '选中日期就是新周期的第 1 天，之后按下面的顺序无限循环。\n'
                '此规则只影响生效日期及以后，不会追溯调整历史排班。',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.6),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('周期顺序（${_pattern.length} 天）',
                    style: const TextStyle(fontSize: 13)),
                const Spacer(),
                if (_pattern.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      if (_pattern.isNotEmpty) _pattern.removeLast();
                    }),
                    child: const Text('删掉最后一天'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _pattern.length; i++)
                  InputChip(
                    label: Text(
                      '${i + 1}.${widget.state.shifts.byId(_pattern[i])?.name ?? '?'}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onDeleted: () => setState(() => _pattern.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('点下面按钮往周期末尾追加一天：', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in types)
                  ActionChip(
                    avatar: CircleAvatar(
                      radius: 7,
                      backgroundColor: AppColors.fromHex(type.colorHex),
                    ),
                    label: Text(type.name),
                    onPressed: () => setState(() => _pattern.add(type.id!)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _pattern.isEmpty
              ? null
              : () {
                  final name = _nameController.text.trim().isEmpty
                      ? '排班规则'
                      : _nameController.text.trim();
                  Navigator.of(context).pop(CycleDraft(
                    name: name,
                    startDate: _startDate,
                    pattern: _pattern,
                  ));
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ============================================================ 模板管理

class TemplateSettingsPage extends StatefulWidget {
  const TemplateSettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<TemplateSettingsPage> createState() => _TemplateSettingsPageState();
}

class _TemplateSettingsPageState extends State<TemplateSettingsPage> {
  AppState get state => widget.state;
  int? _selectedShiftId;

  @override
  void initState() {
    super.initState();
    final shifts = state.shifts.activeShiftTypes;
    if (shifts.isNotEmpty) _selectedShiftId = shifts.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final shifts = state.shifts.activeShiftTypes;
    if (shifts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('班次任务模板')),
        body: const EmptyHint(text: '请先在「排班规则管理」里创建班次类型'),
      );
    }
    if (_selectedShiftId == null || state.shifts.byId(_selectedShiftId) == null) {
      _selectedShiftId = shifts.first.id;
    }

    final roots = state.templates.rootsFor(_selectedShiftId!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('班次任务模板'),
        actions: [
          IconButton(
            tooltip: '把当前班次的模板复制到别的班次',
            onPressed: _copyTo,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _shiftSelector(shifts),
          const Divider(height: 1),
          Expanded(
            child: roots.isEmpty
                ? const EmptyHint(
                    text: '这个班次还没有模板任务\n点右下角「+」新增一条',
                    icon: Icons.playlist_add,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          '班次确定后，这些任务会自动生成到当天的清单里：\n'
                          '· 子任务全部勾选 → 父任务自动完成；\n'
                          '· 在清单里删除某条任务只影响那一天，第二天照常生成。',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                            height: 1.6,
                          ),
                        ),
                      ),
                      for (var i = 0; i < roots.length; i++)
                        _templateCard(roots[i], i + 1),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTemplate(null),
        icon: const Icon(Icons.add),
        label: const Text('新增任务'),
      ),
    );
  }

  Widget _shiftSelector(List<ShiftType> shifts) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final shift in shifts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 7,
                    backgroundColor: AppColors.fromHex(shift.colorHex),
                  ),
                  label: Text(shift.name),
                  selected: _selectedShiftId == shift.id,
                  onSelected: (_) => setState(() => _selectedShiftId = shift.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _templateCard(TaskTemplate root, int number) {
    final children = state.templates.childrenOf(root.id);
    final shift = state.shifts.byId(_selectedShiftId);
    final color = shift == null ? AppColors.primary : AppColors.fromHex(shift.colorHex);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          ListTile(
            leading: NumberBadge(number: number, color: color),
            title: Text(root.title, style: const TextStyle(fontSize: 14.5)),
            subtitle: Text(
              children.isEmpty ? '无子任务' : '${children.length} 个子任务',
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: _templateMenu(root),
            onTap: () => _editTemplate(root),
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 52, right: 8, bottom: 8),
              child: Column(
                children: [
                  for (final child in children)
                    Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            child.title,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        _templateMenu(child, compact: true),
                      ],
                    ),
                ],
              ),
            ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 52, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addTemplate(root.id),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加子任务', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _templateMenu(TaskTemplate tpl, {bool compact = false}) {
    return PopupMenuButton<String>(
      iconSize: compact ? 17 : 20,
      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await _editTemplate(tpl);
            break;
          case 'up':
            await state.templates.move(tpl.id!, -1);
            setState(() {});
            break;
          case 'down':
            await state.templates.move(tpl.id!, 1);
            setState(() {});
            break;
          case 'delete':
            await state.templates.delete(tpl.id!);
            setState(() {});
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuItem(value: 'up', child: Text('上移')),
        const PopupMenuItem(value: 'down', child: Text('下移')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
  }

  Future<void> _addTemplate(int? parentId) async {
    final title = await _promptTitle(parentId == null ? '新增模板任务' : '新增子任务', '');
    if (title == null || title.trim().isEmpty) return;
    await state.templates.insert(
      shiftTypeId: _selectedShiftId!,
      title: title.trim(),
      parentId: parentId,
    );
    setState(() {});
  }

  Future<void> _editTemplate(TaskTemplate tpl) async {
    final title = await _promptTitle('编辑任务', tpl.title);
    if (title == null || title.trim().isEmpty) return;
    final remind = await _pickRemind(tpl);
    await state.templates.update(TaskTemplate(
      id: tpl.id,
      shiftTypeId: tpl.shiftTypeId,
      parentId: tpl.parentId,
      title: title.trim(),
      remindTime: remind,
      sortOrder: tpl.sortOrder,
    ));
    setState(() {});
  }

  Future<String?> _pickRemind(TaskTemplate tpl) async {
    if (!mounted) return tpl.remindTime;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('设置提醒时间标签'),
              subtitle: Text(tpl.remindTime == null ? '当前未设置' : '当前 ${tpl.remindTime}'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: const TimeOfDay(hour: 10, minute: 0),
                );
                if (picked != null) {
                  final text = '${picked.hour.toString().padLeft(2, '0')}:'
                      '${picked.minute.toString().padLeft(2, '0')}';
                  if (ctx.mounted) Navigator.of(ctx).pop(text);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('清除提醒时间'),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text('保持原设置'),
              onTap: () => Navigator.of(ctx).pop(tpl.remindTime),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return tpl.remindTime;
    if (choice.isEmpty) return null;
    return choice;
  }

  Future<String?> _promptTitle(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: appInputDecoration(hintText: '任务标题'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyTo() async {
    final shifts = state.shifts.activeShiftTypes
        .where((s) => s.id != _selectedShiftId)
        .toList();
    if (shifts.isEmpty) return;
    final target = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('把当前模板复制到：', style: TextStyle(fontSize: 14)),
            ),
            for (final shift in shifts)
              ListTile(
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor: AppColors.fromHex(shift.colorHex),
                ),
                title: Text(shift.name),
                onTap: () => Navigator.of(ctx).pop(shift.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (target == null) return;
    final count = await state.templates.copyToShift(_selectedShiftId!, target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 $count 条顶层任务')),
    );
    setState(() {});
  }
}

// ========================================================== 数据管理

class DataSettingsPage extends StatefulWidget {
  const DataSettingsPage({super.key, required this.state, this.onDataChanged});

  final AppState state;

  /// 导入 / 恢复出厂后回调外壳，让任务列表整体重建（可选）。
  final VoidCallback? onDataChanged;

  @override
  State<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends State<DataSettingsPage> {
  AppState get state => widget.state;
  String? _dbPath;
  bool _busy = false;
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      _dbPath = await Db.path();
      final db = Db.instance;
      final counts = <String, int>{};
      for (final table in AppDatabase.allTables) {
        final value = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
        counts[table] = (value.first['c'] as num).toInt();
      }
      if (!mounted) return;
      setState(() {
        _counts
          ..clear()
          ..addAll(counts);
      });
    } catch (_) {
      // 数据库未就绪时静默忽略。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据导入 / 导出')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          _card(
            title: '导出备份',
            description: '把全部数据写成单个 JSON 文件，包含班次、排班规则、模板与所有任务。',
            actions: [
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.save_alt),
                label: const Text('导出到文件'),
              ),
            ],
          ),
          _card(
            title: '导入备份',
            description: '选择一个 DDtodo 导出的 JSON 文件。导入前会**清空本地数据库**，'
                '再按文件内容完整重建。',
            actions: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('选择文件导入'),
              ),
            ],
          ),
          _card(
            title: '数据库统计',
            description: _dbPath == null ? '读取中…' : '数据库文件：$_dbPath',
            actions: const [],
            child: Column(
              children: [
                for (final entry in _counts.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(_tableLabel(entry.key),
                            style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        Text('${entry.value} 行',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _card(
            title: '危险操作',
            description: '恢复出厂设置会删除全部数据，并重新写入预置班次与模板。'
                '此操作不可撤销，建议先导出备份。',
            actions: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _reset,
                icon: const Icon(Icons.restart_alt, color: AppColors.danger),
                label: const Text('恢复出厂设置',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required String description,
    required List<Widget> actions,
    Widget? child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
          if (child != null) ...[const SizedBox(height: 10), child],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: actions),
          ],
        ],
      ),
    );
  }

  String _tableLabel(String table) {
    const map = {
      AppDatabase.tShiftType: '班次类型',
      AppDatabase.tCycle: '排班周期',
      AppDatabase.tException: '单天覆盖',
      AppDatabase.tTemplate: '任务模板',
      AppDatabase.tDaily: '每日任务',
      AppDatabase.tPatternTemplate: '周期模板',
    };
    return map[table] ?? table;
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final result = await BackupService.exportToFile();
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.ok ? '导出成功' : '导出失败'),
        content: Text(
          result.ok
              ? '备份文件已写入：\n\n${result.path}\n\n'
                  '可以用数据线或「文件」应用把它复制到电脑上保存。'
              : result.message,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入会清空现有数据'),
        content: const Text(
          '导入前会删除本地数据库中的全部内容，再按备份文件重建。\n\n'
          '确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await BackupService.importFromFile(path);
    if (result.ok) {
      await state.shifts.load();
      await state.templates.load();
      await state.refreshAll();
      await _loadStats();
      widget.onDataChanged?.call();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复出厂设置？'),
        content: const Text('全部班次、排班规则、模板与任务都会被删除，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除全部数据'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    await BackupService.resetToFactory();
    await state.shifts.load();
    await state.templates.load();
    await state.refreshAll();
    await _loadStats();
    widget.onDataChanged?.call();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复出厂设置')));
  }
}

// ======================================================== 系统日历同步

class CalendarSyncPage extends StatefulWidget {
  const CalendarSyncPage({super.key, required this.state});

  final AppState state;

  @override
  State<CalendarSyncPage> createState() => _CalendarSyncPageState();
}

class _CalendarSyncPageState extends State<CalendarSyncPage> {
  AppState get state => widget.state;
  late final CalendarService _service = CalendarService(state.tasks);
  bool _busy = false;
  bool? _granted;
  List<Calendar> _calendars = [];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    // 本版本移除了 device_calendar 依赖，不需要探测权限。
    if (!CalendarService.enabled) return;
    final granted = await _service.ensurePermission();
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted) {
      final list = await _service.calendars();
      if (!mounted) return;
      setState(() => _calendars = list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('系统日历同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          if (!CalendarService.enabled)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.primary, 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.tint(AppColors.primary, 0.45)),
              ),
              child: const Text(
                '本版本未启用系统日历同步\n\n'
                '为了保证第一次就能打包成功，这个模块暂时移除了（它依赖的第三方日历插件'
                '与较新的 Flutter 版本存在不兼容风险）。\n\n'
                '受影响的只有「从系统日历导入日程」这一项。排班周期、任务清单、'
                '子任务、农历、重复任务、JSON 备份、统计等功能全部正常。\n\n'
                '你以前用旧版本导入过的日历事项如果还留在数据里，可以用下面的'
                '「清除已导入的日历事项」按钮清掉。',
                style: TextStyle(fontSize: 12, height: 1.7, color: AppColors.textSecondary),
              ),
            )
          else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.primary, 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '单向导入：只把系统日历里的日程读进 DDtodo，绝不会修改或写回系统日历。\n\n'
              '· 读取过去与未来的所有日程；\n'
              '· 导入的条目显示为灰色小字 + 日历图标，与 App 自带任务区分；\n'
              '· 可以勾选完成，但只改变 App 内的状态；\n'
              '· 重复同步不会产生重复条目。',
              style: TextStyle(fontSize: 12, height: 1.7, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          if (_granted == false)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('尚未获得日历权限',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text(
                    '请在系统的应用权限里允许 DDtodo 读取日历，然后回到这里重试。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _probe,
                    child: const Text('重新申请权限'),
                  ),
                ],
              ),
            ),
          if (_calendars.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('检测到 ${_calendars.length} 个日历',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final cal in _calendars)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor: cal.displayColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(cal.displayName,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (!CalendarService.enabled || _busy) ? null : _sync,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    CalendarService.enabled
                        ? (_busy ? '同步中…' : '立即同步（单向导入）')
                        : '系统日历同步（本版本未启用）',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('清除已导入的日历事项'),
          ),
        ],
      ),
    );
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final result = await _service.sync();
    await state.refreshAll();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    await _service.clearImported();
    await state.refreshAll();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清除导入的日历事项')));
  }
}

// ================================================================ 关于

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于 DDtodo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.event_available, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 12),
                const Text('DDtodo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const Text('排班日程 + Todo 清单',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                const Text('版本 1.0.0',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Card(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '功能一览\n\n'
                '· 固定周期排班：设定「几天一轮 + 每天什么班」，日历无限循环填充\n'
                '· 单天覆盖：长按日历上的某天，直接改这一天的班次\n'
                '· 修整轮：从某天起换成新的周期，不追溯历史\n'
                '· 跨天班次：晚班 20:00 → 次日 08:00，任务归属结束日\n'
                '· 班次任务模板：到点自动生成清单，子任务全勾选则父任务自动完成\n'
                '· 独立事项：随时新增，可一键转成模板任务\n'
                '· 系统日历单向导入：本版本暂未启用（见「系统日历同步」页说明）\n'
                '· JSON 全量导出 / 导入，纯本地无需联网\n\n'
                '所有数据都保存在手机本地的 SQLite 数据库里，不会上传到任何服务器。',
                style: TextStyle(fontSize: 12.5, height: 1.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
