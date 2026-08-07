// Снимок экрана покупки для App Store Connect.
//
// Живёт вне `test/`, поэтому обычный `flutter test` его не подхватывает.
// Запуск руками:
//
//   flutter test tool/pro_shot_test.dart --dart-define=STORE=appstore
//
// Результат — два файла в `dist/`: 1290×2796 (iPhone 6,9″) и 1242×2208
// (iPhone 5,5″). Рисуется настоящий `ProSheet` настоящей темой приложения: те же
// виджеты, те же строки, тот же цвет, что увидит человек на телефоне. Снять
// настоящий скриншот неоткуда — Mac и iPhone в хозяйстве нет, и до первой
// сборки в TestFlight этот снимок закрывает обязательное поле в консоли.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fern/l10n/locale_controller.dart';
import 'package:fern/services/pro.dart';
import 'package:fern/theme/app_theme.dart';
import 'package:fern/widgets/pro_sheet.dart';

import '../test/test_helpers.dart';

/// App Store Connect принимает не любой размер, а только те, что бывают у
/// настоящих устройств: произвольная высота отбивается ошибкой «неверные
/// размеры одного или нескольких снимков экрана». Снимаем оба ходовых.
const Map<String, Size> kShots = {
  // iPhone 6,9″ — 1290×2796.
  'appstore-review-shot': Size(430, 932),
  // iPhone 5,5″ — 1242×2208. Пропорция короче, пустоты над листом меньше.
  'appstore-review-shot-5.5': Size(414, 736),
};
const double kScale = 3;

Future<void> _loadFont(String family, String path) async {
  final data = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(data.buffer)));
  await loader.load();
}

/// Шрифт иконок. В тестовом окружении его нет, и вместо значков рисуются
/// пустые квадраты — на снимке для ревью это выглядит как сломанный экран.
/// Флаттеровский файл лежит в pub-cache любого пакета с devtools-расширением.
Future<void> _loadIcons() async {
  final matches = Directory('${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev')
      .listSync()
      .map((e) => File('${e.path}/extension/devtools/build/assets/fonts/'
          'MaterialIcons-Regular.otf'))
      .where((f) => f.existsSync());
  if (matches.isEmpty) return;
  await _loadFont('MaterialIcons', matches.first.path);
}

void main() {
  final boundary = GlobalKey();

  for (final entry in kShots.entries) {
    final name = entry.key;
    final shot = entry.value;
    testWidgets('снимок листа Fern Pro — $name', (tester) async {
    await resetStorage();
    // Без своих шрифтов тест рисует прямоугольники-заглушки вместо букв.
    await _loadFont('Unbounded', 'assets/fonts/Unbounded.ttf');
    await _loadFont('Onest', 'assets/fonts/Onest.ttf');
    await _loadFont('IBMPlexSans', 'assets/fonts/IBMPlexSans-SemiBold.ttf');
    await _loadIcons();
    await LocaleController.instance.setCode('ru');

    tester.view.physicalSize = shot * kScale;
    tester.view.devicePixelRatio = kScale;
    addTearDown(tester.view.reset);

    // Лист рисуется внутри MaterialApp с темой приложения: снаружи неё виджеты
    // берут дефолтную тему Flutter (фиолетовую) и шрифт-заглушку, и снимок
    // перестаёт быть похожим на Fern.
    final theme = AppTheme.dark(AppTheme.defaultSeed);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: RepaintBoundary(
        key: boundary,
        child: Builder(builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.surface,
            child: Stack(
              children: [
                // Затемнение — так экран выглядит с открытым нижним листом.
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: scheme.surfaceContainer,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    clipBehavior: Clip.antiAlias,
                    child: const ProSheet(feature: ProFeature.library),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    final object = boundary.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    // toImage ходит в движок — только внутри runAsync, иначе кадр не соберётся.
    final bytes = await tester.runAsync(() async {
      final image = await object.toImage(pixelRatio: kScale);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    final dir = Directory('dist')..createSync(recursive: true);
    final file = File('${dir.path}/$name.png');
    file.writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('снимок готов: ${file.absolute.path} '
        '(${(shot.width * kScale).round()}×${(shot.height * kScale).round()})');
    expect(file.lengthSync(), greaterThan(1000));
    });
  }
}
