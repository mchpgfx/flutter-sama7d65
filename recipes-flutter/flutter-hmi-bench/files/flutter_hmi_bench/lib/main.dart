// Scene-based render benchmark for CPU-rasterised Flutter (no GPU).
//
// Each scene isolates ONE rendering cost so a design budget can be derived from
// measurements rather than impressions. Timings come from
// SchedulerBinding.addTimingsCallback, which reports build (UI thread) and raster
// separately: on a CPU rasteriser we expect raster-bound, and a build-bound scene
// is a different and usually fixable problem. Median and p95 are both reported,
// because a scene that is fast on average but janky is still unusable.
//
// Every scene repaints on every frame, so a figure is "cost to repaint this
// screen", which is the number that matters for animation.
//
// Output is one CSV row per scene on stdout, for capture over the serial console.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const int kWarmupFrames = 20; // discard: first paint, JIT-free AOT still has cache effects
const int kMeasureFrames = 90;
const double kBudgetMs = 33.3; // 30 fps

void main() => runApp(const BenchApp());

// ---------------------------------------------------------------- metrics

class SceneResult {
  SceneResult(this.name, this.build, this.raster, this.total);
  final String name;
  final double build, raster, total;
}

double _pct(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

// ---------------------------------------------------------------- app shell

class BenchApp extends StatefulWidget {
  const BenchApp({super.key});
  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<_Scene> _scenes;
  final List<SceneResult> _results = [];

  int _sceneIndex = 0;
  int _frames = 0;
  double _t = 0; // animation phase, seconds
  final List<double> _build = [], _raster = [], _total = [];
  ui.Image? _image;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _scenes = buildScenes();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // A ticker guarantees a frame every vsync so every scene is measured while
    // actually repainting, rather than idling.
    _ticker = createTicker((d) {
      setState(() => _t = d.inMicroseconds / 1e6);
    })..start();
    _makeImage().then((img) => setState(() => _image = img));
  }

  @override
  void dispose() {
    _ticker.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  // A procedural image, so no binary asset has to be shipped, while still
  // exercising the bitmap draw and resample paths.
  Future<ui.Image> _makeImage() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const n = 256.0;
    c.drawRect(const Rect.fromLTWH(0, 0, n, n), Paint()..color = const Color(0xFF203040));
    for (int i = 0; i < 24; i++) {
      c.drawCircle(
        Offset(((i * 37) % 240) + 8, ((i * 53) % 240) + 8),
        6 + (i % 5) * 3,
        Paint()..color = Color(0xFF000000 | (0x00308030 + i * 0x000A1503)),
      );
    }
    for (int i = 0; i < 10; i++) {
      c.drawLine(Offset(0, i * 25.6), const Offset(n, 0) + Offset(0, i * 25.6),
          Paint()..color = const Color(0x40FFFFFF)..strokeWidth = 2);
    }
    return rec.endRecording().toImage(256, 256);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_done) return;
    for (final t in timings) {
      _frames++;
      if (_frames <= kWarmupFrames) continue;
      _build.add(t.buildDuration.inMicroseconds / 1000.0);
      _raster.add(t.rasterDuration.inMicroseconds / 1000.0);
      _total.add(t.totalSpan.inMicroseconds / 1000.0);
      if (_build.length >= kMeasureFrames) {
        _finishScene();
        return;
      }
    }
  }

  void _finishScene() {
    _build.sort();
    _raster.sort();
    _total.sort();
    final name = _scenes[_sceneIndex].name;
    _results.add(SceneResult(name, _pct(_build, .5), _pct(_raster, .5), _pct(_total, .5)));

    // One CSV row per scene, emitted as it completes so a truncated run is still useful.
    _emit(name);

    _build.clear();
    _raster.clear();
    _total.clear();
    _frames = 0;

    if (_sceneIndex + 1 >= _scenes.length) {
      debugPrint('BENCH,END');
      setState(() => _done = true);
    } else {
      setState(() => _sceneIndex++);
    }
  }

  void _emit(String name) {
    String f(double v) => v.toStringAsFixed(1);
    final rMed = _pct(_raster, .5), rP95 = _pct(_raster, .95);
    final bMed = _pct(_build, .5), bP95 = _pct(_build, .95);
    final tMed = _pct(_total, .5);
    final fps = tMed > 0 ? (1000.0 / tMed) : 0.0;
    final verdict = tMed <= kBudgetMs ? 'PASS' : (tMed <= 66.6 ? 'MARGINAL' : 'FAIL');
    debugPrint('BENCH,$name,build_med=${f(bMed)},build_p95=${f(bP95)},'
        'raster_med=${f(rMed)},raster_p95=${f(rP95)},'
        'total_med=${f(tMed)},fps=${fps.toStringAsFixed(1)},$verdict');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: const Color(0xFF101418),
        body: _done
            ? _Summary(results: _results)
            : _scenes[_sceneIndex].build(_t, _image),
      ),
    );
  }

  // ------------------------------------------------------------ the scenes

  List<_Scene> buildScenes() => [
        // --- baseline -----------------------------------------------------
        _Scene('baseline.static_text', (t, img) => const _StaticText()),
        _Scene('baseline.fullscreen_fill',
            (t, img) => _Painted(painter: _FillPainter(t))),

        // --- instrument / gauges -----------------------------------------
        _Scene('gauge.face_static', (t, img) => _Painted(painter: _GaugePainter(0))),
        _Scene('gauge.needle_NO_boundary',
            (t, img) => _Painted(painter: _GaugePainter(t))),
        _Scene('gauge.needle_WITH_boundary', (t, img) => _NeedleBounded(t: t)),
        _Scene('gauge.arc_ticks_vector',
            (t, img) => _Painted(painter: _ArcTicksPainter(t))),
        _Scene('gauge.big_digits', (t, img) => _BigDigits(t: t)),
        _Scene('gauge.gradient_bezel',
            (t, img) => _Painted(painter: _GradientBezelPainter(t))),

        // --- lists / settings --------------------------------------------
        _Scene('list.text_scroll', (t, img) => _ListScroll(t: t, icons: false)),
        _Scene('list.icons_dividers_scroll',
            (t, img) => _ListScroll(t: t, icons: true)),
        _Scene('list.switches_static', (t, img) => const _Switches()),

        // --- status / monitoring -----------------------------------------
        _Scene('status.value_updates', (t, img) => _ValueUpdates(t: t)),
        _Scene('status.progress_bars', (t, img) => _ProgressBars(t: t)),

        // --- media / charts ----------------------------------------------
        _Scene('image.draw_1to1_none',
            (t, img) => _Img(img: img, scale: 1.0, q: FilterQuality.none)),
        _Scene('image.scaled_low',
            (t, img) => _Img(img: img, scale: 1.7, q: FilterQuality.low)),
        _Scene('image.scaled_medium',
            (t, img) => _Img(img: img, scale: 1.7, q: FilterQuality.medium)),
        _Scene('chart.line_static',
            (t, img) => _Painted(painter: _LineChartPainter(0))),
        _Scene('chart.waveform_scroll',
            (t, img) => _Painted(painter: _LineChartPainter(t))),

        // --- effects: quantify what to forbid ----------------------------
        _Scene('effect.box_shadow', (t, img) => _Shadows(t: t)),
        _Scene('effect.opacity_anim_saveLayer', (t, img) => _OpacityAnim(t: t)),
        _Scene('effect.clip_rrect_antialiased', (t, img) => _ClipAA(t: t)),
        _Scene('effect.alpha_blend_stack', (t, img) => _AlphaStack(t: t)),
        _Scene('effect.backdrop_blur', (t, img) => _Blur(t: t, img: img)),
      ];
}

