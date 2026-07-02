/// Изучаемый язык — то, что выбирается в верхнем баннере на главном экране
/// (аналог «баннера выбора игр» в ScoreMaster). У каждой колоды слов есть свой
/// [code]; баннер фильтрует колоды по выбранному языку.
class StudyLanguage {
  /// Код языка (ISO 639-1), например `en`.
  final String code;

  /// Родное название языка (показывается как есть, без перевода).
  final String name;

  /// Флаг-эмодзи для баннера/плиток.
  final String emoji;

  const StudyLanguage(this.code, this.name, this.emoji);
}

/// Встроенный список популярных для изучения языков. Пользователь выбирает
/// активный в баннере; при желании можно добавить свой (произвольный код).
const List<StudyLanguage> kStudyLanguages = [
  StudyLanguage('en', 'English', '🇬🇧'),
  StudyLanguage('es', 'Español', '🇪🇸'),
  StudyLanguage('de', 'Deutsch', '🇩🇪'),
  StudyLanguage('fr', 'Français', '🇫🇷'),
  StudyLanguage('it', 'Italiano', '🇮🇹'),
  StudyLanguage('pt', 'Português', '🇵🇹'),
  StudyLanguage('tr', 'Türkçe', '🇹🇷'),
  StudyLanguage('zh', '中文', '🇨🇳'),
  StudyLanguage('ja', '日本語', '🇯🇵'),
  StudyLanguage('ko', '한국어', '🇰🇷'),
  StudyLanguage('ar', 'العربية', '🇸🇦'),
  StudyLanguage('ru', 'Русский', '🇷🇺'),
];

/// Язык по коду (или null, если такого во встроенном списке нет).
StudyLanguage? languageByCode(String code) {
  for (final l in kStudyLanguages) {
    if (l.code == code) return l;
  }
  return null;
}
