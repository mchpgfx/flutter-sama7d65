// Demo selector for the SAMA7D65 Curiosity.
//
// ivi-homescreen runs ONE bundle per process, so this menu cannot switch demos
// itself. It writes the chosen bundle path to a file and exits; the supervisor
// script (flutter-demo-launcher) reads it and starts that bundle. The USER button
// on PC10 terminates the demo and the supervisor loops back here.
//
// NOTHING about the display is hardcoded. An earlier version printed a fixed
// "800x480" string, which would have kept saying 800x480 on a 1280x800 panel and
// quietly misreported the platform. Resolution, refresh rate and the NEON flag are
// all read at runtime, and the layout scales, so one image serves any panel the
// bootargs bring up. The XLCDC allows up to 2048x2048 (atmel_hlcdc_dc.c:
// atmel_xlcdc_dc_sama7d65), so the display controller is not the limit.
//
// Styling deliberately follows this project's own measured guidelines: flat opaque
// fills, no gradients, no BoxShadow, no antialiased clipping, no Opacity animation.
// A static screen like this costs almost nothing, and there is no reason to spend it.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Where the supervisor looks for the selection. /run is tmpfs.
const String kChoiceFile = '/run/demo-choice';

const String kGalleryBundle =
    '/usr/share/flutter/flutter-sdk-dev-integration-tests-flutter-gallery/3.47.4/release';
const String kMaterial3Bundle =
    '/usr/share/flutter/flutter-samples-material-3-demo/3.47.4/release';

/// The layout was authored against this; everything scales from the ratio to it.
const Size kDesignSize = Size(800, 480);

/// SIMD state, read once from the kernel rather than asserted.
///
/// This reports what the CPU advertises, which is the honest thing a screen can
/// claim. It is not proof that any particular library was compiled to use it -
/// that comes from the toolchain (this image builds -mfpu=neon-vfpv4 via the
/// cortexa7hf-neon-vfpv4 tune) and, for the hot path here, from Skia's own
/// runtime dispatch plus the hand-written NEON in ivi-homescreen's pixel_swizzle.h.
final String kSimd = _detectSimd();

String _detectSimd() {
  try {
    for (final line in File('/proc/cpuinfo').readAsLinesSync()) {
      if (!line.startsWith('Features')) continue;
      final flags = line.split(':').last.trim().split(RegExp(r'\s+'));
      // 'neon' on 32-bit ARM; 'asimd' is the AArch64 spelling of the same unit.
      if (flags.contains('neon') || flags.contains('asimd')) {
        return flags.contains('vfpv4') ? 'NEON+VFPv4' : 'NEON';
      }
      return 'no NEON';
    }
  } catch (_) {
    // procfs unreadable: say so rather than claiming either way.
  }
  return 'NEON unknown';
}

void main() => runApp(const MenuApp());

class MenuApp extends StatelessWidget {
  const MenuApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: const MenuScreen(),
      );
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  void _select(String bundle) {
    try {
      File(kChoiceFile).writeAsStringSync('$bundle\n', flush: true);
    } catch (e) {
      // Nothing useful to do on the panel; the supervisor will simply re-show the
      // menu. Print so it lands in the journal.
      stderr.writeln('flutter_demo_menu: could not write $kChoiceFile: $e');
      return;
    }
    // The supervisor watches for the file and terminates this process, so exiting
    // here is belt-and-braces rather than the mechanism.
    exit(0);
  }

  /// "1280x800 @ 52.6 Hz" from the live view, falling back gracefully.
  String _describeDisplay(BuildContext context) {
    final view = View.of(context);
    final px = view.physicalSize;
    final res = '${px.width.round()}x${px.height.round()}';

    // FlutterView.display resolves through a nullable map on the platform
    // dispatcher. The software embedder is new and may not register a Display, in
    // which case this throws rather than returning null - so the resolution (which
    // is always available) is never made to depend on the refresh rate.
    String hz = '';
    try {
      final ui.Display d = view.display;
      if (d.refreshRate > 0) hz = ' @ ${d.refreshRate.toStringAsFixed(1)} Hz';
    } catch (_) {}

    return '$res$hz';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Opaque: lets Skia skip blending for the whole screen.
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // One scale factor for the whole screen, from whichever axis is
            // tighter, so a 1280x800 panel gets proportionally larger text and a
            // small panel stays legible instead of overflowing.
            // clamp() returns num, so .toDouble() is required before any of these
            // values reach a double parameter.
            final double s = math
                .min(constraints.maxWidth / kDesignSize.width,
                    constraints.maxHeight / kDesignSize.height)
                .clamp(0.65, 2.2)
                .toDouble();

            // Stack only on a PORTRAIT panel. Keying this off a small width was
            // wrong: stacking doubles the height the tiles need, so on a short
            // landscape panel (480x272) it overflowed - the widget test caught it.
            // When height is the scarce axis, side by side is the fit that works.
            final stack = constraints.maxWidth < constraints.maxHeight;

            final tiles = <Widget>[
              Expanded(
                child: _DemoTile(
                  title: 'Flutter Gallery',
                  subtitle: 'Broad Material widget showcase.\n'
                      'Heavy: elevation, transitions, ripples.',
                  accent: const Color(0xFF4FC3F7),
                  scale: s,
                  onTap: () => _select(kGalleryBundle),
                ),
              ),
              SizedBox(
                  width: stack ? 0.0 : 18 * s,
                  height: stack ? 14 * s : 0.0),
              Expanded(
                child: _DemoTile(
                  title: 'Material 3 Demo',
                  subtitle: 'Dense controls, icons, typography.\n'
                      'Better suited to this hardware.',
                  accent: const Color(0xFF81C784),
                  scale: s,
                  onTap: () => _select(kMaterial3Bundle),
                ),
              ),
            ];

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 14 * s),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Built into Flutter - no asset to ship, and it is the mark
                      // of authorship the brief asked for.
                      FlutterLogo(size: 46 * s),
                      SizedBox(width: 14 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Flutter on SAMA7D65',
                                style: TextStyle(
                                    fontSize: 22 * s,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                'Skia CPU · ${_describeDisplay(context)} · '
                                '$kSimd · no GPU',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12 * s,
                                    color: const Color(0xFF8A98A6))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * s),
                  Expanded(
                    child: stack
                        ? Column(children: tiles)
                        : Row(children: tiles),
                  ),
                  SizedBox(height: 10 * s),
                  Text('Press the USER button (PC10) to return to this menu',
                      style: TextStyle(
                          fontSize: 13 * s, color: const Color(0xFF8A98A6))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A large flat touch target. Deliberately not ElevatedButton/Card: those draw a
/// BoxShadow, measured at 43 ms for eight of them.
class _DemoTile extends StatelessWidget {
  const _DemoTile({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.scale,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Opaque so the whole tile is a hit target, not just its painted pixels.
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B2430),
          // Square corners: a rounded clip with antialiasing costs a saveLayer.
          border: Border.all(color: accent, width: 2),
        ),
        padding: EdgeInsets.all(18 * scale),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 26 * scale,
                    fontWeight: FontWeight.w600,
                    color: accent)),
            SizedBox(height: 12 * scale),
            Text(subtitle,
                style: TextStyle(fontSize: 14 * scale, height: 1.4)),
            const Spacer(),
            Text('TAP TO RUN',
                style: TextStyle(
                    fontSize: 13 * scale, letterSpacing: 1.5, color: accent)),
          ],
        ),
      ),
    );
  }
}
