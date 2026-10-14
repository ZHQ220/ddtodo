import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/date_utils.dart';
import '../../data/app_database.dart';
import '../../data/db.dart';
import '../../models/models.dart';
import '../../services/backup_service.dart';
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
        onTap: () async {
          await Navigator.of(context).pushNamed(route);
          // 回到设置页时通知外壳刷新任务列表 / 日历。
          if (mounted) widget.onDataChanged?.call();
        },
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
            '预置班次可以改颜色、改时间、改名；下班时间早于上班时间的（如晚班）任务会自动归属到结束日。',
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
        : '${type.startTime ?? '--:--'} - ${type.endTime ?? '--:--'}';
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
            '默认按生效日期取「最近一条」规则无限循环；也可以在某一条上点「···」→「设为生效」手动指定。'
            '切换只影响今天及以后，不会追溯调整过去的排班。',
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
                if (value == 'activate') {
                  // 手动指定：从今天起改用这一条周期，并把今天及以后的任务重新对账。
                  await state.activateCycle(cycle);
                  if (!mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已切换到「${cycle.name}」（从今天开始生效）')),
                  );
                } else if (value == 'edit') {
                  await _editCycle(existing: cycle);
                } else if (value == 'delete') {
                  await state.shifts.deleteCycle(cycle.id!);
                  // 删掉生效中的那一条会切回上一条，任务清单也要跟着重算。
                  await state.syncTemplateChanges();
                  if (!mounted) return;
                  setState(() {});
                }
              },
              itemBuilder: (context) => [
                if (!isActive)
                  const PopupMenuItem(value: 'activate', child: Text('设为生效')),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
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
    // 排班变了：把今天及以后的清单重新对账（换过班次的那天会清掉旧班次的任务）。
    await state.syncTemplateChanges();
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
  late ShiftKind _kind;
  TimeOfDay? _start;
  TimeOfDay? _end;

  /// 下班时间不晚于上班时间 → 这个班次是「夜班」，前一天晚上开始上班
  /// （与 ShiftType.startsPreviousDay 同一规则）。
  bool get _startsPreviousDay {
    final s = _start, e = _end;
    if (s == null || e == null) return false;
    return e.hour * 60 + e.minute <= s.hour * 60 + s.minute;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _color = e?.colorHex ?? widget.state.shifts.nextPaletteColor();
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
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
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
            if (_startsPreviousDay)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '下班时间不晚于上班时间，按「夜班」处理：'
                  '${_format(_start) ?? '--:--'} 上班、次日 ${_format(_end) ?? '--:--'} 下班。'
                  '夜班显示在结束的那一天，任务也生成在那一天'
                  '（例如 14 号的夜班 = 13 号 22:00 → 14 号 07:30）。',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
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
  late final TextEditingController _daysController;
  late DateTime _startDate;
  late List<int> _pattern;

  /// 周期天数上限，避免误输入一个大数字把界面撑爆。
  static const int _maxDays = 60;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    // 新建时先给 7 个「空」格子：想排几天就填几天，其余留空即可。
    _pattern = e == null ? List<int>.filled(7, 0) : [...e.pattern];
    if (_pattern.isEmpty) _pattern = List<int>.filled(1, 0);
    _daysController = TextEditingController(text: '${_pattern.length}');
    _startDate = DayUtil.tryParseIso(e?.startDate) ?? DayUtil.today();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  /// 解析「周期天数」输入：兼容全角数字（６）与多余空格；解析不出来返回 null。
  int? _parseDays(String raw) {
    final normalized = raw
        .replaceAllMapped(RegExp(r'[０-９]'),
            (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0))
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) return null;
    return int.tryParse(normalized);
  }

  /// 把周期长度改成 [days] 天：不够的补「空」，多出来的从末尾删掉。
  ///
  /// 统一入口：输入框、+ / − 按钮、追加按钮都走这里，
  /// 每次都换成**新的列表实例**并同步输入框，保证界面一定跟着刷新。
  void _applyDays(int days) {
    final target = days.clamp(1, _maxDays).toInt();
    if (target == _pattern.length) {
      _syncDaysText();
      return;
    }
    setState(() {
      if (target > _pattern.length) {
        _pattern = [
          ..._pattern,
          ...List<int>.filled(target - _pattern.length, 0),
        ];
      } else {
        _pattern = _pattern.sublist(0, target);
      }
      _syncDaysText();
    });
  }

  /// 往周期末尾追加一天（[value] 为班次 id，0 表示留空）。
  void _appendDay(int value) {
    // 先收起键盘：否则键盘可能盖住下面的格子/按钮，点哪都没反应。
    FocusScope.of(context).unfocus();
    if (_pattern.length >= _maxDays) return;
    setState(() {
      _pattern = [..._pattern, value];
      _syncDaysText();
    });
  }

  /// 所有天都留空。
  void _clearAllDays() {
    FocusScope.of(context).unfocus();
    setState(() {
      _pattern = List<int>.filled(_pattern.length, 0);
    });
  }

  /// 把输入框里的数字同步成当前天数。
  void _syncDaysText() {
    final text = '${_pattern.length}';
    // 直接赋 .text：光标会自动落到末尾，且不依赖 TextSelection / TextEditingValue。
    if (_daysController.text != text) _daysController.text = text;
  }

  /// 设置第 [index] 天：班次 id，0 表示「空」（那天没有班次、不生成任务）。
  void _setDay(int index, int value) {
    if (index < 0 || index >= _pattern.length) return;
    setState(() {
      final next = [..._pattern];
      next[index] = value;
      _pattern = next;
    });
  }

  /// 删除第 [index] 天（后面的往前补一位）。
  void _removeDay(int index) {
    if (_pattern.length <= 1) return;
    setState(() {
      _pattern = [..._pattern]..removeAt(index);
      _syncDaysText();
    });
  }

  /// 点某一格：选择这天排什么班，或留空。
  Future<void> _editDay(int index) async {
    FocusScope.of(context).unfocus();
    final types = widget.state.shifts.shiftTypes.where((s) => !s.archived).toList();
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('第 ${index + 1} 天',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('选择这天排什么班，或留空',
                    style: TextStyle(fontSize: 12)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                    radius: 8, backgroundColor: Color(0xFFE3E7EA)),
                title: const Text('留空（不排班）'),
                onTap: () => Navigator.of(ctx).pop(0),
              ),
              for (final type in types)
                ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: AppColors.fromHex(type.colorHex),
                  ),
                  title: Text(type.name),
                  onTap: () => Navigator.of(ctx).pop(type.id!),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删掉这一天'),
                enabled: _pattern.length > 1,
                onTap: () => Navigator.of(ctx).pop(-1),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == -1) {
      _removeDay(index);
    } else {
      _setDay(index, picked);
    }
  }

  /// 周期里的一格：第几天 + 班次名（留空时显示「空」）。
  Widget _dayChip(int index) {
    final value = _pattern[index];
    final type = value == 0 ? null : widget.state.shifts.byId(value);
    final color =
        type == null ? const Color(0xFFB6C0C6) : AppColors.fromHex(type.colorHex);
    return InkWell(
      onTap: () => _editDay(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: type == null ? const Color(0xFFF2F4F6) : AppColors.tint(color, 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: type == null ? const Color(0xFFD7DDE1) : AppColors.tint(color, 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('${index + 1}.${type?.name ?? '空'}',
                style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  /// 「往周期末尾追加一天」的按钮（比 ActionChip 的点击区域大，不容易点不中）。
  Widget _appendButton(String label, int value, Color color) {
    return OutlinedButton(
      onPressed: () => _appendDay(value),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
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
                '留空的天不会有班次、也不会生成任务（月历上是空白）。\n'
                '此规则只影响生效日期及以后，不会追溯调整历史排班。',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.6),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('周期天数', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _daysController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: appInputDecoration(hintText: '7'),
                    // 输入即生效：不用按回车，下面的格子数量立刻跟着变。
                    onChanged: (v) {
                      final n = _parseDays(v);
                      if (n != null) _applyDays(n);
                    },
                    onEditingComplete: () {
                      _applyDays(
                          _parseDays(_daysController.text) ?? _pattern.length);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text('当前共 ${_pattern.length} 天',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                const Spacer(),
                TextButton(
                  onPressed: _clearAllDays,
                  child: const Text('全部留空'),
                ),
              ],
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _applyDays(_pattern.length - 1);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('− 减一天', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _applyDays(_pattern.length + 1);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('＋ 加一天', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '点某一格可以改这天排什么班；留空表示那天没有班次、也不生成任务。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _pattern.length; i++) _dayChip(i),
              ],
            ),
            const SizedBox(height: 10),
            const Text('点下面按钮往周期末尾追加一天：', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _appendButton('空', 0, const Color(0xFFB6C0C6)),
                for (final type in types)
                  _appendButton(type.name, type.id!,
                      AppColors.fromHex(type.colorHex)),
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
            if (_pattern.every((v) => v == 0)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请至少给一天选上班次')),
              );
              return;
            }
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
                          '· 最多三层：任务 → 子任务 → 孙任务，点「添加子任务 / 加下级」往下加；\n'
                          '· 下一层全部勾选 → 上一层自动完成；\n'
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
              _subtitleOf(children),
              style: const TextStyle(fontSize: 11.5),
            ),
            trailing: _templateMenu(root),
            onTap: () => _editTemplate(root),
          ),
          for (final entry in _descendantsOf(root)) _childRow(entry.key, entry.value),
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

  /// 子任务数量文案（含更下一层）。
  String _subtitleOf(List<TaskTemplate> children) {
    if (children.isEmpty) return '还没有子任务';
    final grand = children
        .map((c) => state.templates.childrenOf(c.id).length)
        .fold<int>(0, (a, b) => a + b);
    return grand == 0
        ? '${children.length} 个子任务'
        : '${children.length} 个子任务 + $grand 个孙任务';
  }

  /// 某个任务的全部下级（层级从 1 开始），最多三层：任务 → 子任务 → 孙任务。
  List<MapEntry<TaskTemplate, int>> _descendantsOf(TaskTemplate root,
      [int depth = 1]) {
    final result = <MapEntry<TaskTemplate, int>>[];
    if (depth > 2) return result;
    for (final child in state.templates.childrenOf(root.id)) {
      result.add(MapEntry(child, depth));
      result.addAll(_descendantsOf(child, depth + 1));
    }
    return result;
  }

  /// 一行下级任务（缩进随层级增加）。孙任务（第 3 层）不能再加下级。
  Widget _childRow(TaskTemplate tpl, int depth) {
    return Padding(
      padding: EdgeInsets.fromLTRB(30.0 + depth * 16, 0, 6, 2),
      child: Row(
        children: [
          const Icon(Icons.subdirectory_arrow_right,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              tpl.title,
              style: TextStyle(
                fontSize: depth == 1 ? 13.5 : 12.5,
                color: depth == 1 ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          if (depth < 2)
            TextButton.icon(
              onPressed: () => _addTemplate(tpl.id),
              icon: const Icon(Icons.add, size: 15),
              label: const Text('加下级', style: TextStyle(fontSize: 12)),
            ),
          _templateMenu(tpl, compact: true),
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
            // 模板删掉后，今天及以后「未完成」的实例也跟着消失（已完成的保留）。
            await state.syncTemplateChanges();
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
    // 新加的模板任务立刻补到「今天及以后」的清单里。
    await state.syncTemplateChanges();
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
    // 改名 / 改提醒：今天及以后「未完成」的实例跟着更新（已完成保留）。
    await state.syncTemplateChanges();
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
    // 复制过去的模板也要立刻生效（今天及以后）。
    await state.syncTemplateChanges();
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
            description: '选择一个 DDtodo 导出的 JSON 文件。导入前会清空本地数据库，'
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
                '· 修整轮：排班规则卡片右上角「···」→「设为生效」，从今天起换成这条周期（不追溯历史）\n'
                '· 夜班：下班时间不晚于上班时间的算夜班（如 22:00 → 次日 07:30），日历与任务都算在结束那一天\n'
                '· 班次任务模板：到点自动生成清单，子任务全勾选则父任务自动完成\n'
                '· 换班次 / 换周期后，旧班次没做完的任务会自动清掉，换成当前班次的清单\n'
                '· 清空当天任务：当日详情右上角「···」→ 一键清空，当天不再自动补回来\n'
                '· 独立事项：随时新增，可一键转成模板任务\n'
                '· 法定节假日：日历格右上角标「休」；调休上班的周末标「班」\n'
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
