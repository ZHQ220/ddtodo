import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../core/date_utils.dart';
import '../models/models.dart';
import 'app_database.dart';
import 'db.dart';
import 'shift_repository.dart';
import 'template_repository.dart';

/// 每日任务的读写、按需实例化、完成状态联动。
class TaskRepository extends ChangeNotifier {
  TaskRepository(this._shifts, this._templates);

  final ShiftRepository _shifts;
  final TemplateRepository _templates;

  /// 已经实例化过的「日期|班次键」，避免同一次会话重复跑生成逻辑。
  final Set<String> _ensured = {};

  // -------------------------------------------------- 排班归属计算

  /// 计算某天的班次实例（考虑跨天归属与单天覆盖）。
  ///
  /// 返回两个实例：
  ///  * [ShiftInstance]：班次开始日就是这一天；
  ///  * [ShiftInstance.crossOver]：前一天的跨天班次延续到今天（若有）。
  /// 任务的 `date` 归属结束日，所以跨天班次的任务在前者里带上 `dateOffset`。
  List<ScheduleInstance> scheduleFor(DateTime day) {
    final result = <ScheduleInstance>[];

    // 1) 延续到今天的跨天班次（开始于昨天）。
    final prevShift = shiftOfDay(DayUtil.addDays(day, -1));
    if (prevShift != null && prevShift.crossDay) {
      result.add(ScheduleInstance(
        shiftDate: DayUtil.addDays(day, -1),
        shiftTypeId: prevShift.id!,
        crossDay: true,
        dateOffset: 1,
      ));
    }

    // 2) 今天开始的班次。
    final today = shiftOfDay(day);
    if (today != null) {
      result.add(ScheduleInstance(
        shiftDate: day,
        shiftTypeId: today.id!,
        crossDay: today.crossDay,
        dateOffset: today.crossDay ? 1 : 0,
      ));
    }
    return result;
  }

  /// 某天「开始上班」的班次（不做跨天延续判断）；无排班返回 null。
  ShiftType? shiftOfDay(DateTime day) {
    final d = DayUtil.dateOnly(day);
    final override = _shifts.exceptionOf(d);
    if (override != null) return _shifts.byId(override);

    final cycle = _shifts.activeCycleFor(d);
    if (cycle == null || cycle.pattern.isEmpty) return null;

    final diff = DayUtil.daysBetween(DayUtil.parseIso(cycle.startDate), d);
    if (diff < 0) return null;
    final index = diff % cycle.pattern.length;
    return _shifts.byId(cycle.pattern[index]);
  }

  /// 某天生效的「结束班次」—— 跨天班次归属结束日，日历格与详情页都用这个。
  ///
  /// 规则：晚班（20:00 → 次日 08:00）的任务全部算在**次日**。
  /// 因此某天的主题班次是：昨天开始的跨天班次优先，否则当天开始的班次。
  ShiftType? effectiveShiftOfDay(DateTime day) {
    final prev = shiftOfDay(DayUtil.addDays(day, -1));
    if (prev != null && prev.crossDay) return prev;
    return shiftOfDay(day);
  }

  // -------------------------------------------------- 按需实例化

  /// 打开某天时调用：把当天的模板任务补齐，然后返回当天全部任务。
  Future<List<DailyTask>> ensureAndLoad(DateTime day) async {
    await ensureDay(day);
    return tasksForDay(day);
  }

  /// 批量确保一段日期已实例化（月视图加载时用）。
  Future<void> ensureRange(DateTime from, DateTime to) async {
    var cursor = DayUtil.dateOnly(from);
    final end = DayUtil.dateOnly(to);
    while (!cursor.isAfter(end)) {
      await ensureDay(cursor);
      cursor = DayUtil.addDays(cursor, 1);
    }
  }

