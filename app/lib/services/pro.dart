import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_service.dart';
import 'license_service.dart';
import 'signed_store.dart';

/// Что закрыто в бесплатной версии.
///
/// Закрыт **отдельный сценарий** — учиться на своём материале: книги, видео,
/// статьи, распознавание текста с фотографии и перенос чужих колод. Всё
/// остальное — карточки, все режимы, FSRS, статистика, напоминания, бэкап и
/// экспорт своего словаря — бесплатно и без счётчиков.
///
/// Лимитов на число колод и карточек нет намеренно. Приложение, которое
/// упирается в «осталось 2 из 5», человек удаляет вместе с намерением платить;
/// приложение, которое делает своё дело даром, живёт на телефоне и однажды
/// продаёт то, чего в нём правда не хватает.
enum ProFeature {
  /// Библиотека: разбор книги, видео, статьи по ссылке, текст с фотографии.
  library,

  /// Перенос колод из Anki (.apkg) и таблиц (CSV/TSV).
  deckImport,
}

class Pro {
  const Pro._();

  /// Первый источник в библиотеке бесплатен: главную способность Fern надо
  /// потрогать на своей книге, а не на обещании в описании.
  static const int freeSources = 1;

  static const String _usedKey = 'freeSourcesUsed';
  static int _used = 0;

  /// Сколько бесплатных разборов осталось.
  static int get freeSourcesLeft =>
      (freeSources - _used).clamp(0, freeSources);

  /// Куплено — ключом или покупкой в магазине.
  static bool get active =>
      LicenseService.instance.isValid || BillingService.instance.owned;

  /// Доступна ли возможность прямо сейчас.
  ///
  /// Асинхронно, потому что счётчик и список источников лежат на диске: гейт
  /// зовут и с главного экрана, где библиотека ещё не открывалась.
  static Future<bool> allows(ProFeature feature) async {
    if (active) return true;
    return switch (feature) {
      ProFeature.library => await _loadUsed() < freeSources,
      ProFeature.deckImport => false,
    };
  }

  /// Записывает израсходованный бесплатный разбор.
  ///
  /// Считаются именно РАСХОДЫ, а не сегодняшняя длина библиотеки: прежде гейт
  /// смотрел на список, и удалив прочитанную книгу, человек получал следующую
  /// даром — платить было незачем.
  static Future<void> noteSourceUsed() async {
    final used = await _loadUsed() + 1;
    _used = used;
    await SignedStore.setInt(_usedKey, used);
  }

  /// Счётчик с диска.
  ///
  /// Подделанный или обнулённый снаружи счётчик читается как израсходованный:
  /// обнулять его выгодно, а терять от подделки должен тот, кто подделывает.
  static Future<int> _loadUsed() async {
    _used = await SignedStore.getInt(_usedKey, onTampered: freeSources) ?? 0;
    return _used;
  }

  /// Разовый перенос: у тех, кто разобрал книгу до появления счётчика, его нет,
  /// и за расход принимается уже собранная библиотека. Обновление приложения не
  /// должно дарить лишнюю книгу. Зовётся из `main` со списком источников —
  /// иначе `Pro` и `SourceLibrary` замкнулись бы друг на друге.
  static Future<void> migrateFromLibrary(int existingSources) async {
    if (await SharedPreferencesAsync().getInt(_usedKey) != null) {
      // Счётчик уже есть — просто подтягиваем его в кэш: [freeSourcesLeft]
      // синхронный, и настройки, открытые до первой проверки гейта, иначе
      // показали бы неизрасходованный разбор.
      await _loadUsed();
      return;
    }
    _used = existingSources;
    await SignedStore.setInt(_usedKey, existingSources);
  }

  /// Работают ли надстройки поверх книги: чтение засчитывается как
  /// повторение, а слова ближайших страниц идут в очередь первыми.
  ///
  /// Отдельным именем, а не голым [active] в трёх местах: это одно решение о
  /// границе, и принимать его надо в одном месте.
  static bool get bookBoost => active;

  /// Сколько бесплатных разборов израсходовано. Нужен «удалению всех данных»:
  /// оно стирает настройки целиком, а счётчик обязан пережить стирание.
  static Future<int> usedSources() => _loadUsed();

  /// Вернуть счётчик на место после стирания настроек.
  static Future<void> restoreUsedSources(int used) async {
    if (used <= 0) return;
    _used = used;
    await SignedStore.setInt(_usedKey, used);
  }

  /// Слушать вместе: покупка и ключ — два источника одного состояния.
  static Listenable get changes =>
      Listenable.merge([LicenseService.instance, BillingService.instance]);
}
