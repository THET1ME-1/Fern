import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/strings.dart';
import 'package:fern/models/fsrs.dart';
import 'package:fern/services/fsrs_optimizer.dart';
import 'package:fern/widgets/optimize_info_sheet.dart';

/// Лист объясняет кнопку сроками, а не весами: человек должен увидеть, через
/// сколько дней вернётся новое слово, и чем его расписание отличается от
/// общего.
Widget _host(Widget sheet) => MaterialApp(
      home: Scaffold(body: sheet),
    );

void main() {
  testWidgets('без личных весов показывает общие сроки', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(OptimizeInfoSheet(
      data: const FsrsReadiness(total: 387, pairs: 7),
      personal: null,
      retention: 0.9,
    )));
    await tester.pumpAndSettle();

    expect(find.text(tr('opt_info_title')), findsOneWidget);
    // «Хорошо» на стандартных весах — три дня.
    expect(find.text(trn('n_days', 3)), findsOneWidget);
    // Столбцов сравнения нет, пока подгонки не было.
    expect(find.text(tr('opt_info_col_you')), findsNothing);
    // Состояние сбора данных — то самое, что мешает нажать кнопку.
    expect(find.text(trf('optimize_pairs', {'n': 7, 'need': 20})),
        findsOneWidget);
  });

  testWidgets('с личными весами показывает два столбца', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final personal = List<double>.of(Fsrs.defaultWeights)..[2] = 7.0;
    await tester.pumpWidget(_host(OptimizeInfoSheet(
      data: const FsrsReadiness(total: 900, pairs: 40),
      personal: personal,
      retention: 0.9,
    )));
    await tester.pumpAndSettle();

    expect(find.text(tr('opt_info_col_avg')), findsOneWidget);
    expect(find.text(tr('opt_info_col_you')), findsOneWidget);
    // Общий срок «Хорошо» — 3 дня, личный — 7.
    expect(find.text(trn('n_days', 3)), findsOneWidget);
    expect(find.text(trn('n_days', 7)), findsOneWidget);
    expect(find.text(tr('optimize_active')), findsOneWidget);
  });
}
