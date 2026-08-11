/// Формы английских глаголов, нужные детектору конструкций.
///
/// Чтобы отличить «has built» (перфект) от «was built» (пассив), а «He went»
/// от «He goes», нужно знать вторую и третью форму. Правильные глаголы даёт
/// правило `-ed`, неправильные — этот список: без него любое «went» выглядит
/// начальной формой, и прошедшее время не находится вовсе.
class EnVerbs {
  const EnVerbs._();

  /// Формы глагола «быть» — самый частый вспомогательный.
  static const Set<String> be = {
    'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being', "'m", "'s", "'re",
  };

  /// Формы «быть» в настоящем времени.
  static const Set<String> bePresent = {'am', 'is', 'are'};

  /// Формы «быть» в прошедшем времени.
  static const Set<String> bePast = {'was', 'were'};

  static const Set<String> have = {'have', 'has', 'had', "'ve", "'s", "'d"};
  static const Set<String> havePresent = {'have', 'has'};
  static const Set<String> doAux = {'do', 'does', 'did'};

  /// Модальные глаголы (после них идёт начальная форма без `to`).
  static const Set<String> modals = {
    'can', 'could', 'may', 'might', 'must', 'shall', 'should', 'will',
    'would', 'ought', "'ll", "'d",
  };

  /// Все вспомогательные вместе — по ним видно, что время уже описано
  /// конструкцией и простое настоящее сюда не лезет.
  static Set<String> get auxiliaries => {...be, ...have, ...doAux, ...modals};
}

