// Экраны на узком телефоне и с крупным системным шрифтом: вёрстка не должна
// переполняться.
//
// Так нашлись пять очагов сразу: плитки режимов на экране колоды, карточки
// входов в Библиотеке, обложки колод на главном и в паке, кнопки под полем
// разбора, тройка мини-счётчиков колоды. Все они подтекали жёлто-чёрной лентой
// на 320 dp и при системном шрифте 1.3 — то есть у части людей постоянно.
//
// Шрифты грузятся настоящие: у Unbounded строка заметно выше кегля, и на
// подменном шрифте тестовой среды половина переполнений не воспроизводится, а
// половина выдумывается.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/decks_screen.dart';
import 'package:fern/deck_screen.dart';
import 'package:fern/grammar_screen.dart';
import 'package:fern/library_screen.dart';
import 'package:fern/models/deck.dart';
import 'package:fern/models/word_card.dart';
import 'package:fern/progress_screen.dart';
import 'package:fern/settings_screen.dart';
import 'package:fern/analyze/analyze_screen.dart';
import 'package:fern/analyze/reply_screen.dart';
import 'package:fern/achievements_screen.dart';
import 'package:fern/models/pack.dart';
import 'package:fern/pack_screen.dart';
import 'package:fern/study/results_screen.dart';
import 'package:fern/study/session_screen.dart';
import 'package:fern/study/study_models.dart';
import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/deck_repository.dart';
import 'package:fern/theme/app_theme.dart';
import 'package:fern/services/pro.dart';
import 'package:fern/widgets/color_picker_sheet.dart';
import 'package:fern/widgets/deck_editor_sheet.dart';
import 'package:fern/widgets/hook_editor_sheet.dart';
import 'package:fern/widgets/language_editor_sheet.dart';
import 'package:fern/widgets/pack_editor_sheet.dart';
import 'package:fern/widgets/pro_sheet.dart';

import 'test_helpers.dart';

final _found = <String>[];

