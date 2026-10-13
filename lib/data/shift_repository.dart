import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_colors.dart';
import '../core/date_utils.dart';
import '../models/models.dart';
import 'app_database.dart';
import 'db.dart';

/// 班次类型与排班周期的读写 + 内存缓存。
class ShiftRepository extends ChangeNotifier {
  List<ShiftType> _shiftTypes = [];
  List<ShiftCycle> _cycles = [];
  Map<String, int> _exceptions = {};

  List<ShiftType> get shiftTypes => _shiftTypes;
  List<ShiftCycle> get cycles => _cycles;

  /// 未被归档的班次，按 sort_order 排列。
  List<ShiftType> get activeShiftTypes =>
      _shiftTypes.where((s) => !s.archived).toList();

  /// 周期模板候选（休息日也能排进周期，这里只排除归档班次）。
  List<ShiftType> get schedulable =>
      _shiftTypes.where((s) => !s.archived).toList();

  ShiftType? byId(int? id) {
    if (id == null) return null;
    for (final s in _shiftTypes) {
      if (s.id == id) return s;
    }
    return null;
  }

  ShiftType? byKind(ShiftKind kind) {
    for (final s in _shiftTypes) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  /// 该日期是否有单天覆盖。
  int? exceptionOf(DateTime date) => _exceptions[DayUtil.iso(date)];

  Map<String, int> get exceptions => Map.unmodifiable(_exceptions);

  /// 生效中的周期：start_date <= 目标日 且 id 最大（最近创建的优先）。
  ShiftCycle? activeCycleFor(DateTime date) {
    final iso = DayUtil.iso(date);
    ShiftCycle? best;
    for (final c in _cycles) {
      if (c.startDate.compareTo(iso) <= 0) {
        if (best == null || c.id > best.id) best = c;
      }
    }
    return best;
  }

  // ------------------------------------------------------------ 读取

  Future<void> load() async {
    final db = Db.instance;
    final shiftRows = await db.query(AppDatabase.tShiftType, orderBy: 'sort_order ASC, id ASC');
    final cycleRows = await db.query(AppDatabase.tCycle, orderBy: 'start_date ASC, id ASC');
    final excRows = await db.query(AppDatabase.tException);

    _shiftTypes = shiftRows.map(ShiftType.fromMap).toList();
    _cycles = cycleRows.map(ShiftCycle.fromMap).toList();
    _exceptions = {
      for (final r in excRows)
        (r['date'] as String): (r['override_shift_type_id'] as num).toInt(),
    };
    notifyListeners();
  }

  // ------------------------------------------------------ 班次类型 CRUD

  Future<int> insertShiftType(ShiftType type) async {
    final db = Db.instance;
    final id = await db.insert(AppDatabase.tShiftType, type.toMap()..remove('id'));
    await load();
    return id;
  }

  Future<void> updateShiftType(ShiftType type) async {
    final db = Db.instance;
    await db.update(
      AppDatabase.tShiftType,
      type.toMap(),
      where: 'id = ?',
      whereArgs: [type.id],
    );
    await load();
  }

  /// 删除班次类型。被模板引用时改为归档，避免历史数据错乱。
  Future<void> deleteShiftType(int id) async {
    final db = Db.instance;
    final tplCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM ${AppDatabase.tTemplate} WHERE shift_type_id = ?',
          [id],
        )) ??
        0;
    final usedByCycle = _cycles.any((c) => c.pattern.contains(id));
    if (tplCount > 0 || usedByCycle) {
      await db.update(
        AppDatabase.tShiftType,
        {'archived': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete(AppDatabase.tShiftType, where: 'id = ?', whereArgs: [id]);
      await db.delete(AppDatabase.tException, where: 'override_shift_type_id = ?', whereArgs: [id]);
    }
    await load();
  }

  Future<void> restoreShiftType(int id) async {
    await Db.instance.update(
      AppDatabase.tShiftType,
      {'archived': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  /// 统计每个班次被多少条模板任务引用（设置页删除确认用）。
  Future<Map<int, int>> templateCountByShift() async {
    final rows = await Db.instance.rawQuery(
      'SELECT shift_type_id, COUNT(*) AS c FROM ${AppDatabase.tTemplate} GROUP BY shift_type_id',
    );
    return {
      for (final r in rows) (r['shift_type_id'] as num).toInt(): (r['c'] as num).toInt(),
    };
  }

  // ---------------------------------------------------------- 周期 CRUD

  /// 新建周期：`startDate` 那天即为模式数组的第 1 天，之后无限循环。
  Future<int> createCycle({
    required String name,
    required DateTime startDate,
    required List<int> pattern,
  }) async {
    final db = Db.instance;
    final id = await db.insert(AppDatabase.tCycle, {
      'name': name,
      'start_date': DayUtil.iso(startDate),
      'pattern': pattern.join(','),
      'created_at': DateTime.now().toIso8601String(),
    });
    await load();
    return id;
  }

  Future<void> updateCycle(ShiftCycle cycle) async {
    await Db.instance.update(
      AppDatabase.tCycle,
      cycle.toMap(),
      where: 'id = ?',
      whereArgs: [cycle.id],
    );
    await load();
  }

  Future<void> deleteCycle(int id) async {
    await Db.instance.delete(AppDatabase.tCycle, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  // ---------------------------------------------------------- 单天覆盖

  /// 单天覆盖：只影响这一天。传 null 班次表示恢复按周期计算。
  Future<void> setException(DateTime date, int? shiftTypeId) async {
    final db = Db.instance;
    final iso = DayUtil.iso(date);
    if (shiftTypeId == null) {
      await db.delete(AppDatabase.tException, where: 'date = ?', whereArgs: [iso]);
    } else {
      await db.insert(
        AppDatabase.tException,
        {'date': iso, 'override_shift_type_id': shiftTypeId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await load();
  }

  /// 批量写入覆盖（「修整轮」用）。
  Future<void> setExceptions(Map<String, int> map) async {
    if (map.isEmpty) return;
    final db = Db.instance;
    final batch = db.batch();
    map.forEach((date, shiftId) {
      batch.insert(
        AppDatabase.tException,
        {'date': date, 'override_shift_type_id': shiftId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
    await load();
  }

  /// 清空所有单天覆盖与周期，回到「无排班」状态。
  Future<void> clearSchedule() async {
    final db = Db.instance;
    await db.delete(AppDatabase.tException);
    await db.delete(AppDatabase.tCycle);
    // 清掉按班次自动生成的任务，保留用户自己加的事项与被导入的日历事项。
    await db.delete(
      AppDatabase.tDaily,
      where: 'is_custom = 0 AND source_type = ?',
      whereArgs: [TaskSource.app.name],
    );
    await load();
  }

  /// 新建自定义班次时按调色板轮转取色。
  String nextPaletteColor() {
    final used = _shiftTypes.map((s) => s.colorHex.toUpperCase()).toSet();
    for (final c in AppColors.palette) {
      final hex = AppColors.toHex(c).toUpperCase();
      if (!used.contains(hex)) return hex;
    }
    return AppColors.toHex(AppColors.palette[_shiftTypes.length % AppColors.palette.length]);
  }
}
