import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// 专注计时页（对应参考图底部导航里的计时入口）。
///
/// 纯本地计时，不写入任何数据；用于上班时给某项工作计时。
class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  static const List<int> _presets = [15, 25, 45, 60];

  int _totalSeconds = 25 * 60;
  int _remaining = 25 * 60;
  Timer? _timer;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(int minutes) {
    _timer?.cancel();
    setState(() {
      _running = false;
      _totalSeconds = minutes * 60;
      _remaining = _totalSeconds;
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_remaining <= 0) _remaining = _totalSeconds;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remaining <= 1) {
        timer.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('计时结束')),
        );
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remaining = _totalSeconds;
    });
  }

  String get _text {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalSeconds == 0 ? 0.0 : 1 - _remaining / _totalSeconds;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        children: [
          SizedBox(
            height: 240,
            width: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 240,
                  width: 240,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    backgroundColor: AppColors.tint(AppColors.primary, 0.14),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _text,
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _running ? '计时中…' : '已暂停',
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final minutes in _presets)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('$minutes 分钟'),
                    selected: _totalSeconds == minutes * 60,
                    onSelected: (_) => _select(minutes),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                label: Text(_running ? '暂停' : '开始'),
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.replay),
                label: const Text('重置'),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Text(
            '提示：计时只在本地运行，不做系统级闹钟推送。\n'
            '如果需要在某个时间点被提醒，请在任务上设置「⏰ 提醒时间」标签。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}
