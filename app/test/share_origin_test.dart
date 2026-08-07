import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/utils/share_origin.dart';

/// Точка, к которой iPad прицепляет системный лист «Поделиться». Пустой
/// прямоугольник UIKit не принимает, и лист просто не появляется — с виду это
/// «кнопка не работает», а по итогам ревью Apple это отказ.
void main() {
  testWidgets('точка берётся с виджета, который позвал', (tester) async {
    late BuildContext inner;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 40,
            child: Builder(builder: (context) {
              inner = context;
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );

    final rect = shareOriginFromContext(inner);
    expect(rect.width, 100);
    expect(rect.height, 40);
    expect(rect.isEmpty, isFalse);
  });

  testWidgets('без размеров возвращается середина экрана', (tester) async {
    late BuildContext outer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          outer = context;
          return const SizedBox.shrink();
        }),
      ),
    );

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = shareOriginFromContext(outer);
    expect(rect.isEmpty, isFalse);
    expect(rect.center.dx, closeTo(size.width / 2, 1));
    expect(rect.center.dy, closeTo(size.height / 2, 1));
  });
}
