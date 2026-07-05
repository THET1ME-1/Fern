import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/study/tappable_text.dart';

void main() {
  testWidgets('long-press + протяжка выделяет фразу и зовёт onPhrase',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(2000, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? phrase;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TappableText(
          text: 'The quick brown fox jumps',
          style: const TextStyle(fontSize: 20),
          known: const {},
          sessionAdded: const {},
          highlightVersion: 0,
          knownColor: Colors.green,
          addedColor: Colors.orange,
          onWord: (_) {},
          onPhrase: (p) => phrase = p,
        ),
      ),
    ));
    await tester.pump();

    final rect = tester.getRect(find.byType(RichText));
    // Long-press у левого края → протяжка вправо → отпускание.
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(6, 0),
    );
    await tester.pump(const Duration(milliseconds: 700)); // порог long-press
    await gesture.moveTo(rect.center);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(phrase, isNotNull);
    expect(phrase!.trim().isNotEmpty, isTrue);
    // Выделение началось от первого слова.
    expect(phrase!.toLowerCase().startsWith('the'), isTrue);
  });
}
