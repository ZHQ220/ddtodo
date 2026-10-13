import 'package:flutter/material.dart' show Color;

import '../data/task_repository.dart';

/// 系统日历同步（**当前构建版本：未启用**）。
///
/// 为什么是空的：
///   这条功能依赖第三方包 `device_calendar`。该包最后发布于 2024 年 9 月，
///   与较新的 Flutter / Android Gradle 插件版本存在不兼容风险，会让「第一次打包」
///   失败。为了让 DDtodo 的核心功能（排班日历 / 任务清单 / 备份 / 统计）
///   一次就能打包成功，这一版先把该依赖整体摘掉。
///
///   **重新启用的方法**（三步，改完再打包即可）：
///     1. 在 `pubspec.yaml` 的 dependencies 里取消 `device_calendar: ^4.3.3` 的注释；
///     2. 用 git / 备份里的旧版覆盖本文件（旧版是通过 `DeviceCalendarPlugin`
///        真正读系统日历的实现，逻辑见本文件末尾的说明注释）；
///     3. `flutter pub get` 后重新 `flutter build apk --release`。
///
///   本文件对外暴露的**类名、方法名、字段名与启用版完全一致**
///   （`CalendarService` / `CalendarSyncResult` / `Calendar` / `CalendarLabel`），
///   所以界面层（`settings_pages.dart` 的 `CalendarSyncPage`）一行都不用改。
class CalendarService {
  CalendarService(this._tasks);

  final TaskRepository _tasks;

  /// 本构建版本是否真的接入了系统日历。界面据此显示提示。
  static const bool enabled = false;

  /// 未启用时给用户看的说明。
  static const String disabledMessage =
      '当前版本为了保证一次打包成功，暂时移除了「系统日历同步」模块。'
      '排班、清单、农历、备份、统计等功能不受影响。';

  /// 申请日历读取权限。未启用时直接返回 false。
  Future<bool> ensurePermission() async => false;

  /// 可读取的日历列表。未启用时恒为空。
  Future<List<Calendar>> calendars() async => const <Calendar>[];

  /// 执行同步。未启用时返回一条说明，不做任何数据改动。
  Future<CalendarSyncResult> sync() async {
    return const CalendarSyncResult(ok: false, message: disabledMessage);
  }

  /// 清除之前导入过的日历事项。**这个仍然可用**：
  /// 如果你以前用过带日历功能的版本、数据库里留下了灰色导入项，可以清掉它们。
  Future<void> clearImported() => _tasks.clearImported();
}

/// 同步结果。
class CalendarSyncResult {
  const CalendarSyncResult({
    required this.ok,
    required this.message,
    this.imported = 0,
    this.skipped = 0,
    this.calendars = 0,
  });

  final bool ok;
  final String message;
  final int imported;
  final int skipped;
  final int calendars;
}

/// 日历信息。
///
/// 字段名与 `device_calendar` 包的 `Calendar` 保持一致（`id` / `name` / `color`），
/// 这样重新启用该包时界面层无需改动。
class Calendar {
  const Calendar({this.id, this.name, this.color});

  final String? id;
  final String? name;

  /// ARGB 整数颜色值。
  final int? color;
}

/// 便于 UI 层展示日历名称与颜色。
extension CalendarLabel on Calendar {
  String get displayName =>
      (name ?? '').trim().isEmpty ? '未命名日历' : name!.trim();

  Color get displayColor {
    final argb = color;
    if (argb == null) return const Color(0xFF8A8F98);
    return Color(argb);
  }
}

// ---------------------------------------------------------------- 启用版说明
//
// 启用版（本文件的旧实现）大致逻辑如下，重新接入 `device_calendar` 时按此恢复：
//
//   final _plugin = DeviceCalendarPlugin();
//
//   Future<bool> ensurePermission() async {
//     final r = await _plugin.hasPermissions();
//     if (r.isSuccess && (r.data ?? false)) return true;
//     final q = await _plugin.requestPermissions();
//     return q.isSuccess && (q.data ?? false);
//   }
//
//   Future<List<Calendar>> calendars() async {
//     final r = await _plugin.retrieveCalendars();
//     return r.isSuccess ? (r.data ?? []) : [];
//   }
//
//   // 读取 1970–2100 的全部日程；失败则按 10 年分段重试
//   Future<List<Event>> eventsOf(String calendarId) async { ... }
//
//   // sync(): 先 clearImported()，再按 external_id 去重，
//   //         用 TaskRepository.addCustomTask(source: TaskSource.calendar) 写入；
//   //         全天事件按 UTC 取日期，其余按本地日期。
//
// 相关文件：需求见 SPEC.md「系统日历」一节。