class _Scene {
  _Scene(this.name, this._b);
  final String name;
  final Widget Function(double t, ui.Image? img) _b;
  Widget build(double t, ui.Image? img) => _b(t, img);
}

// ---------------------------------------------------------------- helpers

class _Painted extends StatelessWidget {
  const _Painted({required this.painter});
  final CustomPainter painter;
  @override
  Widget build(BuildContext _) =>
      CustomPaint(painter: painter, size: Size.infinite, child: const SizedBox.expand());
}

class _Summary extends StatelessWidget {
  const _Summary({required this.results});
  final List<SceneResult> results;
  @override
  Widget build(BuildContext _) => ListView(
        children: [
          const ListTile(title: Text('done - see serial console for CSV')),
          for (final r in results)
            ListTile(
              dense: true,
              title: Text(r.name, style: const TextStyle(fontSize: 12)),
              trailing: Text('${r.total.toStringAsFixed(1)} ms',
                  style: TextStyle(
                      fontSize: 12,
                      color: r.total <= kBudgetMs ? Colors.greenAccent : Colors.orangeAccent)),
            ),
        ],
      );
}

// ---------------------------------------------------------------- scenes

class _StaticText extends StatelessWidget {
  const _StaticText();
  @override
  Widget build(BuildContext _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Instrument Status', style: TextStyle(fontSize: 26)),
            const SizedBox(height: 8),
            for (int i = 0; i < 9; i++)
              Text('Channel ${i + 1}   nominal   24.${i}0 V   ${40 + i} C',
                  style: const TextStyle(fontSize: 15)),
          ],
        ),
      );
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final v = (math.sin(t) * 0.5 + 0.5);
    c.drawRect(Offset.zero & s,
        Paint()..color = Color.fromARGB(255, (v * 60).toInt(), 40, 70));
  }

  @override
  bool shouldRepaint(_) => true;
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = math.min(s.width, s.height) / 2 - 12;
    c.drawCircle(ctr, r, Paint()..color = const Color(0xFF1B2430));
    c.drawCircle(ctr, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 4
      ..color = const Color(0xFF4A6070));
    for (int i = 0; i <= 40; i++) {
      final a = math.pi * 0.75 + (math.pi * 1.5) * (i / 40);
      final len = (i % 5 == 0) ? 16.0 : 8.0;
      c.drawLine(ctr + Offset(math.cos(a), math.sin(a)) * (r - len),
          ctr + Offset(math.cos(a), math.sin(a)) * r,
          Paint()..strokeWidth = (i % 5 == 0) ? 3 : 1.5..color = const Color(0xFF9FB4C4));
    }
    final a = math.pi * 0.75 + (math.pi * 1.5) * (math.sin(t) * 0.5 + 0.5);
    c.drawLine(ctr, ctr + Offset(math.cos(a), math.sin(a)) * (r - 20),
        Paint()..strokeWidth = 4..color = const Color(0xFFFF5A3C));
    c.drawCircle(ctr, 7, Paint()..color = const Color(0xFFCFD8DF));
  }

  @override
  bool shouldRepaint(_) => true;
}

