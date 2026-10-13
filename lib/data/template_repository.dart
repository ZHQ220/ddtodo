import 'package:flutter/material.dart';

import '../models/models.dart';
import 'app_database.dart';
import 'db.dart';

/// 班次任务模板（树形：父任务 + 子任务）读写与缓存。
class TemplateRepository extends ChangeNotifier {
  List<TaskTemplate> _all = [];

  List<TaskTemplate> get all => _all;

  /// 某个班次的全部模板（父 + 子，已按 sort_order 排序）。
  List<TaskTemplate> forShift(int shiftTypeId) =>
      _all.where((t) => t.shiftTypeId == shiftTypeId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 顶层模板。
  List<TaskTemplate> rootsFor(int shiftTypeId) {
    final list = forShift(shiftTypeId);
    final ids = list.map((t) => t.id).toSet();
    return list.where((t) => !ids.contains(t.parentId)).toList();
  }

  /// 某个模板的子任务。
  List<TaskTemplate> childrenOf(int? parentId) =>
      _all.where((t) => t.parentId == parentId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  TaskTemplate? byId(int? id) {
    if (id == null) return null;
    for (final t in _all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 模板总数（汇总统计用）。
  int get total => _all.length;

  Future<void> load() async {
    final rows = await Db.instance.query(
      AppDatabase.tTemplate,
      orderBy: 'shift_type_id ASC, sort_order ASC, id ASC',
    );
    _all = rows.map(TaskTemplate.fromMap).toList();
    notifyListeners();
  }

  Future<int> insert({
    required int shiftTypeId,
    required String title,
    int? parentId,
    String? remindTime,
  }) async {
    final db = Db.instance;
    final maxOrder = await _maxOrder(shiftTypeId, parentId);
    final id = await db.insert(AppDatabase.tTemplate, {
      'shift_type_id': shiftTypeId,
      'parent_id': parentId,
      'title': title,
      'remind_time': remindTime,
      'sort_order': maxOrder + 1,
    });
    await load();
    return id;
  }

  Future<void> update(TaskTemplate tpl) async {
    await Db.instance.update(
      AppDatabase.tTemplate,
      tpl.toMap(),
      where: 'id = ?',
      whereArgs: [tpl.id],
    );
    await load();
  }

  Future<void> rename(int id, String title) async {
    await Db.instance.update(
      AppDatabase.tTemplate,
      {'title': title},
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  Future<void> setRemind(int id, String? time) async {
    await Db.instance.update(
      AppDatabase.tTemplate,
      {'remind_time': time},
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  /// 移动模板到另一个班次。
  Future<void> moveToShift(int id, int shiftTypeId) async {
    await Db.instance.update(
      AppDatabase.tTemplate,
      {'shift_type_id': shiftTypeId, 'parent_id': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  /// 同层级上下移动。
  Future<void> move(int id, int delta) async {
    final tpl = byId(id);
    if (tpl == null) return;
    final siblings = _all
        .where((t) => t.shiftTypeId == tpl.shiftTypeId && t.parentId == tpl.parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final index = siblings.indexWhere((t) => t.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;

    final db = Db.instance;
    // 重新顺序编号，避免历史 sort_order 存在重复值。
    final reordered = [...siblings];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    final batch = db.batch();
    for (var i = 0; i < reordered.length; i++) {
      batch.update(
        AppDatabase.tTemplate,
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [reordered[i].id],
      );
    }
    await batch.commit(noResult: true);
    await load();
  }

  /// 删除模板；连同其子任务。
  Future<void> delete(int id) async {
    final db = Db.instance;
    await db.delete(AppDatabase.tTemplate, where: 'parent_id = ?', whereArgs: [id]);
    await db.delete(AppDatabase.tTemplate, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// 清空某个班次的全部模板（含子任务）。
  Future<void> clearShift(int shiftTypeId) async {
    final db = Db.instance;
    final ids = forShift(shiftTypeId).map((t) => t.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      AppDatabase.tTemplate,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    await load();
  }

  /// 把某个班次的模板整份复制到另一个班次。
  Future<int> copyToShift(int fromShiftId, int toShiftId) async {
    final src = forShift(fromShiftId);
    if (src.isEmpty) return 0;
    final db = Db.instance;
    final idMap = <int, int>{};
    var order = 0;
    for (final tpl in src.where((t) => t.parentId == null)) {
      final id = await db.insert(AppDatabase.tTemplate, {
        'shift_type_id': toShiftId,
        'parent_id': null,
        'title': tpl.title,
        'remind_time': tpl.remindTime,
        'sort_order': order++,
      });
      idMap[tpl.id!] = id;
    }
    order = 0;
    for (final tpl in src.where((t) => t.parentId != null)) {
      final newParent = idMap[tpl.parentId!];
      if (newParent == null) continue;
      await db.insert(AppDatabase.tTemplate, {
        'shift_type_id': toShiftId,
        'parent_id': newParent,
        'title': tpl.title,
        'remind_time': tpl.remindTime,
        'sort_order': order++,
      });
    }
    await load();
    return idMap.length;
  }

  Future<int> _maxOrder(int shiftTypeId, int? parentId) async {
    final rows = await Db.instance.rawQuery(
      'SELECT MAX(sort_order) AS m FROM ${AppDatabase.tTemplate} '
      'WHERE shift_type_id = ? AND ${parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'}',
      parentId == null ? [shiftTypeId] : [shiftTypeId, parentId],
    );
    final value = rows.isEmpty ? null : rows.first['m'];
    return (value as num?)?.toInt() ?? -1;
  }
}
