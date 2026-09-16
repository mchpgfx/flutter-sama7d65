import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo_menu/main.dart';

void main() {
  // Panels this one image is meant to serve.
  const cases = <String, Size>{
    '800x480  (current ST7262 LVDS)': Size(800, 480),
    '1280x800 (NVD LVDS)': Size(1280, 800),
    '1024x600': Size(1024, 600),
    '480x272  (small, forces the stacked layout)': Size(480, 272),
    '2048x2048 (XLCDC maximum)': Size(2048, 2048),
    '480x800  (portrait, forces the stacked layout)': Size(480, 800),
    '600x1024 (portrait)': Size(600, 1024),
  };

  cases.forEach((label, size) {
    testWidgets('renders with no overflow at $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MenuApp());
      await tester.pumpAndSettle();

      // A RenderFlex overflow is reported as an exception, not a silent clip.
      expect(tester.takeException(), isNull, reason: 'overflow at $label');

      // Both choices must still be reachable at every size.
      expect(find.text('Flutter Gallery'), findsOneWidget);
      expect(find.text('Material 3 Demo'), findsOneWidget);
      expect(find.byType(FlutterLogo), findsOneWidget);
    });
  });

  testWidgets('reports the live resolution, not a hardcoded one', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MenuApp());
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(find.textContaining('Skia CPU')).data!;
    expect(status, contains('1280x800'));
    expect(status, isNot(contains('800x480')));
    // Whatever the host reports, the SIMD field must be filled in from procfs.
    expect(status, matches(RegExp(r'(NEON\+VFPv4|NEON|no NEON|NEON unknown)')));
    // ignore: avoid_print
    print('  status line at 1280x800: "$status"');
  });
}
