/// Из чего складывается запуск и что делать, когда шаг не поднялся.
///
/// Раньше `main()` ловил любое исключение и отвечал на всё одинаково:
/// «Хранилище словаря повреждено», две кнопки, обе уводят живую базу в
/// карантин. Падала при этом чаще не база, а что-нибудь из двух десятков
/// шагов рядом — плагин, ассет, лицензия. Человеку предлагали стереть словарь
/// из-за не загрузившейся темы.
library;

/// Шаг запуска. Порядок совпадает с порядком в `startFern`.
enum StartupStep {
  storage,
  theme,
  locale,
  languages,
  translation,
  reader,
  cardImages,
  license,
  billing,
  seed,
  reminders,
}

extension StartupStepTitle on StartupStep {
  /// Как назвать шаг человеку. Аварийный экран живёт до загрузки локалей,
  /// поэтому языка у него ровно два — как и у самого экрана.
  String title({required bool ru}) => switch (this) {
        StartupStep.storage => ru ? 'хранилище словаря' : 'word storage',
        StartupStep.theme => ru ? 'оформление' : 'appearance',
        StartupStep.locale => ru ? 'язык интерфейса' : 'interface language',
        StartupStep.languages => ru ? 'список языков' : 'language list',
        StartupStep.translation => ru ? 'переводчик' : 'translation',
        StartupStep.reader => ru ? 'настройки читалки' : 'reader settings',
        StartupStep.cardImages => ru ? 'картинки карточек' : 'card images',
        StartupStep.license => ru ? 'лицензия' : 'license',
        StartupStep.billing => ru ? 'покупки' : 'purchases',
        StartupStep.seed => ru ? 'готовые колоды' : 'starter decks',
        StartupStep.reminders => ru ? 'напоминания' : 'reminders',
      };

  /// Чинится ли отказ восстановлением данных. Только у хранилища: остальное
  /// карантином базы не лечится, а вот испортить им данные можно.
  bool get isStorage => this == StartupStep.storage;
}

/// Отказ на конкретном шаге запуска.
class StartupError implements Exception {
  final StartupStep step;
  final Object cause;

  StartupError(this.step, this.cause);

  bool get isStorage => step.isStorage;

  @override
  String toString() => '${step.name}: $cause';
}
