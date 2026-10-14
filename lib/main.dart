import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ui/app_state.dart';
import 'ui/pages/calendar_page.dart';
import 'ui/pages/settings_pages.dart';
import 'ui/pages/statistics_page.dart';
import 'ui/pages/task_list_page.dart';
import 'ui/pages/timer_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.boot();
  runApp(DDTodoApp(state: state));
}

/// DDtodo —— 排班日程 + Todo 清单。
class DDTodoApp extends StatelessWidget {
  const DDTodoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DDtodo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeShell(state: state),
      routes: {
        '/shifts': (_) => ShiftSettingsPage(state: state),
        '/templates': (_) => TemplateSettingsPage(state: state),
        '/data': (_) => DataSettingsPage(state: state),
        '/about': (_) => const AboutPage(),
      },
    );
  }
}

/// 底部导航容器。对应参考图里的 5 个入口：
/// 日历 / 清单 / 计时 / 统计 / 设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _refreshToken = 0;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarPage(state: state),
      TaskListPage(key: ValueKey('tasks-$_refreshToken'), state: state),
      const TimerPage(),
      StatisticsPage(state: state),
      SettingsPage(
        state: state,
        onDataChanged: () => setState(() => _refreshToken++),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        leading: _index == 0
            ? IconButton(
                tooltip: '回到今天',
                icon: const Icon(Icons.today),
                onPressed: state.goToToday,
              )
            : null,
        actions: [
          if (_index == 0)
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await state.hardRefresh();
                if (!mounted) return;
                setState(() => _refreshToken++);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已刷新：排班与任务清单重新读取'),
                    duration: Duration(milliseconds: 1200),
                  ),
                );
              },
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              // 数据页要回调外壳刷新任务列表，所以单独用 MaterialPageRoute 打开。
              if (value == '/data') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DataSettingsPage(
                      state: state,
                      onDataChanged: () => setState(() => _refreshToken++),
                    ),
                  ),
                );
                return;
              }
              // 从设置类页面返回后刷新任务列表与日历（模板/排班改动会影响任务）。
              Navigator.of(context).pushNamed(value).then((_) {
                if (mounted) setState(() => _refreshToken++);
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: '/shifts', child: Text('排班规则管理')),
              PopupMenuItem(value: '/templates', child: Text('班次任务模板')),
              PopupMenuItem(value: '/data', child: Text('数据导入导出')),
            ],
          ),
        ],
      ),
      // 监听全局状态：月份切换、任务增删、模板改动后立刻刷新当前页面。
      // 没有这层监听时，左右滑动月份虽然会换页，但标题和「任务数量圆点」不会更新
      // （滑到的那一个月永远显示不出数字）。
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: '日历'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rtl), label: '清单'),
          BottomNavigationBarItem(icon: Icon(Icons.timer_outlined), label: '计时'),
          BottomNavigationBarItem(icon: Icon(Icons.insights), label: '统计'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '设置'),
        ],
      ),
    );
  }

  static const List<String> _titles = ['DDtodo', '任务清单', '专注计时', '统计', '设置'];
}
