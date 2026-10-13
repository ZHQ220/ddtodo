import 'package:sqflite/sqflite.dart';

/// 数据库结构定义 + 预置数据播种。
///
/// 设计要点：
///  * 只持久化「规则」与「单天覆盖」，排班本身在 UI 层按需实时计算，绝不预生成多年数据。
///  * 每日任务实例按「打开某天」时才实例化，避免上万行无意义记录。
class AppDatabase {
  AppDatabase._();

  static const String dbName = 'dd_todo.db';
  static const int schemaVersion = 1;

  // ---------------------------------------------------------------- 表名
  static const String tShiftType = 'shift_type';
  static const String tCycle = 'shift_cycle';
  static const String tException = 'shift_exception';
  static const String tTemplate = 'task_template';
  static const String tDaily = 'daily_task';
  static const String tPatternTemplate = 'pattern_template';

  /// 导出/导入时需要完整搬运的表。
  static const List<String> allTables = [
    tShiftType,
    tCycle,
    tException,
    tTemplate,
    tDaily,
    tPatternTemplate,
  ];

  // ------------------------------------------------------------ 预置班次
  /// 预置班次：早班(绿) / 中班(红) / 晚班(蓝) / 工作班(橙) / 休息(灰)。
  /// `kind` 同时作为该班次在周期模板里的字母键（A/B/C/D/R）。
  static const List<Map<String, Object?>> presetShiftTypes = [
    {
      'name': '早班',
      'color': '#2FB344',
      'is_preset': 1,
      'kind': 'morning',
      'cross_day': 0,
      'start_time': '06:00',
      'end_time': '14:00',
      'sort_order': 0,
      'archived': 0,
    },
    {
      'name': '中班',
      'color': '#E5484D',
      'is_preset': 1,
      'kind': 'middle',
      'cross_day': 0,
      'start_time': '14:00',
      'end_time': '20:00',
      'sort_order': 1,
      'archived': 0,
    },
    {
      'name': '晚班',
      'color': '#3B82F6',
      'is_preset': 1,
      'kind': 'night',
      'cross_day': 1,
      'start_time': '20:00',
      'end_time': '08:00',
      'sort_order': 2,
      'archived': 0,
    },
    {
      'name': '工作班',
      'color': '#F59E0B',
      'is_preset': 1,
      'kind': 'work',
      'cross_day': 0,
      'start_time': '08:00',
      'end_time': '17:00',
      'sort_order': 3,
      'archived': 0,
    },
    {
      'name': '休息',
      'color': '#6B7280',
      'is_preset': 1,
      'kind': 'rest',
      'cross_day': 0,
      'start_time': null,
      'end_time': null,
      'sort_order': 4,
      'archived': 0,
    },
  ];

  // ------------------------------------------------------ 预置任务模板
  /// 预置的顶层模板任务（`shift` 为班次 kind）。
  static const List<Map<String, String?>> presetRootTasks = [
    {'shift': 'night', 'title': '报表', 'remind': null},
    {'shift': 'night', 'title': '一般联系', 'remind': null},
    {'shift': 'night', 'title': '机组启停', 'remind': null},
    {'shift': 'morning', 'title': '早班报表', 'remind': '07:00'},
    {'shift': 'morning', 'title': '机组启停', 'remind': null},
    {'shift': 'middle', 'title': '中班报表1', 'remind': null},
    {'shift': 'middle', 'title': '中班报表2', 'remind': null},
    {'shift': 'middle', 'title': '省间现货审核', 'remind': null},
    {'shift': 'middle', 'title': '机组启停', 'remind': null},
  ];

  /// 预置的子任务：挂在同班次下标题为 `parent` 的顶层任务上。
  static const List<Map<String, String?>> presetChildTasks = [
    {'shift': 'night', 'title': 'CPS拍照', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '平衡表+截图', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '国网云小报表', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '危险点分析文档', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '优化记录', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '一体化日报', 'parent': '报表', 'remind': null},
    {'shift': 'night', 'title': '市场截图', 'parent': '报表', 'remind': null},
  ];

  // ---------------------------------------------------- 预置周期模板
  /// 常见排班周期模板，用户点一下就套用（可再编辑）。
  static const List<Map<String, Object?>> presetPatterns = [
    {
      'name': '两班两倒（早早晚休）',
      'pattern': 'A-A-C-R',
      'letters': 'A:早班,C:晚班,R:休息',
      'sort_order': 0,
    },
    {
      'name': '四班三倒（早中晚休）',
      'pattern': 'A-B-C-R',
      'letters': 'A:早班,B:中班,C:晚班,R:休息',
      'sort_order': 1,
    },
    {
      'name': '白夜休休（工作工作休休）',
      'pattern': 'D-D-R-R',
      'letters': 'D:工作班,R:休息',
      'sort_order': 2,
    },
    {
      'name': '上二休二（工作休工作休）',
      'pattern': 'D-R-D-R',
      'letters': 'D:工作班,R:休息',
      'sort_order': 3,
    },
    {
      'name': '常白班（工作×5 休×2）',
      'pattern': 'D-D-D-D-D-R-R',
      'letters': 'D:工作班,R:休息',
      'sort_order': 4,
    },
  ];

