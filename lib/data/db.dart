import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// 数据库生命周期管理（单例）。
///
/// 放在独立文件里，避免 `AppDatabase`（纯结构定义）反向依赖 path_provider。
class Db {
  Db._();

  static Database? _db;

  static Database get instance {
    final db = _db;
    if (db == null) {
      throw StateError('数据库尚未初始化，请先 await Db.open()');
    }
    return db;
  }

  static bool get isOpen => _db != null;

  static Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, AppDatabase.dbName);
    final db = await openDatabase(
      path,
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.onCreate,
      onUpgrade: AppDatabase.onUpgrade,
    );
    _db = db;
    return db;
  }

  /// 数据库文件路径，设置页展示用。
  static Future<String> path() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, AppDatabase.dbName);
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 关闭并删除数据库文件（导入备份、恢复出厂设置时用）。
  static Future<void> wipe() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, AppDatabase.dbName);
    await close();
    await deleteDatabase(path);
  }

  /// 重新打开（wipe 之后调用）。
  static Future<Database> reopen() async {
    await open();
    return instance;
  }
}