Future<void> _probe(
  WidgetTester tester,
  String label,
  Widget screen, {
  required Size size,
  required double scale,
  String locale = 'ru',
}) async {
  await LocaleController.instance.setCode(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    final full = details.toString();
    final where = RegExp(r'(file:///[^\s)]+\.dart:\d+:\d+)').firstMatch(full);
    final head = text.split('\n').first;
    errors.add('$head  <<< ${where?.group(1) ?? 'место не указано'}');
  };
  try {
    await tester.pumpWidget(MaterialApp(
      key: ValueKey('$label$size$scale$locale'),
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
        ),
        child: screen,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  } catch (e) {
    errors.add('ПАДЕНИЕ: $e');
  } finally {
    FlutterError.onError = prev;
  }
  for (final e in errors.toSet()) {
    _found.add('[$label ${size.width.toInt()}x${size.height.toInt()} '
        'x$scale $locale] $e');
  }
}

Future<Deck> _seedDeck() async {
  final repo = DeckRepository.instance;
  final deck = Deck(
    id: 'd1',
    languageCode: 'en',
    name: 'Первые слова',
    colorValue: 0xFF2E7D5B,
    shapeIndex: 0,
    createdAt: 1,
  );
  await repo.upsertDeck(deck);
  for (var i = 0; i < 8; i++) {
    await repo.upsertCard(WordCard(
      id: 'c$i',
      deckId: 'd1',
      front: 'word$i',
      back: 'слово$i',
    ));
  }
  return deck;
}

Future<void> _loadFonts() async {
  const files = {
    'Unbounded': ['assets/fonts/Unbounded.ttf'],
    'Onest': ['assets/fonts/Onest.ttf'],
    'IBMPlexSans': [
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
      'assets/fonts/IBMPlexSans-Bold.ttf',
    ],
  };
  for (final e in files.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      loader.addFont(
          File(path).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }
}

Future<void> _probeSheet(
  WidgetTester tester,
  String label,
  Future<void> Function(BuildContext context) open, {
  required Size size,
  required double scale,
  String locale = 'ru',
}) async {
  await LocaleController.instance.setCode(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    final where = RegExp(r'(file:///[^\s)]+\.dart:\d+:\d+)')
        .firstMatch(details.toString());
    errors.add('${text.split('\n').first}  <<< '
        '${where?.group(1) ?? 'место не указано'}');
  };
  try {
    await tester.pumpWidget(MaterialApp(
      key: ValueKey('$label$size$scale$locale'),
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('открыть'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  } catch (e) {
    errors.add('ПАДЕНИЕ: $e');
  } finally {
    FlutterError.onError = prev;
  }
  for (final e in errors.toSet()) {
    _found.add('[$label ${size.width.toInt()}x${size.height.toInt()} '
        'x$scale $locale] $e');
  }
}

void main() {
  setUpAll(_loadFonts);

  setUp(() async {
    await resetStorage();
    await DeckRepository.instance.init();
    await LocaleController.instance.setCode('ru');
  });

  tearDown(() {
    expect(_found, isEmpty, reason: _found.join('\n'));
    _found.clear();
  });

  const sizes = [Size(320, 640), Size(360, 740), Size(411, 914)];
  const scales = [1.0, 1.3];
  // Немецкий и португальский — самые длинные подписи из семи языков.
  const langs = ['de', 'pt'];

  testWidgets('колоды', (t) async {
    await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Колоды', const DecksScreen(), size: s, scale: sc);
      }
    }
  });

  testWidgets('экран колоды', (t) async {
    final deck = await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Колода', DeckScreen(deck: deck), size: s, scale: sc);
      }
    }
    // немецкий: подписи режимов длиннее русских
    await _probe(t, 'Колода', DeckScreen(deck: deck),
        size: const Size(360, 740), scale: 1.0, locale: 'de');
  });

  testWidgets('библиотека', (t) async {
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Библиотека', const LibraryScreen(),
            size: s, scale: sc);
      }
    }
    await _probe(t, 'Библиотека', const LibraryScreen(),
        size: const Size(360, 740), scale: 1.0, locale: 'de');
  });

  testWidgets('прогресс', (t) async {
    await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Прогресс', const ProgressScreen(), size: s, scale: sc);
      }
    }
  });

  testWidgets('настройки', (t) async {
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Настройки', const SettingsScreen(), size: s, scale: sc);
      }
    }
  });

  testWidgets('грамматика', (t) async {
    await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Грамматика', const GrammarScreen(languageCode: 'en'), size: s, scale: sc);
      }
    }
  });

  testWidgets('сессия во всех режимах', (t) async {
    final deck = await _seedDeck();
    final cards = await DeckRepository.instance.loadCards();
    const modes = [
      StudyMode.learn,
      StudyMode.flashcards,
      StudyMode.test,
      StudyMode.write,
      StudyMode.spell,
      StudyMode.assemble,
      StudyMode.audio,
      StudyMode.speed,
      StudyMode.cloze,
      StudyMode.associations,
      StudyMode.cram,
      StudyMode.twins,
    ];
    for (final m in modes) {
      for (final s in [const Size(320, 640), const Size(360, 740)]) {
        for (final sc in [1.0, 1.3]) {
          await _probe(t, 'Сессия ${m.name}',
              SessionScreen(deck: deck, mode: m, cards: cards),
              size: s, scale: sc);
        }
      }
    }
  });

  testWidgets('результаты', (t) async {
    await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(
            t,
            'Результаты',
            const ResultsScreen(
                result: SessionResult(14, 11, Duration(minutes: 3, seconds: 20))),
            size: s,
            scale: sc);
      }
    }
  });

  testWidgets('достижения', (t) async {
    await _seedDeck();
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Достижения', const AchievementsScreen(),
            size: s, scale: sc);
      }
    }
  });

  testWidgets('пак', (t) async {
    await _seedDeck();
    final pack = Pack(
        id: 'p1',
        name: 'Английский на лето',
        languageCode: 'en',
        colorValue: 0xFF2E7D5B,
        createdAt: 1);
    await DeckRepository.instance.upsertPack(pack);
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Пак', PackScreen(pack: pack), size: s, scale: sc);
      }
    }
  });

  testWidgets('ответ', (t) async {
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Ответ', const ReplyScreen(), size: s, scale: sc);
      }
    }
  });

  testWidgets('разбор текста', (t) async {
    for (final s in sizes) {
      for (final sc in scales) {
        await _probe(t, 'Разбор', const AnalyzeScreen(), size: s, scale: sc);
      }
    }
  });

  testWidgets('длинные языки на узком экране', (t) async {
    final deck = await _seedDeck();
    final cards = await DeckRepository.instance.loadCards();
    for (final l in langs) {
      for (final s in [const Size(320, 640), const Size(360, 740)]) {
        await _probe(t, 'Колоды', const DecksScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Колода', DeckScreen(deck: deck),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Библиотека', const LibraryScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Прогресс', const ProgressScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Настройки', const SettingsScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Разбор', const AnalyzeScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Достижения', const AchievementsScreen(),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Результаты',
            const ResultsScreen(
                result: SessionResult(9, 7, Duration(minutes: 2))),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Сессия',
            SessionScreen(
                deck: deck, mode: StudyMode.flashcards, cards: cards),
            size: s, scale: 1.0, locale: l);
        await _probe(t, 'Сессия выбор',
            SessionScreen(deck: deck, mode: StudyMode.test, cards: cards),
            size: s, scale: 1.0, locale: l);
      }
    }
  });

  // ------------------------------- Нижние листы -------------------------------

  const sheetCases = [
    (Size(320, 640), 1.0, 'ru'),
    (Size(320, 640), 1.3, 'ru'),
    (Size(360, 740), 1.0, 'de'),
  ];

  testWidgets('редактор колоды', (t) async {
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Редактор колоды',
        (ctx) => showDeckEditor(ctx, languageCode: 'en'),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('редактор пака', (t) async {
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Редактор пака',
        (ctx) => showPackEditor(ctx, languageCode: 'en'),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('выбор цвета', (t) async {
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Выбор цвета',
        (ctx) => showColorPickerSheet(ctx, initial: AppTheme.defaultSeed),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('редактор языка', (t) async {
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Редактор языка',
        (ctx) => showLanguageEditor(ctx),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('крючок к слову', (t) async {
    final card = WordCard(id: 'c1', deckId: 'd1', front: 'word', back: 'слово');
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Крючок',
        (ctx) => showHookEditor(ctx, card),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('лист Pro', (t) async {
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Pro',
        (ctx) => ProSheet.show(ctx, feature: ProFeature.library),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });

  testWidgets('редактор колоды с данными', (t) async {
    final deck = Deck(
      id: 'd1',
      languageCode: 'en',
      name: 'Очень длинное название колоды для проверки',
      colorValue: 0xFF2E7D5B,
      shapeIndex: 0,
      createdAt: 1,
    );
    await DeckRepository.instance.upsertDeck(deck);
    for (final c in sheetCases) {
      await _probeSheet(
        t,
        'Редактор колоды (данные)',
        (ctx) => showDeckEditor(ctx, existing: deck, languageCode: 'en'),
        size: c.$1,
        scale: c.$2,
        locale: c.$3,
      );
    }
  });
}
