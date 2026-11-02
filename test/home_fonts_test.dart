// A text button given its own `textStyle` replaces the theme's whole style, family included, so its label fell back to
// the platform font ("See all" on Home drew in Roboto while everything around it was Geist). Every text button on Home
// must be set in the app's font.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/ui/home_shell.dart';

import 'golden/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Home\'s "See all" and "Browse projects" are set in Geist', (tester) async {
    FakeHost();
    await pumpLook(tester, const Look(), HomeShell(agent: newAgent()), height: 1600);
    await tester.pump(const Duration(milliseconds: 600));
    for (final label in ['See all', 'Browse projects']) {
      final finder = find.descendant(of: find.widgetWithText(TextButton, label), matching: find.text(label));
      if (finder.evaluate().isEmpty) continue; // not on this layout
      final family = tester.widget<RichText>(find.descendant(of: finder.first, matching: find.byType(RichText))).text.style?.fontFamily;
      expect(family, anyOf('Geist', 'packages/rynex/Geist'), reason: label);
    }
    expect(find.widgetWithText(TextButton, 'See all'), findsOneWidget);
  });
}
