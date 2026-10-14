import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/db.dart';

/// 备份文件结构（导入 / 导出共用的 JSON 契约）。
class BackupPayload {
  const BackupPayload({
    required this.version,
    required this.exportedAt,
    required this.tables,
  });

  final int version;
  final String exportedAt;
  final Map<String, List<Map<String, Object?>>> tables;

  Map<String, Object?> toJson() => {
        'app': 'DDtodo',
        'format': 'ddtodo-backup',
        'version': version,
        'exported_at': exportedAt,
        'tables': tables,
      };
}

/// 结果包装，方便 UI 区分成功 / 失败。
class BackupResult {
  const BackupResult({this.ok = false, this.path, this.message = ''});

  final bool ok;
  final String? path;
  final String message;
}

/// 数据导出 / 导入。
///
/// 需求约定：
///  * 导出为**单个 JSON 文件**，包含全部数据表；
///  * 导入前**先清空本地库**，再按 JSON 全量重建。
class BackupService {
  BackupService._();

  static const int formatVersion = 1;
  static const String fileNamePrefix = 'ddtodo-backup';

  /// 历史遗留列：v1 的建表语句里有这些列，v2 已经删掉。
  ///
  /// 导入旧备份时如果原样 insert，会报 `no such column`，所以先剔除。
  static const Map<String, List<String>> _legacyColumns = {
    // 「跨天班次」开关所在的列，功能已删除（现在由上下班时间自动判断）。
    AppDatabase.tShiftType: ['cross_day'],
  };

  /// 导出到应用文档目录，返回文件路径。
  static Future<BackupResult> exportToFile({String? directory}) async {
    try {
      final db = Db.instance;
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in AppDatabase.allTables) {
        tables[table] = await db.query(table);
      }

      final payload = BackupPayload(
        version: formatVersion,
        exportedAt: DateTime.now().toIso8601String(),
        tables: tables,
      );

      final dir = directory == null
          ? await getApplicationDocumentsDirectory()
          : Directory(directory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .split('.')
          .first;
      final file = File(p.join(dir.path, '$fileNamePrefix-$stamp.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload.toJson()),
        flush: true,
      );

      return BackupResult(ok: true, path: file.path, message: '导出成功');
    } catch (e) {
      return BackupResult(message: '导出失败：$e');
    }
  }

  /// 从 JSON 文本导入（先清空再重建）。
  static Future<BackupResult> importFromString(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const BackupResult(message: '文件格式不正确：顶层不是 JSON 对象');
      }
      final tableNode = decoded['tables'];
      if (tableNode is! Map) {
        return const BackupResult(message: '文件格式不正确：缺少 tables 字段');
      }
      final tables = <String, List<Map<String, Object?>>>{};
      tableNode.forEach((key, value) {
        if (value is List) {
          tables['$key'] = [
            for (final row in value)
              if (row is Map) row.map((k, v) => MapEntry('$k', v)),
          ];
        }
      });

      final unknown = tables.keys.where((k) => !AppDatabase.allTables.contains(k)).toList();
      if (unknown.isNotEmpty) {
        return BackupResult(
          message: '文件里包含未知数据表：${unknown.join('、')}',
        );
      }
      if (tables.isEmpty) {
        return const BackupResult(message: '文件里没有任何数据表');
      }

      await _replaceAll(tables);
      return BackupResult(ok: true, message: '导入成功，已按备份重建全部数据');
    } catch (e) {
      return BackupResult(message: '导入失败：$e');
    }
  }

  /// 从文件导入。
  static Future<BackupResult> importFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return const BackupResult(message: '文件不存在');
      }
      return importFromString(await file.readAsString());
    } catch (e) {
      return BackupResult(message: '读取文件失败：$e');
    }
  }

  /// 清空并重建全部表（放在一个事务里，失败自动回滚）。
  static Future<void> _replaceAll(Map<String, List<Map<String, Object?>>> tables) async {
    final db = Db.instance;
    await db.transaction((txn) async {
      // 先按依赖倒序清空，避免外键 / 索引残留。
      for (final table in AppDatabase.allTables.reversed) {
        await txn.delete(table);
      }
      for (final table in AppDatabase.allTables) {
        final rows = tables[table];
        if (rows == null) {
          // 备份里缺少这张表时，重新播种它的预置内容（shift_cycle /
          // shift_exception / daily_task 本身没有预置内容）。
          await AppDatabase.seedTable(txn, table);
          continue;
        }
        for (final row in rows) {
          final legacy = _legacyColumns[table];
          if (legacy != null) {
            for (final key in legacy) {
              row.remove(key);
            }
          }
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  /// 恢复出厂设置：清空数据后重新播种预置班次与模板。
  static Future<void> resetToFactory() async {
    final db = Db.instance;
    await db.transaction((txn) async {
      for (final table in AppDatabase.allTables.reversed) {
        await txn.delete(table);
      }
      await AppDatabase.seedAll(txn);
    });
  }

  /// 导出文件的默认展示目录。
  static Future<String> defaultDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}
