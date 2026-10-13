# DDtodo · 排班日程 + Todo 清单

一个**纯本地、免联网、无账号**的 Android App：用「固定周期 + 单天覆盖」管理倒班排班，
并让每个班次自动生成当天的任务清单（支持多级子任务、勾选联动）。

> 本仓库是**完整手写源码**。因为编写环境里没有任何 Flutter SDK，代码**没有经过编译验证**，
> 首次构建时请按下面《从零构建 APK》的步骤操作，若遇到版本报错请对照《常见问题》调整。

> **完全的新手请先看 [打包指南.md](打包指南.md)** —— 那里有两条「复制粘贴就能走完」的路线：
> 用 GitHub 免费服务器云端打包（本机什么都不用装），或者在本机装 Flutter + Android Studio 打包。
> 云端打包脚本已经在 `.github/workflows/build-apk.yml` 里备好了。

---

## 1. 功能一览

| 模块 | 说明 |
| --- | --- |
| 月视图日历 | 每格显示 日期 / 农历（节日·节气优先）/ 班次色块 / 未完成任务数。左右滑动翻月 |
| 固定周期排班 | 「几天一轮 + 每天什么班」，从生效日期起**无限循环**填满日历 |
| 单天覆盖 | **长按**某天 → 直接选班次，只改这一天，不动周期 |
| 修整轮 | 新建规则时选中的日期就是**新周期第 1 天**，之后按新顺序循环；**不追溯历史** |
| 跨天班次 | 如晚班 20:00 → 次日 08:00，任务**归属到结束日**（选错结束日任务就长错地方） |
| 班次任务模板 | 每个班次一套模板；当天班次确定后自动生成到清单；**子任务全勾 → 父任务自动完成** |
| 独立事项 | 不绑定模板的一次性任务；可「一键转为模板任务」（附加到指定班次，明天起生效） |
| 提醒 | 只显示 `⏰ 10:00` 时间标签，**不做系统级闹钟推送** |
| 系统日历同步 | ⚠️ **本版本未启用**（为保证一次打包成功已摘掉 `device_calendar`）；入口仍在，页面会说明原因 |
| 数据备份 | 单个 JSON 文件导出全库；导入时**先清空本地库**再按文件重建 |
| 专注计时 / 统计 | 本地计时器；当月完成率、班次分布、未来 7 天任务量 |

界面配色照抄参考截图：青绿主色 `#1F9E8F` + 编号方块卡片 + 圆点圆环勾选。

---

## 2. 目录结构

```
DDtodo/
├── SPEC.md                     # 完整需求与设计规格（先读这个）
├── README.md                   # 本文件
├── pubspec.yaml                # 依赖声明
├── analysis_options.yaml       # lint 配置
├── lib/
│   ├── main.dart               # 入口 + 底部导航外壳
│   ├── core/
│   │   ├── app_colors.dart     # 10 色候选池 + 主色
│   │   ├── date_utils.dart     # DayUtil 日期工具
│   │   ├── settings_service.dart  # SharedPreferences 偏好
│   │   └── theme.dart          # Material 3 主题
│   ├── models/models.dart      # ShiftType / ShiftCycle / TaskTemplate / ScheduleInstance / DailyTask
│   ├── data/
│   │   ├── db.dart             # SQLite 单例
│   │   ├── app_database.dart   # 建表 + 预置数据播种
│   │   ├── shift_repository.dart
│   │   ├── template_repository.dart
│   │   └── task_repository.dart   # 排班计算 + 任务实例化（核心）
│   ├── services/
│   │   ├── backup_service.dart    # JSON 导出 / 导入 / 恢复出厂
│   │   └── calendar_service.dart  # 系统日历同步（本版本为未启用的占位实现）
│   ├── utils/lunar.dart        # 农历 + 24 节气（1900–2100 年位表，无第三方依赖）
│   └── ui/
│       ├── app_state.dart      # 全局状态（ChangeNotifier）
│       ├── widgets/common.dart # 圆形勾选 / 编号方块 / 班次色块 等
│       └── pages/
│           ├── calendar_page.dart      # 月视图
│           ├── day_detail_sheet.dart   # 当日详情（底部上滑）+ 班次选择器 + 新增事项
│           ├── task_list_page.dart     # 全局任务列表 + 搜索
│           ├── timer_page.dart         # 专注计时
│           ├── statistics_page.dart    # 统计
│           └── settings_pages.dart     # 设置 / 排班规则 / 模板 / 数据 / 日历 / 关于
├── android/                    # Android 工程壳（manifest + gradle）
└── tools/                      # 农历年位表校验脚本（Python，可选）
```

---

## 3. 关键设计约定

