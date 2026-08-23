import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/translation/endpoint_provider.dart';
import 'package:fern/services/translation/translation_manager.dart';
import 'package:fern/services/translation_service.dart';
import 'package:fern/services/translation/translation_provider.dart';

/// Звено, которое молчит навсегда: так вёл себя ML Kit, пока ждал загрузку
/// языковой модели на мобильном интернете.
class _SilentProvider extends TranslationProvider {
  @override
  String get id => 'silent';
  @override
  String get name => 'Silent';
  @override
  bool get isOffline => true;
  @override
  String get kindLabel => 'offline';
  @override
  Future<bool> isReady(String from, String to) async => true;
  @override
  Future<TransResult?> translate(String text, String from, String to,
          {String? context}) =>
      Completer<TransResult?>().future; // никогда не завершится
}

/// Звено, которое честно признаётся, что не смогло.
class _FailingProvider extends TranslationProvider {
  @override
  String get id => 'failing';
  @override
  String get name => 'Failing';
  @override
  bool get isOffline => true;
  @override
  String get kindLabel => 'offline';
  @override
  Future<bool> isReady(String from, String to) async => true;
  @override
  Future<TransResult?> translate(String text, String from, String to,
          {String? context}) async =>
      null;
}

class _OkProvider extends TranslationProvider {
  @override
  String get id => 'ok';
  @override
  String get name => 'Ok';
  @override
  bool get isOffline => false;
  @override
  String get kindLabel => 'online';
  @override
  Future<bool> isReady(String from, String to) async => true;
  @override
  Future<TransResult?> translate(String text, String from, String to,
          {String? context}) async =>
      TransResult(primary: 'книга', sourceId: id);
}

void main() {
  final mgr = TranslationManager.instance;

  setUp(() {
    TranslationManager.linkTimeout = const Duration(milliseconds: 50);
  });

  tearDown(() {
    TranslationManager.linkTimeout = null;
  });

  test('замолчавшее звено не держит цепочку — ход уходит следующему', () async {
    mgr.debugSetBuiltins(
      offline: _SilentProvider(),
      online: _OkProvider(),
      activeId: 'silent',
    );
    final res = await mgr
        .translate('book', 'en', 'ru', enrich: false)
        .timeout(const Duration(seconds: 2));
    expect(res?.primary, 'книга');
    expect(res?.sourceId, 'ok');
  });

  test('неудача звена тоже передаёт ход дальше', () async {
    mgr.debugSetBuiltins(
      offline: _FailingProvider(),
      online: _OkProvider(),
      activeId: 'failing',
    );
    final res = await mgr.translate('book', 'en', 'ru', enrich: false);
    expect(res?.sourceId, 'ok');
  });

  test('молчат все — возвращается null, а не вечное ожидание', () async {
    mgr.debugSetBuiltins(
      offline: _SilentProvider(),
      online: _SilentProvider(),
      activeId: 'silent',
    );
    final res = await mgr
        .translate('book', 'en', 'ru', enrich: false)
        .timeout(const Duration(seconds: 2));
    expect(res, isNull);
  });

  group('сообщение о неудаче', () {
    tearDown(() {
      TranslationService.debugSetDownloading('en', value: false);
    });

    test('пока модель качается, говорим про загрузку, а не про ошибку', () {
      TranslationService.debugSetDownloading('en');
      expect(mgr.failureKey('en', 'ru'), 'translate_downloading');
    });

    test('загрузки нет — обычная ошибка перевода', () {
      expect(mgr.failureKey('en', 'ru'), 'translate_failed');
    });

    test('качается чужой язык — на нашу пару это не влияет', () {
      TranslationService.debugSetDownloading('de');
      expect(mgr.failureKey('en', 'ru'), 'translate_failed');
      TranslationService.debugSetDownloading('de', value: false);
    });
  });

  group('потолок ожидания', () {
    test('свой сервер с локальной LLM ждёт дольше веб-переводчика', () {
      const cfg = EndpointConfig(
        id: 'x',
        name: 'Ollama',
        kind: EndpointKind.ollama,
        baseUrl: 'http://192.168.1.10:11434',
        apiKey: '',
        model: 'llama3.1',
      );
      // Внутри запроса к Ollama стоит 60 с: внешний потолок обязан быть больше,
      // иначе цепочка срывает ответ, который вот-вот придёт.
      expect(EndpointProvider(cfg).timeout.inSeconds, greaterThan(60));
    });
  });
}