  /// 确保某天的任务实例存在。幂等：已有记录不会被重复创建。
  Future<void> ensureDay(DateTime day) async {
    final d = DayUtil.dateOnly(day);
    final db = Db.instance;

    for (final inst in scheduleFor(d)) {
      final key = '${DayUtil.iso(d)}|${inst.shiftTypeId}';
      if (_ensured.contains(key)) continue;

      final templates = _templates.forShift(inst.shiftTypeId);
      if (templates.isEmpty) {
        _ensured.add(key);
        continue;
      }

      final taskDate = DayUtil.iso(DayUtil.addDays(d, inst.dateOffset));
      // 以 shift_date 为准判重：同一「班次实例」无论归属到哪一天，只实例化一次。
      final existing = await db.query(
        AppDatabase.tDaily,
        columns: ['template_id'],
        where: 'template_id IS NOT NULL AND shift_date = ?',
        whereArgs: [DayUtil.iso(d)],
      );
      final existingTemplateIds = <int>{};
      for (final row in existing) {
        final tid = (row['template_id'] as num?)?.toInt();
        if (tid != null) existingTemplateIds.add(tid);
      }

      // 用逐条 insert（而不是 batch）是为了拿到父任务自增后的真实 id ——
      // batch 里的 insert 只返回占位 id（负数），无法作为子任务的 parent_id。
      var order = 0;
      final idByTemplate = <int, int>{};

      // 先父后子：模板在数据库里也是先插父的，这里再排一次保证顺序。
      final templateIds = templates.map((t) => t.id!).toSet();
      int orderOf(TaskTemplate t) => t.sortOrder;
      final roots = templates
          .where((t) => !templateIds.contains(t.parentId))
          .toList()
        ..sort((a, b) => orderOf(a).compareTo(orderOf(b)));
      final children = templates
          .where((t) => templateIds.contains(t.parentId))
          .toList()
        ..sort((a, b) => orderOf(a).compareTo(orderOf(b)));

      for (final tpl in roots) {
        if (existingTemplateIds.contains(tpl.id!)) continue;
        final id = await db.insert(AppDatabase.tDaily, {
          'date': taskDate,
          'shift_type_id': inst.shiftTypeId,
          'shift_date': DayUtil.iso(d),
          'title': tpl.title,
          'is_completed': 0,
          'is_custom': 0,
          'source_type': TaskSource.app.name,
          'remind_time': tpl.remindTime,
          'parent_id': null,
          'template_id': tpl.id,
          'sort_order': order++,
          'deleted': 0,
        });
        idByTemplate[tpl.id!] = id;
      }

      for (final tpl in children) {
        if (existingTemplateIds.contains(tpl.id!)) continue;
        final parentTemplateId = tpl.parentId;
        var parentDailyId = parentTemplateId == null ? null : idByTemplate[parentTemplateId];
        parentDailyId ??= await _findParentDailyId(db, taskDate, parentTemplateId);
        final id = await db.insert(AppDatabase.tDaily, {
          'date': taskDate,
          'shift_type_id': inst.shiftTypeId,
          'shift_date': DayUtil.iso(d),
          'title': tpl.title,
          'is_completed': 0,
          'is_custom': 0,
          'source_type': TaskSource.app.name,
          'remind_time': tpl.remindTime,
          'parent_id': parentDailyId,
          'template_id': tpl.id,
          'sort_order': order++,
          'deleted': 0,
        });
        idByTemplate[tpl.id!] = id;
      }

      _ensured.add(key);
    }
  }

