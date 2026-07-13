import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../l10n/strings.dart';
import 'translation_provider.dart';

/// Тип API стороннего сервера перевода.
enum EndpointKind { ollama, openai, libretranslate, deepl }

extension EndpointKindInfo on EndpointKind {
  String get id => switch (this) {
        EndpointKind.ollama => 'ollama',
        EndpointKind.openai => 'openai',
        EndpointKind.libretranslate => 'libretranslate',
        EndpointKind.deepl => 'deepl',
      };

  /// Подпись типа для UI. Имена собственные (Ollama, LibreTranslate, DeepL) не
  /// переводятся; локализуется только описательная «OpenAI-совместимый».
  String get label => switch (this) {
        EndpointKind.ollama => 'Ollama',
        EndpointKind.openai => tr('endpoint_openai_compat'),
        EndpointKind.libretranslate => 'LibreTranslate',
        EndpointKind.deepl => 'DeepL',
      };

  /// Нужен ли этому типу ключ/токен доступа.
  bool get needsKey =>
      this == EndpointKind.openai || this == EndpointKind.deepl;

  /// Нужно ли имя модели (LLM-типы).
  bool get needsModel =>
      this == EndpointKind.ollama || this == EndpointKind.openai;

  static EndpointKind fromId(String id) => EndpointKind.values.firstWhere(
        (k) => k.id == id,
        orElse: () => EndpointKind.ollama,
      );
}

/// Конфиг одного пользовательского сервера. Сериализуется в prefs (JSON).
class EndpointConfig {
  final String id; // уникальный, напр. ep_<micros>
  final String name; // отображаемое имя
  final EndpointKind kind;
  final String baseUrl;
  final String apiKey;
  final String model;

  const EndpointConfig({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    this.apiKey = '',
    this.model = '',
  });

  EndpointConfig copyWith({
    String? name,
    EndpointKind? kind,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) =>
      EndpointConfig(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.id,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
      };

  factory EndpointConfig.fromJson(Map<String, dynamic> j) => EndpointConfig(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Server',
        kind: EndpointKindInfo.fromId(j['kind'] as String? ?? 'ollama'),
        baseUrl: j['baseUrl'] as String? ?? '',
        apiKey: j['apiKey'] as String? ?? '',
        model: j['model'] as String? ?? '',
      );
}

/// Провайдер поверх пользовательского сервера. Собирает запрос под тип API и
/// разбирает ответ. Тонкий клиент: вся тяжесть — на сервере пользователя.
class EndpointProvider extends TranslationProvider {
  final EndpointConfig config;
  EndpointProvider(this.config);

  @override
  String get id => config.id;

  @override
  String get name => config.name;

  @override
  bool get isOffline => false;

  @override
  String get kindLabel => 'endpoint';

  @override
  bool supportsPair(String from, String to) => from != to;

  @override
  Future<bool> isReady(String from, String to) async =>
      from != to && config.baseUrl.trim().isNotEmpty;

  @override
  Future<TransResult?> translate(
    String text,
    String from,
    String to, {
    String? context,
  }) async {
    final q = text.trim();
    if (q.isEmpty || from == to) return null;
    try {
      final primary = switch (config.kind) {
        EndpointKind.libretranslate => await _libre(q, from, to),
        EndpointKind.deepl => await _deepl(q, from, to),
        EndpointKind.ollama => await _ollama(q, from, to, context),
        EndpointKind.openai => await _openai(q, from, to, context),
      };
      if (primary == null || primary.trim().isEmpty) return null;
      return TransResult(primary: primary.trim(), sourceId: id);
    } catch (e) {
      debugPrint('EndpointProvider(${config.kind.id}) failed: $e');
      return null;
    }
  }

  Uri _url(String path) {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$path');
  }

  Future<String?> _libre(String q, String from, String to) async {
    final resp = await http
        .post(
          _url('/translate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'q': q,
            'source': from,
            'target': to,
            'format': 'text',
            if (config.apiKey.isNotEmpty) 'api_key': config.apiKey,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return j['translatedText'] as String?;
  }

  Future<String?> _deepl(String q, String from, String to) async {
    final base = config.baseUrl.trim().isEmpty
        ? 'https://api-free.deepl.com/v2/translate'
        : _url('/v2/translate').toString();
    final resp = await http.post(
      Uri.parse(base),
      headers: {
        'Authorization': 'DeepL-Auth-Key ${config.apiKey}',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'text': q,
        'source_lang': from.toUpperCase(),
        'target_lang': to.toUpperCase(),
      },
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final list = j['translations'] as List?;
    if (list == null || list.isEmpty) return null;
    return (list.first as Map)['text'] as String?;
  }

  Future<String?> _ollama(
      String q, String from, String to, String? ctx) async {
    final resp = await http
        .post(
          _url('/api/generate'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': config.model.isEmpty ? 'llama3.1' : config.model,
            'prompt': _prompt(q, from, to, ctx),
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return _clean(j['response'] as String?);
  }

  Future<String?> _openai(
      String q, String from, String to, String? ctx) async {
    final resp = await http
        .post(
          _url('/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (config.apiKey.isNotEmpty)
              'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.model.isEmpty ? 'gpt-4o-mini' : config.model,
            'temperature': 0,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a translation engine. Reply with ONLY the translation, no notes or quotes.',
              },
              {'role': 'user', 'content': _prompt(q, from, to, ctx)},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = j['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final msg = (choices.first as Map)['message'] as Map?;
    return _clean(msg?['content'] as String?);
  }

  String _prompt(String q, String from, String to, String? ctx) {
    final fromName = _langName(from);
    final toName = _langName(to);
    final ctxLine = (ctx != null && ctx.trim().isNotEmpty)
        ? '\nContext sentence: "${ctx.trim()}"'
        : '';
    return 'Translate the following $fromName text into $toName. '
        'Reply with ONLY the translation, no explanations.$ctxLine\n\nText: "$q"';
  }

  /// Убирает обрамляющие кавычки/подписи от LLM-ответа.
  String? _clean(String? s) {
    if (s == null) return null;
    var t = s.trim();
    if (t.length >= 2 &&
        ((t.startsWith('"') && t.endsWith('"')) ||
            (t.startsWith('«') && t.endsWith('»')))) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }
}

/// Английское имя языка по ISO-коду — для промптов LLM.
String _langName(String code) => const {
      'en': 'English',
      'es': 'Spanish',
      'de': 'German',
      'fr': 'French',
      'it': 'Italian',
      'pt': 'Portuguese',
      'tr': 'Turkish',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'ru': 'Russian',
    }[code] ??
    code;