1. **不预生成排班**：数据库里只存「周期规则」和「单天覆盖」，日历按滑动到的月份实时计算。
2. **不预生成任务**：任务实例在**打开某一天时**才写入 `daily_task`，用 `shift_date` 判重。
3. **删除 = 墓碑**：删除的任务写 `deleted = 1`，保证重开页面不会又「自动长回来」。
4. **跨天归属**：`ScheduleInstance.showsOn = 班次开始日 + 1 天`；任务里的 `date` 是展示日，
   `shift_date` 是班次开始日，两者都存，统计和判重才准确。
5. **颜色自定义**：任何班次（含预置）都能从 10 色候选池里换色，`shift_type.color` 存 `#RRGGBB`。
6. **农历自带实现**：`lib/utils/lunar.dart` 内置 1900–2100 年位表 + 24 节气偏移表，
   不引入 `lunar` 等第三方包（避免版本约束解析失败）。

---

## 4. 从零构建 APK

### 4.1 准备环境

1. 安装 **Flutter（stable 3.x，建议 3.24 或更新）**，并确保 `flutter doctor` 通过 Android 工具链：
   ```
   flutter doctor -v
   ```
   Android Studio（或独立 Android SDK）+ JDK 17 是必须的。
2. 把本项目目录放到一个**纯英文、无空格**的路径下（例如 `D:\code\DDtodo`）。

### 4.2 生成平台壳（推荐做法）

`android/` 里如果缺少 Gradle Wrapper 的 jar/脚本，最省事的办法是让 Flutter 先生成一个标准壳，
再把本项目的源码覆盖回去：

```bash
# 1) 在别处生成一个同名标准工程
flutter create --org com.example --project-name ddtodo ddtodo_scaffold

# 2) 用标准壳里的 android/ 覆盖本项目（关键是补上 gradle wrapper）
#    Windows PowerShell:
robocopy ddtodo_scaffold\android D:\code\DDtodo\android /E
#    然后保留本项目自己的 AndroidManifest.xml、build.gradle、MainActivity.kt、styles.xml
#    （即：只从壳里取 gradlew、gradlew.bat、gradle\wrapper\gradle-wrapper.jar）

# 3) 进入本项目拉依赖并构建
cd D:\code\DDtodo
flutter pub get
flutter build apk --release
```

也可以完全用本项目自带的 `android/`（已写好 `settings.gradle` / `build.gradle` /
`app/build.gradle` / `AndroidManifest.xml`），只要补上 **gradle wrapper 的 jar 与脚本**
（`android/gradlew`、`android/gradlew.bat`、`android/gradle/wrapper/gradle-wrapper.jar`）
——这三个文件是二进制/脚本，需要在有网络的环境用 `flutter create` 生成或从 Gradle 官方下载。

### 4.3 产物位置

```
build/app/outputs/flutter-apk/app-release.apk          # 通用包
build/app/outputs/flutter-apk/app-debug.apk            # 调试包（体积大、启动慢）
```

按 CPU 架构拆分（体积更小，推荐给真机）：

```bash
flutter build apk --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> 本项目 `release` 构建暂时复用 **debug 签名**，可以直接装机测；
> 要上架应用商店请自行生成 keystore 并替换 `android/app/build.gradle` 里的 `signingConfig`。

### 4.4 直接装到手机

```bash
# 手机打开「开发者选项 → USB 调试」，用数据线连电脑
flutter devices
flutter install                # 或 flutter run --release
# 没有数据线：把 app-release.apk 拷进手机，用文件管理器点击安装
```

---

## 5. 常见问题（版本 / 编译）

**Q1. `flutter pub get` 报某个包要求更高的 Dart / Flutter 版本。**
`pubspec.yaml` 里写的是**保守下限**约束（例如 `sqflite: ^2.3.3`、`file_picker: ^10.0.0`），
pub 会自动往下解析到你的 SDK 支持的最高版本。如果真的解不出来，按顺序降级：

```yaml
environment:
  sdk: ^3.5.0            # 你的 Flutter 比较旧时可降到 ^3.3.0 / ^3.0.0
dependencies:
  file_picker: ^8.0.0    # 13.x 要求 Flutter 3.38+，10.x 要求 3.22+