  Future<int?> _findParentDailyId(Database db, String date, int? parentTemplateId) async {
    if (parentTemplateId == null) return null;
    final rows = await db.query(
      AppDatabase.tDaily,
      columns: ['id'],
      where: 'date = ? AND template_id = ?',
      whereArgs: [date, parentTemplateId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  // ------------------------------------------------------------ 查询

  /// 某天的全部任务（跨天班次的任务按结束日归类）。
  Future<List<DailyTask>> tasksForDay(DateTime day) async {
    final db = Db.instance;
    final iso = DayUtil.iso(day);
    final rows = await db.query(
      AppDatabase.tDaily,
      where: '(date = ? OR (shift_date = ? AND date <> ?)) AND deleted = 0',
      whereArgs: [iso, iso, iso],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(DailyTask.fromMap).toList();
  }

  /// 某天已合入的导入来源（用于去重，避免重复导入升级成副本）。
  Future<Set<String>> importedKeys() async {
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      columns: ['external_id'],
      where: 'source_type = ? AND external_id IS NOT NULL',
      whereArgs: [TaskSource.calendar.name],
    );
    return {
      for (final r in rows) (r['external_id'] as String?) ?? '',
    }..remove('');
  }

  /// 月视图用：统计每个日期的未完成任务数。
  Future<Map<String, int>> countsByDate(DateTime from, DateTime to) async {
    final rows = await Db.instance.rawQuery(
      '''
      SELECT COALESCE(date, shift_date) AS d, COUNT(*) AS c
      FROM ${AppDatabase.tDaily}
      WHERE deleted = 0 AND is_completed = 0 AND parent_id IS NULL
        AND COALESCE(date, shift_date) >= ? AND COALESCE(date, shift_date) <= ?
      GROUP BY d
      ''',
      [DayUtil.iso(from), DayUtil.iso(to)],
    );
    return {
      for (final r in rows) (r['d'] as String): (r['c'] as num).toInt(),
    };
  }

  /// 全局列表用：按日期区间查询。
  Future<List<DailyTask>> tasksInRange(DateTime from, DateTime to) async {
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      where: 'COALESCE(date, shift_date) >= ? AND COALESCE(date, shift_date) <= ? AND deleted = 0',
      whereArgs: [DayUtil.iso(from), DayUtil.iso(to)],
      orderBy: 'COALESCE(date, shift_date) ASC, sort_order ASC, id ASC',
    );
    return rows.map(DailyTask.fromMap).toList();
  }

  /// 搜索（任务列表页）。
  Future<List<DailyTask>> search(String keyword, {int limit = 200}) async {
    final kw = '%${keyword.trim()}%';
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      where: 'title LIKE ? AND deleted = 0',
      whereArgs: [kw],
      orderBy: 'COALESCE(date, shift_date) DESC, id DESC',
      limit: limit,
    );
    return rows.map(DailyTask.fromMap).toList();
  }

  /// 全部任务（导出备份用）。
  Future<List<DailyTask>> all() async {
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      orderBy: 'COALESCE(date, shift_date) ASC, id ASC',
    );
    return rows.map(DailyTask.fromMap).toList();
  }

  // ---------------------------------------------------------- 写入

  /// 新增独立事项（不绑定模板）。
  Future<int> addCustomTask({
    required DateTime date,
    required String title,
    int? shiftTypeId,
    String? remindTime,
    TaskSource source = TaskSource.app,
    String? externalId,
    String? description,
  }) async {
    final iso = DayUtil.iso(date);
    final display = description == null || description.isEmpty ? title : '$title\n$description';
    final id = await Db.instance.insert(AppDatabase.tDaily, {
      'date': iso,
      'shift_type_id': shiftTypeId,
      'shift_date': iso,
      'title': display,
      'is_completed': 0,
      'is_custom': 1,
      'source_type': source.name,
      'remind_time': remindTime,
      'parent_id': null,
      'template_id': null,
      'sort_order': 9000,
      'deleted': 0,
      'external_id': externalId,
    });
    notifyListeners();
    return id;
  }

  /// 新增子任务（挂在已有任务下）。
  Future<int> addChildTask({
    required DailyTask parent,
    required String title,
  }) async {
    final date = parent.date ?? parent.shiftDate;
    final shiftDate = parent.shiftDate;
    final id = await Db.instance.insert(AppDatabase.tDaily, {
      'date': date,
      'shift_type_id': parent.shiftTypeId,
      'shift_date': shiftDate,
      'title': title,
      'is_completed': 0,
      'is_custom': 1,
      'source_type': TaskSource.app.name,
      'remind_time': null,
      'parent_id': parent.id,
      'template_id': null,
      'sort_order': 100,
      'deleted': 0,
    });
    notifyListeners();
    return id;
  }

