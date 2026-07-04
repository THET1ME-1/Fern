import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../deck_repository.dart';
import 'dictionary_service.dart';
import 'endpoint_provider.dart';
import 'mlkit_provider.dart';
import 'online_mt_provider.dart';
import 'translation_provider.dart';

/// Реестр и оркестратор перевода: держит список провайдеров, активный выбор и
/// fallback-цепочку, обогащает результат словарём. Конфиги — в prefs
/// (через [DeckRepository]). Публичное API, которое зовёт UI вместо прямых
/// вызовов конкретного движка.
class TranslationManager extends ChangeNotifier {
  TranslationManager._();
  static final TranslationManager instance = TranslationManager._();

  final MlKitProvider _mlkit = MlKitProvider();
  final OnlineMtProvider _google = OnlineMtProvider();
  final List<EndpointConfig> _endpoints = [];

  String _activeId = 'mlkit';
  bool _loaded = false;

  DeckRepository get _repo => DeckRepository.instance;

  /// Загружает конфиги и выбор активного провайдера. Вызывать после init репо.
  Future<void> load() async {
    _endpoints
      ..clear()
      ..addAll(_decodeEndpoints(await _repo.translationConfigJson()));
    _activeId = await _repo.activeProviderId() ?? 'mlkit';
    _loaded = true;
    notifyListeners();
  }

  List<EndpointConfig> _decodeEndpoints(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          EndpointConfig.fromJson((e as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistEndpoints() async {
    await _repo.setTranslationConfigJson(
      jsonEncode([for (final e in _endpoints) e.toJson()]),
    );
  }

  // ----------------------------- Провайдеры -----------------------------

  /// Все доступные провайдеры: встроенные + пользовательские серверы.
  List<TranslationProvider> get providers => [
        _mlkit,
        _google,
        for (final e in _endpoints) EndpointProvider(e),
      ];

  List<EndpointConfig> get endpoints => List.unmodifiable(_endpoints);

  String get activeId => _activeId;

  /// Активный провайдер (или ML Kit, если сохранённый id больше не существует).
  TranslationProvider get active =>
      providers.firstWhere((p) => p.id == _activeId, orElse: () => _mlkit);

  Future<void> setActive(String id) async {
    _activeId = id;
    await _repo.setActiveProviderId(id);
    notifyListeners();
  }

  Future<void> addEndpoint(EndpointConfig cfg) async {
    _endpoints.add(cfg);
    await _persistEndpoints();
    notifyListeners();
  }

  Future<void> updateEndpoint(EndpointConfig cfg) async {
    final i = _endpoints.indexWhere((e) => e.id == cfg.id);
    if (i >= 0) _endpoints[i] = cfg;
    await _persistEndpoints();
    notifyListeners();
  }

  Future<void> removeEndpoint(String id) async {
    _endpoints.removeWhere((e) => e.id == id);
    if (_activeId == id) await setActive('mlkit');
    await _persistEndpoints();
    notifyListeners();
  }

  // ----------------------------- Перевод -----------------------------

  /// Можно ли показывать кнопку перевода для этой пары (online работает для
  /// любой различной пары; офлайн-fallback подхватит поддерживаемые).
  bool canTranslate(String from, String to) => from != to;

  /// Переводит через активный провайдер, при неудаче — по fallback-цепочке
  /// (активный → Google → ML Kit). Затем обогащает словарём (часть речи,
  /// примеры, транскрипция) для одиночных слов.
  Future<TransResult?> translate(
    String text,
    String from,
    String to, {
    String? context,
    bool enrich = true,
  }) async {
    if (!_loaded) await load();
    final t = text.trim();
    if (t.isEmpty || from == to) return null;

    TransResult? result;
    for (final p in _fallbackChain()) {
      if (!p.supportsPair(from, to)) continue;
      result = await p.translate(t, from, to, context: context);
      if (result != null) break;
    }
    if (result == null) return null;

    if (enrich && !t.contains(' ')) {
      final dict = await DictionaryService.lookup(t, from);
      if (!dict.isEmpty) {
        result = result.mergedWith(
          partOfSpeech: dict.partOfSpeech,
          examples: dict.examples,
          phonetic: dict.phonetic,
        );
      }
    }
    return result;
  }

  /// Активный провайдер первым, затем встроенные онлайн/офлайн как запас.
  List<TranslationProvider> _fallbackChain() {
    final active = this.active;
    final chain = <TranslationProvider>[active];
    for (final p in [_google, _mlkit]) {
      if (p.id != active.id) chain.add(p);
    }
    return chain;
  }
}