// Same needle, but only the needle's own box repaints. On a CPU rasteriser this
// pair is the single most instructive comparison in the suite.
class _NeedleBounded extends StatelessWidget {
  const _NeedleBounded({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Stack(
        children: [
          const RepaintBoundary(child: _StaticText()),
          Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(painter: _GaugePainter(t)),
              ),
            ),
          ),
        ],
      );
}

class _ArcTicksPainter extends CustomPainter {
  _ArcTicksPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromCenter(
        center: Offset(s.width / 2, s.height / 2),
        width: s.width - 60,
        height: s.height - 40);
    for (int k = 0; k < 5; k++) {
      c.drawArc(rect.deflate(k * 9.0), math.pi * 0.8,
          math.pi * 1.4 * (0.3 + 0.7 * (math.sin(t + k) * .5 + .5)), false,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 5
            ..color = Color(0xFF30A0FF - k * 0x00102000));
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _BigDigits extends StatelessWidget {
  const _BigDigits({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) {
    final v = (math.sin(t) * 500 + 500);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(v.toStringAsFixed(1),
            style: const TextStyle(fontSize: 96, fontFeatures: [ui.FontFeature.tabularFigures()])),
        const Text('mV', style: TextStyle(fontSize: 22)),
      ]),
    );
  }
}

class _GradientBezelPainter extends CustomPainter {
  _GradientBezelPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(s.width, s.height),
              [const Color(0xFF223344), const Color(0xFF66889A), const Color(0xFF11181F)],
              [0, (math.sin(t) * .3 + .5), 1]));
  }

  @override
  bool shouldRepaint(_) => true;
}

// Stateful so the ScrollController is created once. Building one per frame would
// leak controllers and can trip an assertion mid-run.
class _ListScroll extends StatefulWidget {
  const _ListScroll({required this.t, required this.icons});
  final double t;
  final bool icons;
  @override
  State<_ListScroll> createState() => _ListScrollState();
}

class _ListScrollState extends State<_ListScroll> {
  final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final off = (widget.t * 90) % 4000;
    // jumpTo only once attached; on the first build the viewport does not exist yet.
    if (_c.hasClients) _c.jumpTo(off);
    final icons = widget.icons;
    return ListView.builder(
      controller: _c,
      physics: const NeverScrollableScrollPhysics(),
      itemExtent: 44,
      itemCount: 200,
      itemBuilder: (_, i) => icons
          ? Column(children: [
              Expanded(
                child: Row(children: [
                  const Icon(Icons.sensors, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Sensor $i', style: const TextStyle(fontSize: 14))),
                  Text('${(i * 7) % 100} %', style: const TextStyle(fontSize: 14)),
                ]),
              ),
              const Divider(height: 1),
            ])
          : Align(
              alignment: Alignment.centerLeft,
              child: Text('Log entry $i  -  measurement complete',
                  style: const TextStyle(fontSize: 14))),
    );
  }
}

