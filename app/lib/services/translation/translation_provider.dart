/// Расширяемый слой перевода Fern.
///
/// Раньше перевод был жёстко завязан на один движок (ML Kit on-device).
/// Здесь вводится абстракция [TranslationProvider] — конкретный движок или
/// сервис перевода. Реализации: ML Kit (офлайн), онлайн Google, свой сервер
/// (Ollama/OpenAI/LibreTranslate/DeepL), локальные GGUF/ONNX (Фаза 2).
///
/// Оркестрирует всё [TranslationManager]: держит список провайдеров, активный
/// выбор и fallback-цепочку.
library;

/// Результат одного запроса перевода.
///
/// Ключевая идея качества: не одно навязанное значение, а несколько вариантов
/// (для многозначных слов) + часть речи и примеры из словаря. Пользователь
/// выбирает нужный вариант чипсом.
class TransResult {
  /// Основной перевод — подставляется в карточку по умолчанию.
  final String primary;

  /// Альтернативные варианты/значения (chips на выбор).
  final List<String> alternatives;

  /// Часть речи, если её дал словарь («сущ.», «глаг.», «adj»…).
  final String? partOfSpeech;

  /// Примеры употребления (в языке-источнике).
  final List<String> examples;

  /// Транскрипция/произношение, если известно (например `/ˈbʊk/`).
  final String? phonetic;

  /// id провайдера-источника (для подписи/отладки).
  final String sourceId;

  const TransResult({
    required this.primary,
    this.alternatives = const [],
    this.partOfSpeech,
    this.examples = const [],
    this.phonetic,
    required this.sourceId,
  });

  /// Все варианты перевода без дублей, [primary] первым.
  List<String> get options {
    final seen = <String>{};
    final out = <String>[];
    for (final s in [primary, ...alternatives]) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  /// Копия с добавленными словарными данными (обогащение поверх машинного МТ).
  TransResult mergedWith({
    List<String>? alternatives,
    String? partOfSpeech,
    List<String>? examples,
    String? phonetic,
  }) {
    return TransResult(
      primary: primary,
      alternatives: [...this.alternatives, ...?alternatives],
      partOfSpeech: this.partOfSpeech ?? partOfSpeech,
      examples: examples == null ? this.examples : [...this.examples, ...examples],
      phonetic: this.phonetic ?? phonetic,
      sourceId: sourceId,
    );
  }
}

/// Провайдер перевода: конкретный движок/сервис.
abstract class TranslationProvider {
  /// Стабильный идентификатор (для сохранения выбора/конфигов в prefs).
  String get id;

  /// Человекочитаемое имя для UI.
  String get name;

  /// Работает ли без сети (офлайн-значок в списке).
  bool get isOffline;

  /// Тип-подпись для UI («Онлайн», «Свой сервер», «Локальная модель»…).
  String get kindLabel;

  /// Готов ли перевести пару языков (модели скачаны/сконфигурирован/есть сеть).
  Future<bool> isReady(String from, String to);

  /// Поддерживается ли пара в принципе (для показа кнопки перевода).
  bool supportsPair(String from, String to) => from != to;

  /// Переводит [text] с [from] на [to]. [context] — предложение-контекст для
  /// снятия многозначности (используют LLM-провайдеры). Возвращает null при
  /// ошибке/недоступности — тогда менеджер уходит по fallback-цепочке.
  Future<TransResult?> translate(
    String text,
    String from,
    String to, {
    String? context,
  });
}
