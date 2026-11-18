// The toolbar hugs a banner below it, and keeps its full bottom padding when
// there is none (premium, offline / failed load).
import 'package:chain_pop/screens/game/widgets/game_bottom_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<double> bottomPadding(WidgetTester tester, bool hasBanner) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: GameBottomToolbar(
            measureKey: key,
            accent: Colors.cyan,
            axisGuidesVisible: false,
            canUndo: true,
            onHint: () {},
            onToggleGuides: () {},
            onResetView: () {},
            onUndo: () {},
            onRestart: () {},
            hasBanner: hasBanner,
          ),
        ),
      ),
    ));
    final padding = tester.widget<Padding>(find.byKey(key));
    return (padding.padding as EdgeInsets).bottom;
  }

  testWidgets('4 px above a banner, 12 px with no banner', (tester) async {
    expect(await bottomPadding(tester, true), 4);
    expect(await bottomPadding(tester, false), 12);
  });
}
