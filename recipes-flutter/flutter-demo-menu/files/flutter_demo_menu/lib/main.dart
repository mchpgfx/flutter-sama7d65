// Demo selector for the SAMA7D65 Curiosity.
//
// ivi-homescreen runs ONE bundle per process, so this menu cannot switch demos
// itself. It writes the chosen bundle path to a file and exits; the supervisor
// script (flutter-demo-launcher) reads it and starts that bundle. The USER button
// on PC10 terminates the demo and the supervisor loops back here.
//
// Styling deliberately follows this project's own measured guidelines: flat opaque
// fills, no gradients, no BoxShadow, no antialiased clipping, no Opacity animation.
// A static screen like this costs almost nothing, and there is no reason to spend it.

import 'dart:io';
import 'package:flutter/material.dart';

/// Where the supervisor looks for the selection. /run is tmpfs.
const String kChoiceFile = '/run/demo-choice';

const String kGalleryBundle =
    '/usr/share/flutter/flutter-sdk-dev-integration-tests-flutter-gallery/3.47.4/release';
const String kMaterial3Bundle =
    '/usr/share/flutter/flutter-samples-material-3-demo/3.47.4/release';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Opaque: lets Skia skip blending for the whole screen.
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            children: [
              Row(
                children: [
                  // Built into Flutter - no asset to ship, and it is the mark of
                  // authorship the brief asked for.
                  const FlutterLogo(size: 46),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Flutter on SAMA7D65',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600)),
                      Text('Skia CPU renderer · 800×480 · no GPU',
                          style: TextStyle(fontSize: 12, color: Color(0xFF8A98A6))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _DemoTile(
                        title: 'Flutter Gallery',
                        subtitle: 'Broad Material widget showcase.\n'
                            'Heavy: elevation, transitions, ripples.',
                        accent: Color(0xFF4FC3F7),
                        onTap: () => _select(kGalleryBundle),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _DemoTile(
                        title: 'Material 3 Demo',
                        subtitle: 'Dense controls, icons, typography.\n'
                            'Better suited to this hardware.',
                        accent: Color(0xFF81C784),
                        onTap: () => _select(kMaterial3Bundle),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text('Press the USER button (PC10) to return to this menu',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A98A6))),
            ],
          ),
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color accent;
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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w600, color: accent)),
            const SizedBox(height: 12),
            Text(subtitle,
                style: const TextStyle(fontSize: 14, height: 1.4)),
            const Spacer(),
            Text('TAP TO RUN',
                style: TextStyle(
                    fontSize: 13, letterSpacing: 1.5, color: accent)),
          ],
        ),
      ),
    );
  }
}
