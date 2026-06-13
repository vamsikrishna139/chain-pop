import 'package:chain_pop/screens/game/widgets/phase_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PhaseProgressBar renders segmented clearance', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhaseProgressBar(removedNodes: 2, totalNodes: 4),
        ),
      ),
    );

    expect(find.byType(PhaseProgressBar), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PhaseProgressBar)),
      matchesSemantics(label: '2 of 4 nodes cleared'),
    );
  });
}
