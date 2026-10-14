import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量偏好设置。数据库里放业务数据，这里只放 UI 偏好与一次性初始化标记。
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs);

  final SharedPreferences _prefs;

  static const _kInitialized = 'db_initialized_v1';
  static const _kShowLunar = 'show_lunar';
  static const _kWeekStartMonday = 'week_start_monday';
  static const _kLastDate = 'last_selected_date';

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService._(prefs);
  }

  bool get isInitialized => _prefs.getBool(_kInitialized) ?? false;

  Future<void> markInitialized() async {
    await _prefs.setBool(_kInitialized, true);
    notifyListeners();
  }

  /// 首次启动标记。数据库被清空（导入备份）后需要重置，以便重新播种预置数据。
  Future<void> resetInitialized() async {
    await _prefs.setBool(_kInitialized, false);
    notifyListeners();
  }

  bool get showLunar => _prefs.getBool(_kShowLunar) ?? true;

  Future<void> setShowLunar(bool v) async {
    await _prefs.setBool(_kShowLunar, v);
    notifyListeners();
  }

  bool get weekStartMonday => _prefs.getBool(_kWeekStartMonday) ?? true;

  Future<void> setWeekStartMonday(bool v) async {
    await _prefs.setBool(_kWeekStartMonday, v);
    notifyListeners();
  }

  // ------------------------------------------- 手动指定生效的排班周期
  //
  // 没有值 = 不指定：按「生效日期最近的那一条」自动生效（旧行为）。
  // 在周期列表里点了「设为生效」之后固定用那一条，并从 [_kActiveCycleFrom]
  // 那天起生效（只影响今天及以后，过去不变）。
  static const _kActiveCycleId = 'active_cycle_id';
  static const _kActiveCycleFrom = 'active_cycle_from';

  int? get activeCycleId {
    final v = _prefs.getInt(_kActiveCycleId);
    return (v == null || v <= 0) ? null : v;
  }

  /// 手动指定生效周期的起始日（yyyy-MM-dd）；未指定返回 null。
  String? get activeCycleFrom => _prefs.getString(_kActiveCycleFrom);

  /// 指定生效周期；`id` 传 null 表示恢复「按最近一条自动生效」。
  Future<void> setActiveCycle(int? id, {String? from}) async {
    if (id == null) {
      await _prefs.remove(_kActiveCycleId);
      await _prefs.remove(_kActiveCycleFrom);
    } else {
      await _prefs.setInt(_kActiveCycleId, id);
      if (from != null) await _prefs.setString(_kActiveCycleFrom, from);
    }
    notifyListeners();
  }

  String? get lastDate => _prefs.getString(_kLastDate);

  Future<void> setLastDate(String iso) async {
    await _prefs.setString(_kLastDate, iso);
  }
}
