import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/l10n/strings.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/services/source_library.dart';
import 'package:fern/video/subtitle.dart';
import 'package:fern/video/video_screen.dart';

import 'test_helpers.dart';

/// Фейковый path_provider — SourceLibrary пишет/читает транскрипт в temp-папку.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

VideoTranscript _transcript() => const VideoTranscript(
      videoId: 'abc123',
      url: 'https://youtu.be/abc123',
      title: 'Тестовое видео',
      langCode: 'en',
      wordTimed: false,
      lines: [
        SubLine(
          start: Duration.zero,
          end: Duration(seconds: 2),
          text: 'The cat and the dog.',
        ),
        SubLine(
          start: Duration(seconds: 2),
          end: Duration(seconds: 4),
          text: 'The cat runs and jumps over lazy foxes.',
        ),
      ],
    );

void main() {
  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  testWidgets('Страница видео: анализ субтитров и кнопка разбора',
      (WidgetTester tester) async {
    final tmp = Directory.systemTemp.createTempSync('fern_video');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() => tmp.deleteSync(recursive: true));

    // Высокий вьюпорт — иначе ленивый ListView не строит карточки ниже сгиба
    // (превью 16:9 занимает пол-экрана), и анализ «не находится».
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Одно известное слово → в анализе будут все три группы.
    await DeckRepository.instance.upsertDeck(Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'EN',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    ));
    await DeckRepository.instance.upsertCard(
      WordCard(id: 'c1', deckId: 'd1', front: 'the', back: 'арт'),
    );

    await tester.runAsync(() async {
      final id = await SourceLibrary.instance.saveVideo(_transcript());
      final src = (await SourceLibrary.instance.get(id!))!;
      expect(src.isVideo, true);
      expect(src.languageCode, 'en');
      final round = await SourceLibrary.instance.loadVideo(id);
      expect(round, isNotNull, reason: 'транскрипт не прочитался');
      expect(round!.lines.length, 2);
      await tester.pumpWidget(MaterialApp(home: VideoScreen(source: src)));
      // Дать завершиться чтению транскрипта + пересчёту анализа.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 900)); // добежать анимациям
    });

    expect(tester.takeException(), isNull);
    // Кнопка «Смотреть и учить» и все три группы анализа на месте.
    expect(find.text(tr('video_open_study')), findsOneWidget);
    expect(find.text(tr('analysis_known')), findsOneWidget);
    expect(find.text(tr('analysis_learning')), findsOneWidget);
    expect(find.text(tr('analysis_unknown')), findsOneWidget);
    // Карточка проверки языка показана.
    expect(find.text(tr('lang_check_title')), findsOneWidget);
  });
}
