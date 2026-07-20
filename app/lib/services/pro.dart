import 'package:flutter/material.dart';

import 'billing_service.dart';
import 'license_service.dart';
import 'source_library.dart';

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

  /// Куплено — ключом или покупкой в магазине.
  static bool get active =>
      LicenseService.instance.isValid || BillingService.instance.owned;

  /// Доступна ли возможность прямо сейчас.
  ///
  /// Асинхронно, потому что список источников лежит на диске: гейт зовут и с
  /// главного экрана, где библиотека ещё не открывалась.
  static Future<bool> allows(ProFeature feature) async {
    if (active) return true;
    return switch (feature) {
      ProFeature.library =>
        (await SourceLibrary.instance.list()).length < freeSources,
      ProFeature.deckImport => false,
    };
  }

  /// Слушать вместе: покупка и ключ — два источника одного состояния.
  static Listenable get changes =>
      Listenable.merge([LicenseService.instance, BillingService.instance]);
}
