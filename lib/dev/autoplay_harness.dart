import 'dart:async';

import 'package:flutter/material.dart';

import '../game/levels/generation/difficulty_mode.dart';
import '../screens/game_screen.dart';
import '../services/ads/no_op_ad_service.dart';
import '../services/game_audio.dart';
import '../theme/app_colors.dart';

/// Dev-only on-device playtest driver. Gated behind `--dart-define=AUTOPLAY=true`
/// in `main()`. Solver-driven autoplay across [perMode] levels of each mode,
/// logging structured `AUTOPLAY|…` lines (captured from the `flutter run`
/// console / logcat) for the playtest notes. Never shipped to production.
class AutoplayApp extends StatelessWidget {
  const AutoplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const _AutoplayHarness(),
    );
  }
}

class _AutoplayHarness extends StatefulWidget {
  const _AutoplayHarness();

  @override
  State<_AutoplayHarness> createState() => _AutoplayHarnessState();
}

/// One scheduled autoplay item: which mode + which level id to generate.
typedef _PlanItem = ({DifficultyMode mode, int level});

class _AutoplayHarnessState extends State<_AutoplayHarness> {
  static const Duration stuckTimeout = Duration(seconds: 30);

  /// Requested run: 50 Easy + 50 Medium (the "100 mix") then 500 Hard.
  /// Level ids sweep 1..N so we exercise a wide id range, not just openers.
  static final List<_PlanItem> plan = [
    for (var i = 1; i <= 50; i++) (mode: DifficultyMode.easy, level: i),
    for (var i = 1; i <= 50; i++) (mode: DifficultyMode.medium, level: i),
    for (var i = 1; i <= 500; i++) (mode: DifficultyMode.hard, level: i),
  ];

  int _idx = 0;
  int _key = 0;
  bool _done = false;
  final Stopwatch _sw = Stopwatch();
  Timer? _watchdog;

  // Running tallies for an on-device summary line at the end.
  int _wins = 0;
  int _stuck = 0;
  final Map<String, int> _winsByMode = {};
  final Map<String, int> _stuckByMode = {};
  final Map<String, int> _msSumByMode = {};
  final Map<String, int> _msMaxByMode = {};

  _PlanItem get _cur => plan[_idx];

  @override
  void initState() {
    super.initState();
    debugPrint('AUTOPLAY|START total=${plan.length} '
        'easy=50 medium=50 hard=500 watchdogSec=${stuckTimeout.inSeconds}');
    _beginLevel();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _beginLevel() {
    _sw
      ..reset()
      ..start();
    _watchdog?.cancel();
    _watchdog = Timer(stuckTimeout, () {
      _stuck++;
      _stuckByMode[_cur.mode.name] = (_stuckByMode[_cur.mode.name] ?? 0) + 1;
      debugPrint('AUTOPLAY|STUCK i=${_idx + 1}/${plan.length} '
          'mode=${_cur.mode.name} level=${_cur.level} '
          'ms=${_sw.elapsedMilliseconds}');
      _advance();
    });
  }

  void _onWin() {
    final ms = _sw.elapsedMilliseconds;
    final m = _cur.mode.name;
    _wins++;
    _winsByMode[m] = (_winsByMode[m] ?? 0) + 1;
    _msSumByMode[m] = (_msSumByMode[m] ?? 0) + ms;
    _msMaxByMode[m] = (_msMaxByMode[m] ?? 0) > ms ? _msMaxByMode[m]! : ms;
    debugPrint('AUTOPLAY|WIN i=${_idx + 1}/${plan.length} '
        'mode=$m level=${_cur.level} ms=$ms');
    if ((_idx + 1) % 50 == 0) {
      debugPrint('AUTOPLAY|PROGRESS done=${_idx + 1}/${plan.length} '
          'wins=$_wins stuck=$_stuck');
    }
    _advance();
  }

  void _advance() {
    _watchdog?.cancel();
    if (_idx + 1 >= plan.length) {
      for (final m in const ['easy', 'medium', 'hard']) {
        final w = _winsByMode[m] ?? 0;
        final avg = w == 0 ? 0 : (_msSumByMode[m] ?? 0) ~/ w;
        debugPrint('AUTOPLAY|SUMMARY mode=$m wins=$w '
            'stuck=${_stuckByMode[m] ?? 0} avgMs=$avg maxMs=${_msMaxByMode[m] ?? 0}');
      }
      debugPrint('AUTOPLAY|ALL_DONE wins=$_wins stuck=$_stuck '
          'total=${plan.length}');
      setState(() => _done = true);
      return;
    }
    _idx++;
    _key++;
    setState(() {});
    _beginLevel();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Scaffold(
        body: Center(
          child: Text('AUTOPLAY COMPLETE',
              style: TextStyle(color: Colors.white, fontSize: 20)),
        ),
      );
    }
    return GameScreen(
      key: ValueKey('autoplay-$_key'),
      level: _cur.level,
      difficulty: _cur.mode,
      autoplay: true,
      suppressGameplayTimers: true,
      adService: NoOpAdService(),
      audioHandleFactory: SilentGameAudioHandle.new,
      onAutoplayWin: _onWin,
    );
  }
}