class _Switches extends StatelessWidget {
  const _Switches();
  @override
  Widget build(BuildContext _) => ListView(
        children: [
          for (int i = 0; i < 9; i++)
            SwitchListTile(
                dense: true,
                value: i.isEven,
                onChanged: (_) {},
                title: Text('Option $i', style: const TextStyle(fontSize: 14))),
        ],
      );
}

class _ValueUpdates extends StatelessWidget {
  const _ValueUpdates({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Stack(children: [
        const RepaintBoundary(child: _StaticText()),
        Positioned(
          right: 16,
          top: 16,
          child: RepaintBoundary(
            child: Text((math.sin(t) * 100).toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 40, fontFeatures: [ui.FontFeature.tabularFigures()])),
          ),
        ),
      ]);
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (int i = 0; i < 7; i++) ...[
            LinearProgressIndicator(value: (math.sin(t + i) * .5 + .5)),
            const SizedBox(height: 14),
          ]
        ]),
      );
}

class _Img extends StatelessWidget {
  const _Img({required this.img, required this.scale, required this.q});
  final ui.Image? img;
  final double scale;
  final FilterQuality q;
  @override
  Widget build(BuildContext _) => img == null
      ? const SizedBox()
      : _Painted(painter: _ImgPainter(img!, scale, q));
}

class _ImgPainter extends CustomPainter {
  _ImgPainter(this.img, this.scale, this.q);
  final ui.Image img;
  final double scale;
  final FilterQuality q;
  @override
  void paint(Canvas c, Size s) {
    final w = 256.0 * scale, h = 256.0 * scale;
    final dst = Rect.fromCenter(
        center: Offset(s.width / 2, s.height / 2), width: w, height: h);
    c.drawImageRect(img, const Rect.fromLTWH(0, 0, 256, 256), dst,
        Paint()..filterQuality = q);
  }

  @override
  bool shouldRepaint(_) => true;
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final grid = Paint()..color = const Color(0xFF2A3540)..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 40) {
      c.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 0; y < s.height; y += 40) {
      c.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    for (int series = 0; series < 3; series++) {
      final p = Path();
      for (double x = 0; x <= s.width; x += 3) {
        final y = s.height / 2 +
            math.sin((x / 46) + t * 2 + series) * (s.height / 4 - series * 14);
        if (x == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      c.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = [
              const Color(0xFF4FC3F7),
              const Color(0xFFFFB74D),
              const Color(0xFF81C784)
            ][series]);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _Shadows extends StatelessWidget {
  const _Shadows({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Center(
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (int i = 0; i < 8; i++)
              Container(
                width: 150,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF25313D),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 10 + 6 * (math.sin(t + i) * .5 + .5),
                        offset: const Offset(0, 4)),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _OpacityAnim extends StatelessWidget {
  const _OpacityAnim({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Center(
        // Opacity forces saveLayer: an offscreen buffer plus a composite.
        child: Opacity(
          opacity: 0.15 + 0.85 * (math.sin(t) * .5 + .5),
          child: const _StaticText(),
        ),
      );
}

class _ClipAA extends StatelessWidget {
  const _ClipAA({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (int i = 0; i < 6; i++)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: Container(
                  width: 170,
                  height: 100,
                  color: Color(0xFF30506A + (i * 0x00050A05)),
                  child: Center(child: Text('clip $i')),
                ),
              ),
          ],
        ),
      );
}

// Stacked translucency: the case reported as sluggish on hardware.
class _AlphaStack extends StatelessWidget {
  const _AlphaStack({required this.t});
  final double t;
  @override
  Widget build(BuildContext _) => Stack(
        children: [
          _Painted(painter: _GradientBezelPainter(t)),
          for (int i = 0; i < 6; i++)
            Positioned(
              left: 20.0 + i * 110 + math.sin(t + i) * 16,
              top: 60.0 + (i % 3) * 110,
              child: Container(
                width: 220,
                height: 150,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
        ],
      );
}

class _Blur extends StatelessWidget {
  const _Blur({required this.t, required this.img});
  final double t;
  final ui.Image? img;
  @override
  Widget build(BuildContext _) => Stack(children: [
        _Painted(painter: _LineChartPainter(t)),
        Center(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                width: 400,
                height: 240,
                color: Colors.black.withValues(alpha: 0.2),
                child: const Center(child: Text('BackdropFilter')),
              ),
            ),
          ),
        ),
      ]);
}