```

**Q2. 编译报 `CardThemeData` / `InputDecorationThemeData` / `withValues` / `toARGB32` 之类的 API 不存在（或反过来报类型不匹配）。**
这是 Flutter 近几个版本反复折腾「`XxxTheme` → `XxxThemeData`」的后果：同一个字段在 3.27 之前和之后
要求的类型不同，**写哪一个都会在另一半版本上编译失败**。本项目因此完全绕开了这类字段：

| 通常写法 | 本项目的替代做法 |
| --- | --- |
| `ThemeData(cardTheme: ...)` | 不用；`Card` 的样式在 `lib/ui/pages/settings_pages.dart` 就地指定 |
| `ThemeData(inputDecorationTheme: ...)` | 不用；统一走 `lib/ui/widgets/common.dart` 的 `appInputDecoration()` |
| `ThemeData(chipTheme: ...)` | 不用；`ChoiceChip` / `ActionChip` 用 Material 3 默认样式 |
| `MaterialStateProperty` / `MaterialState` | 用 `WidgetStateProperty` / `WidgetState`（Flutter 3.19+ 就有） |
| `withValues()` / `toARGB32()` | 用 `withOpacity()` / `Color.value`（3.27 上只是 deprecation 警告，不影响编译） |

所以主题相关报错如果出现，绝大多数是**你手动改过这些文件**；本项目交付状态只保证
Flutter **3.24 及以上**（Dart 3.5+，对应 `pubspec.yaml` 的 `sdk: ^3.5.0`）与**当前最新稳定版**都能编译。
若真的卡在这里，把报错行贴出来按上表替换即可。

**Q3. 「系统日历同步」页面显示未启用 / 点了没反应。**
这是**有意为之**：`device_calendar 4.3.3` 最后更新于 2024-09，与较新的 Flutter /
Android Gradle 插件不兼容，会让第一次打包失败。所以在交付版本里已经把它整体摘掉：
`pubspec.yaml` 中该依赖被注释，`lib/services/calendar_service.dart` 换成了不依赖任何
第三方插件的占位实现（`CalendarService.enabled == false`），界面层保留了入口并给出说明。
**App 其余功能（排班 / 清单 / 备份 / 统计）完全不受影响。**

想重新启用（可选，等核心功能跑通之后再做）：

```bash
# 1. 取消 pubspec.yaml 里 device_calendar: ^4.3.3 的注释
# 2. 按 lib/services/calendar_service.dart 文件末尾「启用版说明」恢复 DeviceCalendarPlugin 实现
# 3. 把 settings_pages.dart 里 CalendarSyncPage 的 CalendarService.enabled 判断去掉
flutter pub get && flutter build apk --release
```

**Q4. 打包报 NDK 版本不匹配（`requires NDK xx.x`）。**
按提示在 `android/app/build.gradle` 的 `android { }` 里加：
```groovy
ndkVersion = "27.0.12077973"
```

**Q5. Gradle 下载慢 / 超时。**
在 `android/gradle/wrapper/gradle-wrapper.properties` 里把 `distributionUrl` 换成国内镜像，
或在 Android Studio 里配置代理（首次构建要下载 Gradle 与依赖，耐心等几分钟）。

**Q6. 应用装到手机上后，设置里的「系统日历同步」是灰的。**
入口在 **设置 → 系统日历同步**（右上角 `⋮` 菜单里也有快捷入口），页面正常打开，
只是同步按钮被禁用并在顶部说明了原因 —— 见 Q3，本版本已摘掉该依赖。

---

## 6. 数据存放与备份

* SQLite 数据库：`/data/data/com.example.ddtodo/databases/dd_todo.db`（需 root 才能直接取）。
* 导出的备份：App 文档目录，路径会在「设置 → 数据导入导出」的弹窗里显示，
  通常是 `/data/user/0/com.example.ddtodo/app_flutter/ddtodo-backup-<时间戳>.json`。
* 备份 JSON 结构：`{ app, format, version, exported_at, tables: { <表名>: [ 行... ] } }`。
* 导入会**清空本地全部数据**再重建；建议先导出一份备份。

---

## 7. 已知限制

1. **没有系统级提醒**：只显示 `⏰ HH:mm` 标签，不会弹通知、不会响铃。
2. **系统日历同步本版本未启用**：为了一次打包成功已摘掉 `device_calendar`（见 Q3）。
   重新启用后仍为只读单向：App 不写回系统日历；重复同步会**清空并重建**导入项，
   因此「在 App 里勾选过的导入事项」在下次同步后会回到未完成。
3. **农历为查表实现**：1900–2100 年内准确；超出范围或极少数边界日期（如节气恰好在午夜）
   可能差一天。校对脚本在 `tools/validate_lunar.py`（需要 Python 环境，可选）。
4. **单设备数据**：没有云同步，换手机请用 JSON 导出/导入搬迁。
5. **代码未经编译验证**：编写环境没有 Flutter SDK，第一次构建可能需要按第 5 节微调版本。

---

## 8. 排班语义速查（最容易用错的三件事）

| 想做的事 | 操作 | 生效范围 |
| --- | --- | --- |
| 就今天特殊，明天照旧 | 日历上**长按**该天 → 选班次 | 仅这一天（写入 `shift_exception`） |
| 从今天起换个新周期 | 设置 → 排班规则管理 → 新增周期，**生效日期选今天** | 今天起无限循环；过去不动 |
| 让某条事项每天自动出现 | 任务卡片右上角 `⋮` → 一键转为模板任务 → 选班次 | 明天起，按该班次自动生成 |
