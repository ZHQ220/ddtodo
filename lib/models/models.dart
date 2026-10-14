/// 数据模型。字段命名与 `SPEC.md` 中的表结构一一对应。

/// 任务的来源，对应 daily_task.source_type。
///
/// 早期版本有过「从系统日历导入」，该功能已移除；历史数据里若残留
/// `calendar` 之类的旧值，一律当作 App 内创建处理（[fromName] 全量兜底）。
enum TaskSource {
  /// App 内创建（模板实例或独立事项）
  app;

  static TaskSource fromName(String? name) => TaskSource.app;

  String get dbName => name;
}

/// 预置班次的种类。`custom` 表示用户自建的班次。
enum ShiftKind {
  morning,
  middle,
  night,
  work,
  rest,
  custom;

  static ShiftKind fromName(String? name) {
    switch (name) {
      case 'morning':
        return ShiftKind.morning;
      case 'middle':
        return ShiftKind.middle;
      case 'night':
        return ShiftKind.night;
      case 'work':
        return ShiftKind.work;
      case 'rest':
        return ShiftKind.rest;
      default:
        return ShiftKind.custom;
    }
  }

  String get label {
    switch (this) {
      case ShiftKind.morning:
        return '早班';
      case ShiftKind.middle:
        return '中班';
      case ShiftKind.night:
        return '晚班';
      case ShiftKind.work:
        return '工作班';
      case ShiftKind.rest:
        return '休息';
      case ShiftKind.custom:
        return '自定义';
    }
  }
}

