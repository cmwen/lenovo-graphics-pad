import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lenovo_graphics_pad/main.dart';

void main() {
  testWidgets('shows transport status and pointer diagnostics', (tester) async {
    await tester.pumpWidget(const LenovoGraphicsPadApp());

    expect(
      find.text(
        'Local preview only. No tablet or host is connected, and USB/Bluetooth transport is not implemented.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not implemented'), findsOneWidget);
    expect(find.text('Pointer tool: No input yet'), findsOneWidget);

    final canvas = find.byKey(const ValueKey('preview-canvas'));
    await tester.drag(canvas, const Offset(100, 80));
    await tester.pumpAndSettle();

    expect(find.text('Pointer tool: touch'), findsOneWidget);
    expect(find.text('Tip: up'), findsOneWidget);
    expect(find.textContaining('Normalized position:'), findsOneWidget);
    expect(find.textContaining('Flutter-reported pressure:'), findsOneWidget);
  });
}
