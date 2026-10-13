# DDtodo — 需求与设计规格（锁定版）

本文件是实现的唯一事实来源：原始需求（用户消息 m00003）+ 澄清问答（用户答复 m00073）。

## 0. 环境事实（影响交付方式）

- 开发会话内 **PowerShell 完全不可用**（`Error: SetNamedSecurityInfoW failed (Win32 5): grantWrite(D:\DDtodo)`），
  因此**无法**运行 `flutter create` / `flutter pub get` / `flutter build apk`，
  也无法用 Gradle 生成二进制文件 `gradle/wrapper/gradle-wrapper.jar`。
- 用户本机**尚未安装 Flutter SDK**。
- 交付方式（用户已确认）：手写全套源码 + 精确的打包命令；
  `android/` 由 `flutter create .` 生成（该命令会保留 `lib/`、`pubspec.yaml`、`README.md`）。

## 1. 技术栈与交付

- Flutter + SQLite（`sqflite`）+ `shared_preferences`（偏好）+ `path_provider` + `path`
  + `file_picker`（导入时选 JSON 文件）。
- 纯本地运行，无云服务，无账号系统。
- 应用名 **DDtodo**；Android `applicationId` = `com.example.ddtodo`。
- **本版本移除了 `device_calendar`**（原计划的系统日历同步，见 2.4）：该插件最后更新于
  2024-09，与较新的 Flutter / Android Gradle 插件存在不兼容风险，会让第一次打包失败。
  为保证「一次打包成功」，`pubspec.yaml` 中该依赖已注释、日历权限已注释、
  `lib/services/calendar_service.dart` 改为不依赖任何插件的占位实现
  （`CalendarService.enabled == false`，界面保留入口并显示说明）。恢复方法写在
  `README.md` Q3 与 `lib/services/calendar_service.dart` 文件末尾。
- `intl` 也未使用（日期格式化由 `lib/core/date_utils.dart` 与 `lib/utils/lunar.dart` 自己实现）。

## 2. 核心业务逻辑

### 2.1 排班
- 预置班次：早班、中班、晚班、工作班、休息；用户可新增自定义班次（名称 + 颜色）。
- **10 个候选颜色**，用户可为每个班次设置（含预置班次）。若预置班次颜色被改了，其余未被指定的班次按候选池顺序自动分配。
- 固定周期循环：`循环天数` + `生效日期(start_date)` + 模式数组（如 `["早","早","晚","休"]`），无限循环。
- 单天覆盖：长按某天直接弹窗切换当天班次，立即生效，不二次确认，不影响循环。
- **修改整轮排班**：选中那天 = 新周期第 1 天，之后按新模式无限循环。
- **绝不追溯**：过去日期保持原样。新建/修改任务模板同样不追溯（只影响今天及以后）。
- 节假日照常循环，不跳过、不顺延（用户自行单天覆盖）。

### 2.2 跨天班次（用户答复：跨天班次全部归属到结束日那天）
- 晚班 20:00→次日 08:00 视为跨天班次；其任务清单全部归到**结束日**（13 日晚班 → 显示在 14 日列表）。
- 14 日列表内容 = 13 日晚班（跨天，标为「昨日」）+ 14 日自己的班次（若非跨天）。
- 任务只在「结束日」生成一次，不重复。

### 2.3 任务模板与每日清单
- 每个班次一套模板任务，支持多级子任务（`parent_id`）。
- 班次确定后自动实例化模板到当天清单（动态生成，不预生成多年数据）。
- 子任务全勾选 → 父任务自动完成；父任务取消 → 子任务取消。
- 单天删除任务不影响模板（第二天照常生成）。
- 每日独立事项：可添加，不绑定模板，支持「一键转为模板任务」（选择附加到哪个班次）。
- 提醒：仅显示 `⏰ 10:00` 时间标签，不做系统级闹钟。

### 2.4 系统日历（⚠️ 本版本未启用，见第 1 节说明）
- 目标行为：仅 `系统日历 → App` 单向导入；设置页按钮手动触发；读取过去与未来所有日程。
- 导入项作为「每日单独事项」展示，**灰色字体 + 日历图标**与 App 自带事项区分。
- 勾选仅改 App 内状态，不写回系统日历。
- 当前状态：界面与代码骨架保留（`CalendarSyncPage` + `CalendarService`），
  但 `CalendarService.enabled == false`，同步按钮禁用并在页面顶部说明原因；
  「清除已导入的日历事项」仍然可用。

## 3. 数据库表

| 表 | 字段 |
|---|---|
| `shift_type` | id, name, color, is_preset |
| `shift_cycle` | id, name, start_date, cycle_days, pattern_json |
| `shift_exception` | date (PK), override_shift_type_id |
| `task_template` | id, shift_type_id, title, parent_id, frequency, sort_order |
| `daily_task` | id, date, shift_type_id, title, is_completed, is_custom, source_type, remind_time, parent_id, template_id, shift_date |

`source_type` = `app` | `calendar`；`shift_date` = 生成该任务的班次所属日（跨天时 ≠ date）。

## 4. UI

- 日历主页面：月视图，日期格含日期数字、农历、班次色块（自定义颜色）、任务数量圆点。
- 当日详情页：底部上滑弹出；顶部当日班次（可点击切换）；卡片展示班次任务集（可收起/展开）；再展示独立事项与系统日历事项；右下悬浮 `+`。
- 底部导航：日历、任务列表、统计、设置、我的（图 1 的 5 个图标）。
- 视觉：照抄图 2 —— 青绿主题、编号方块、圆点/圆环勾选、卡片、悬浮 `+`、圆角。

## 5. 性能与完整性

- **不预生成排班数据**：数据库只存周期规则与单天覆盖，UI 按滚动到的月份实时计算。
- 导出 JSON 含全部表；导入先清空全部表再重建。

## 6. 打包（用户本机执行）

```powershell
cd D:\DDtodo
flutter create --platforms=android --org com.example --project-name ddtodo .
flutter pub get
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk
```