  Future<void> updateTask(DailyTask task) async {
    await Db.instance.update(
      AppDatabase.tDaily,
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
    notifyListeners();
  }

  Future<void> renameTask(int id, String title) async {
    await Db.instance.update(
      AppDatabase.tDaily,
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Future<void> setRemind(int id, String? time) async {
    await Db.instance.update(
      AppDatabase.tDaily,
      {'remind_time': time},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  /// 勾选 / 取消勾选。
  ///
  /// 联动规则：勾选末尾子任务会让所有未勾选的父级自动完成；取消子任务会清掉父级完成态。
  Future<void> toggle(DailyTask task) async {
    final db = Db.instance;
    final next = !task.isCompleted;

    await db.update(
      AppDatabase.tDaily,
      {'is_completed': next ? 1 : 0},
      where: 'id = ?',
      whereArgs: [task.id],
    );

    if (task.parentId != null) {
      final parent = await _byId(task.parentId!);
      if (parent != null) {
        if (!next) {
          await db.update(
            AppDatabase.tDaily,
            {'is_completed': 0},
            where: 'id = ?',
            whereArgs: [parent.id],
          );
        } else {
          // 注意：要先落库再查兄弟节点，否则拿到的是勾选前的状态。
          final siblings = await _childrenOf(parent.id);
          final allDone = siblings.isNotEmpty && siblings.every((c) => c.isCompleted);
          if (allDone && !parent.isCompleted) {
            await db.update(
              AppDatabase.tDaily,
              {'is_completed': 1},
              where: 'id = ?',
              whereArgs: [parent.id],
            );
          }
        }
      }
    }
    notifyListeners();
  }

  Future<DailyTask?> _byId(int id) async {
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyTask.fromMap(rows.first);
  }

  Future<List<DailyTask>> _childrenOf(int parentId) async {
    final rows = await Db.instance.query(
      AppDatabase.tDaily,
      where: 'parent_id = ? AND deleted = 0',
      whereArgs: [parentId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(DailyTask.fromMap).toList();
  }

  /// 删除任务（连同子任务）。
  ///
  /// * 模板实例：写 `deleted = 1` 墓碑，模板不受影响，**但同一天不会再次自动生成**
  ///   （`ensureDay` 的判重只看 `shift_date`，墓碑行仍然占位），次日照常生成；
  /// * 独立事项 / 导入项：直接物理删除，它们没有「自动长回来」的问题。
  Future<void> deleteTask(DailyTask task) async {
    final db = Db.instance;
    final id = task.id;
    if (id == null) return;

    final children = await _childrenOf(id);
    final isTemplateInstance = task.templateId != null || children.any((c) => c.templateId != null);

    if (isTemplateInstance) {
      await db.update(
        AppDatabase.tDaily,
        {'deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.update(
        AppDatabase.tDaily,
        {'deleted': 1},
        where: 'parent_id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete(AppDatabase.tDaily, where: 'parent_id = ?', whereArgs: [id]);
      await db.delete(AppDatabase.tDaily, where: 'id = ?', whereArgs: [id]);
    }
    notifyListeners();
  }

  /// 清空某天的全部「非导入」任务。
  Future<void> clearDay(DateTime day) async {
    await Db.instance.delete(
      AppDatabase.tDaily,
      where: 'date = ? AND source_type <> ? AND deleted = 0',
      whereArgs: [DayUtil.iso(day), TaskSource.calendar.name],
    );
    _ensured.clear();
    notifyListeners();
  }

  /// 让某天重新生成模板任务（清掉墓碑后重新实例化）。
  Future<List<DailyTask>> regenerateDay(DateTime day) async {
    await Db.instance.delete(
      AppDatabase.tDaily,
      where: 'date = ? AND source_type = ?',
      whereArgs: [DayUtil.iso(day), TaskSource.app.name],
    );
    _ensured.clear();
    return ensureAndLoad(day);
  }

  /// 导入期间清空日历来源的任务（重新导入时调用）。
  Future<void> clearImported() async {
    await Db.instance.delete(
      AppDatabase.tDaily,
      where: 'source_type = ?',
      whereArgs: [TaskSource.calendar.name],
    );
    notifyListeners();
  }

  /// 清空所有任务。
  Future<void> clearAll() async {
    await Db.instance.delete(AppDatabase.tDaily);
    _ensured.clear();
    notifyListeners();
  }

  /// 把当前任务分组：父任务 + 其子任务。
  static Map<DailyTask, List<DailyTask>> group(List<DailyTask> tasks) {
    final roots = tasks.where((t) => t.parentId == null).toList();
    final result = <DailyTask, List<DailyTask>>{};
    for (final r in roots) {
      result[r] = tasks.where((t) => t.parentId == r.id).toList();
    }
    return result;
  }
}