/// shift_type
class ShiftType {
  const ShiftType({
    this.id,
    required this.name,
    required this.colorHex,
    this.isPreset = false,
    this.kind = ShiftKind.custom,
    this.startTime,
    this.endTime,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int? id;
  final String name;
  final String colorHex;
  final bool isPreset;
  final ShiftKind kind;

  /// `HH:mm`，可为空。
  final String? startTime;
  final String? endTime;
  final int sortOrder;

  /// 归档后不再出现在选择列表里，但历史数据仍可正确显示。
  final bool archived;

  bool get isRest => kind == ShiftKind.rest;

  /// 是否跨天（例如 20:00 上班、次日 08:00 下班）。
  ///
  /// 不再由任何开关决定：**结束时间不晚于开始时间**就算跨天，
  /// 这种班次的任务照旧归属到结束日（次日）。
  bool get crossesMidnight {
    final s = _minutesOf(startTime);
    final e = _minutesOf(endTime);
    if (s == null || e == null) return false;
    return e <= s;
  }

  /// 把 `HH:mm` 解析成「当天第几分钟」；解析不了返回 null（含休息班无时间）。
  static int? _minutesOf(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  ShiftType copyWith({
    int? id,
    String? name,
    String? colorHex,
    bool? isPreset,
    ShiftKind? kind,
    String? startTime,
    String? endTime,
    int? sortOrder,
    bool? archived,
  }) {
    return ShiftType(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      isPreset: isPreset ?? this.isPreset,
      kind: kind ?? this.kind,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'color': colorHex,
        'is_preset': isPreset ? 1 : 0,
        'kind': kind.name,
        'start_time': startTime,
        'end_time': endTime,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
      };

  static ShiftType fromMap(Map<String, Object?> m) => ShiftType(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '未命名',
        colorHex: (m['color'] as String?) ?? '#3B82F6',
        isPreset: (m['is_preset'] as int? ?? 0) == 1,
        kind: ShiftKind.fromName(m['kind'] as String?),
        startTime: m['start_time'] as String?,
        endTime: m['end_time'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
        archived: (m['archived'] as int? ?? 0) == 1,
      );
}

/// shift_cycle —— 一条排班规则（按生效日期倒序寻找最新的一条）。
class ShiftCycle {
  const ShiftCycle({
    this.id,
    required this.name,
    required this.startDate,
    required this.pattern,
  });

  final int? id;
  final String name;
  final String startDate;
  final List<int> pattern;

  int get cycleDays => pattern.length;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'start_date': startDate,
        'pattern': pattern.join(','),
      };

  static ShiftCycle fromMap(Map<String, Object?> m) => ShiftCycle(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '排班规则',
        startDate: (m['start_date'] as String?) ?? '1970-01-01',
        pattern: ((m['pattern'] as String?) ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map(int.parse)
            .toList(),
      );
}

/// task_template —— 班次任务模板（树形，parent_id 自引用）。
class TaskTemplate {
  const TaskTemplate({
    this.id,
    required this.shiftTypeId,
    this.parentId,
    required this.title,
    this.remindTime,
    this.sortOrder = 0,
  });

  final int? id;
  final int shiftTypeId;
  final int? parentId;
  final String title;
  final String? remindTime;
  final int sortOrder;

  TaskTemplate copyWith({
    int? id,
    int? shiftTypeId,
    int? parentId,
    String? title,
    String? remindTime,
    int? sortOrder,
  }) =>
      TaskTemplate(
        id: id ?? this.id,
        shiftTypeId: shiftTypeId ?? this.shiftTypeId,
        parentId: parentId ?? this.parentId,
        title: title ?? this.title,
        remindTime: remindTime ?? this.remindTime,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'shift_type_id': shiftTypeId,
        'parent_id': parentId,
        'title': title,
        'remind_time': remindTime,
        'sort_order': sortOrder,
      };

  static TaskTemplate fromMap(Map<String, Object?> m) => TaskTemplate(
        id: m['id'] as int?,
        shiftTypeId: m['shift_type_id'] as int? ?? 0,
        parentId: m['parent_id'] as int?,
        title: (m['title'] as String?) ?? '',
        remindTime: m['remind_time'] as String?,
        sortOrder: m['sort_order'] as int? ?? 0,
      );
}

/// 排班生成实例（一个「班次实例」= 某天开始的一个班次）。
///
/// 跨天班次（如 20:00 → 次日 08:00）的任务归到结束日，因此：
///   shiftDate  = 班次开始的那天
///   dateOffset = 任务日期相对开始日的天数（跨天班次为 1）
///   showsOn    = 任务实际显示的日期 = shiftDate + dateOffset
class ScheduleInstance {
  const ScheduleInstance({
    required this.shiftDate,
    required this.shiftTypeId,
    this.dateOffset = 0,
  });

  /// 班次开始日（yyyy-MM-dd）。
  final String shiftDate;

  final int shiftTypeId;

  /// 任务实际显示的日期相对 [shiftDate] 的偏移天数。
  final int dateOffset;

  /// 任务实际显示的日期（yyyy-MM-dd）。
  ///
  /// 由 [shiftDate] 与 [dateOffset] 推导，避免内部字段互相矛盾。
  String get showsOn => _shift(shiftDate, dateOffset);

  static String _shift(String iso, int days) {
    final p = iso.split('-');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]) + days);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

/// daily_task
class DailyTask {
  const DailyTask({
    this.id,
    this.date,
    this.shiftTypeId,
    this.shiftDate,
    required this.title,
    this.isCompleted = false,
    this.isCustom = false,
    this.source = TaskSource.app,
    this.remindTime,
    this.parentId,
    this.templateId,
    this.sortOrder = 0,
    this.deleted = false,
  });

  final int? id;

  /// 显示日期（跨天班次为结束日）。
  final String? date;

  /// 生成该任务的班次类型；独立事项为空。
  final int? shiftTypeId;

  /// 生成该任务的班次开始日（跨天归属判定的关键）。
  final String? shiftDate;

  final String title;
  final bool isCompleted;
  final bool isCustom;
  final TaskSource source;
  final String? remindTime;
  final int? parentId;
  final int? templateId;
  final int sortOrder;

  /// 软删除墓碑：保证「单天删除」后重新打开页面不会再次自动生成。
  final bool deleted;

  DailyTask copyWith({
    int? id,
    String? date,
    int? shiftTypeId,
    String? shiftDate,
    String? title,
    bool? isCompleted,
    bool? isCustom,
    TaskSource? source,
    String? remindTime,
    int? parentId,
    int? templateId,
    int? sortOrder,
    bool? deleted,
  }) =>
      DailyTask(
        id: id ?? this.id,
        date: date ?? this.date,
        shiftTypeId: shiftTypeId ?? this.shiftTypeId,
        shiftDate: shiftDate ?? this.shiftDate,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
        isCustom: isCustom ?? this.isCustom,
        source: source ?? this.source,
        remindTime: remindTime ?? this.remindTime,
        parentId: parentId ?? this.parentId,
        templateId: templateId ?? this.templateId,
        sortOrder: sortOrder ?? this.sortOrder,
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'shift_type_id': shiftTypeId,
        'shift_date': shiftDate,
        'title': title,
        'is_completed': isCompleted ? 1 : 0,
        'is_custom': isCustom ? 1 : 0,
        'source_type': source.dbName,
        'remind_time': remindTime,
        'parent_id': parentId,
        'template_id': templateId,
        'sort_order': sortOrder,
        'deleted': deleted ? 1 : 0,
      };

  static DailyTask fromMap(Map<String, Object?> m) => DailyTask(
        id: m['id'] as int?,
        date: m['date'] as String?,
        shiftTypeId: m['shift_type_id'] as int?,
        shiftDate: m['shift_date'] as String?,
        title: (m['title'] as String?) ?? '',
        isCompleted: (m['is_completed'] as int? ?? 0) == 1,
        isCustom: (m['is_custom'] as int? ?? 0) == 1,
        source: TaskSource.fromName(m['source_type'] as String?),
        remindTime: m['remind_time'] as String?,
        parentId: m['parent_id'] as int?,
        templateId: m['template_id'] as int?,
        sortOrder: m['sort_order'] as int? ?? 0,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}