  // ------------------------------------------------------------- 建表语句
  static const List<String> _createStatements = [
    '''
    CREATE TABLE $tShiftType (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      color       TEXT NOT NULL,
      is_preset   INTEGER NOT NULL DEFAULT 0,
      kind        TEXT NOT NULL DEFAULT 'custom',
      cross_day   INTEGER NOT NULL DEFAULT 0,
      start_time  TEXT,
      end_time    TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      archived    INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE $tCycle (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      start_date  TEXT NOT NULL,
      pattern     TEXT NOT NULL,
      created_at  TEXT
    )
    ''',
    '''
    CREATE INDEX idx_cycle_start ON $tCycle (start_date DESC)
    ''',
    '''
    CREATE TABLE $tException (
      date                  TEXT PRIMARY KEY,
      override_shift_type_id INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tTemplate (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_type_id INTEGER NOT NULL,
      parent_id     INTEGER,
      title         TEXT NOT NULL,
      remind_time   TEXT,
      sort_order    INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE INDEX idx_template_shift ON $tTemplate (shift_type_id, parent_id)
    ''',
    '''
    CREATE TABLE $tDaily (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      date          TEXT,
      shift_type_id INTEGER,
      shift_date    TEXT,
      title         TEXT NOT NULL,
      is_completed  INTEGER NOT NULL DEFAULT 0,
      is_custom     INTEGER NOT NULL DEFAULT 0,
      source_type   TEXT NOT NULL DEFAULT 'app',
      remind_time   TEXT,
      parent_id     INTEGER,
      template_id   INTEGER,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      deleted       INTEGER NOT NULL DEFAULT 0,
      external_id   TEXT
    )
    ''',
    '''
    CREATE INDEX idx_daily_date ON $tDaily (date, shift_date)
    ''',
    '''
    CREATE TABLE $tPatternTemplate (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      pattern     TEXT NOT NULL,
      letters     TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0
    )
    ''',
  ];

  /// 建表 + 首次播种。`seed` 为 false 时（导入备份后）只建表。
  static Future<void> onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final sql in _createStatements) {
      batch.execute(sql);
    }
    await batch.commit(noResult: true);
    await seedAll(db);
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 目前只有 v1，占位以便后续版本按 oldVersion 递进迁移。
  }

  /// 全量播种（班次 + 模板 + 周期模板）。
  static Future<void> seedAll(DatabaseExecutor db) async {
    await seedShiftTypes(db);
    await seedTemplates(db);
    await seedPatterns(db);
  }

  /// 只补某一张表的预置内容（导入备份后缺表时逐表调用）。
  static Future<void> seedTable(DatabaseExecutor db, String table) async {
    switch (table) {
      case tShiftType:
        await seedShiftTypes(db);
        break;
      case tTemplate:
        await seedTemplates(db);
        break;
      case tPatternTemplate:
        await seedPatterns(db);
        break;
      default:
        // shift_cycle / shift_exception / daily_task 没有预置内容。
        break;
    }
  }

  /// 写入预置班次。幂等：只有在表为空时才写入。
  static Future<void> seedShiftTypes(DatabaseExecutor db) async {
    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tShiftType')) ?? 0;
    if (count > 0) return;
    final batch = db.batch();
    for (final row in presetShiftTypes) {
      batch.insert(tShiftType, row);
    }
    await batch.commit(noResult: true);
  }

  /// 写入预置任务模板（父任务 + 子任务）。幂等：只有在表为空时才写入。
  static Future<void> seedTemplates(DatabaseExecutor db) async {
    final count =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tTemplate')) ?? 0;
    if (count > 0) return;

    final shifts = await db.query(tShiftType);
    final idByKind = <String, int>{};
    for (final row in shifts) {
      idByKind[(row['kind'] as String?) ?? ''] = row['id'] as int;
    }

    // 必须逐条 insert（而不是 batch）才能拿到父任务自增后的真实 id。
    final parents = <String, int>{};
    var order = 0;
    for (final tpl in presetRootTasks) {
      final shiftId = idByKind[tpl['shift']];
      if (shiftId == null) continue;
      final id = await db.insert(tTemplate, {
        'shift_type_id': shiftId,
        'parent_id': null,
        'title': tpl['title'],
        'remind_time': tpl['remind'],
        'sort_order': order++,
      });
      parents['${tpl['shift']}|${tpl['title']}'] = id;
    }

    var childOrder = 0;
    final childBatch = db.batch();
    for (final tpl in presetChildTasks) {
      final shiftId = idByKind[tpl['shift']];
      final parentId = parents['${tpl['shift']}|${tpl['parent']}'];
      if (shiftId == null || parentId == null) continue;
      childBatch.insert(tTemplate, {
        'shift_type_id': shiftId,
        'parent_id': parentId,
        'title': tpl['title'],
        'remind_time': tpl['remind'],
        'sort_order': childOrder++,
      });
    }
    await childBatch.commit(noResult: true);
  }

  /// 写入预置排班周期模板。幂等：只有在表为空时才写入。
  static Future<void> seedPatterns(DatabaseExecutor db) async {
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $tPatternTemplate')) ??
        0;
    if (count > 0) return;
    final batch = db.batch();
    for (final row in presetPatterns) {
      batch.insert(tPatternTemplate, row);
    }
    await batch.commit(noResult: true);
  }
}
