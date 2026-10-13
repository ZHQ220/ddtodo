import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量偏好设置。数据库里放业务数据，这里只放 UI 偏好与一次性初始化标记。
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs);

  final SharedPreferences _prefs;

  static const _kInitialized = 'db_initialized_v1';
  static const _kShowLunar = 'show_lunar';
  static const _kWeekStartMonday = 'week_start_monday';
  static const _kDefaultCrossDay = 'default_cross_day';
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

  /// 晚班跨天：默认开启，用户可在设置里关掉。
  bool get defaultCrossDay => _prefs.getBool(_kDefaultCrossDay) ?? true;

  Future<void> setDefaultCrossDay(bool v) async {
    await _prefs.setBool(_kDefaultCrossDay, v);
    notifyListeners();
  }

  String? get lastDate => _prefs.getString(_kLastDate);

  Future<void> setLastDate(String iso) async {
    await _prefs.setString(_kLastDate, iso);
  }
}
