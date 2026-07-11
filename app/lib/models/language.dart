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

  Map<String, dynamic> toJson() =>
      {'code': code, 'name': name, 'emoji': emoji};

  factory StudyLanguage.fromJson(Map<String, dynamic> j) => StudyLanguage(
        (j['code'] as String? ?? '').trim().toLowerCase(),
        (j['name'] as String? ?? '').trim(),
        (j['emoji'] as String? ?? '').trim().isEmpty
            ? '🌐'
            : (j['emoji'] as String).trim(),
      );
}

/// Встроенный список популярных для изучения языков. Пользователь выбирает
/// активный в баннере; при желании можно добавить свой (произвольный код).
const List<StudyLanguage> kStudyLanguages = [
  // Самые популярные — вверху.
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
  // Европа.
  StudyLanguage('nl', 'Nederlands', '🇳🇱'),
  StudyLanguage('pl', 'Polski', '🇵🇱'),
  StudyLanguage('uk', 'Українська', '🇺🇦'),
  StudyLanguage('cs', 'Čeština', '🇨🇿'),
  StudyLanguage('sk', 'Slovenčina', '🇸🇰'),
  StudyLanguage('sv', 'Svenska', '🇸🇪'),
  StudyLanguage('da', 'Dansk', '🇩🇰'),
  StudyLanguage('nb', 'Norsk', '🇳🇴'),
  StudyLanguage('fi', 'Suomi', '🇫🇮'),
  StudyLanguage('el', 'Ελληνικά', '🇬🇷'),
  StudyLanguage('ro', 'Română', '🇷🇴'),
  StudyLanguage('hu', 'Magyar', '🇭🇺'),
  StudyLanguage('bg', 'Български', '🇧🇬'),
  StudyLanguage('sr', 'Српски', '🇷🇸'),
  StudyLanguage('hr', 'Hrvatski', '🇭🇷'),
  StudyLanguage('sl', 'Slovenščina', '🇸🇮'),
  StudyLanguage('lt', 'Lietuvių', '🇱🇹'),
  StudyLanguage('lv', 'Latviešu', '🇱🇻'),
  StudyLanguage('et', 'Eesti', '🇪🇪'),
  StudyLanguage('ca', 'Català', '🇪🇸'),
  StudyLanguage('is', 'Íslenska', '🇮🇸'),
  StudyLanguage('ga', 'Gaeilge', '🇮🇪'),
  StudyLanguage('sq', 'Shqip', '🇦🇱'),
  // Ближний Восток / Кавказ / Центральная Азия.
  StudyLanguage('he', 'עברית', '🇮🇱'),
  StudyLanguage('fa', 'فارسی', '🇮🇷'),
  StudyLanguage('ur', 'اردو', '🇵🇰'),
  StudyLanguage('ka', 'ქართული', '🇬🇪'),
  StudyLanguage('hy', 'Հայերեն', '🇦🇲'),
  StudyLanguage('az', 'Azərbaycan', '🇦🇿'),
  StudyLanguage('kk', 'Қазақша', '🇰🇿'),
  StudyLanguage('uz', 'Oʻzbekcha', '🇺🇿'),
  // Южная и Юго-Восточная Азия.
  StudyLanguage('hi', 'हिन्दी', '🇮🇳'),
  StudyLanguage('bn', 'বাংলা', '🇧🇩'),
  StudyLanguage('ta', 'தமிழ்', '🇮🇳'),
  StudyLanguage('te', 'తెలుగు', '🇮🇳'),
  StudyLanguage('id', 'Bahasa Indonesia', '🇮🇩'),
  StudyLanguage('ms', 'Bahasa Melayu', '🇲🇾'),
  StudyLanguage('vi', 'Tiếng Việt', '🇻🇳'),
  StudyLanguage('th', 'ไทย', '🇹🇭'),
  StudyLanguage('tl', 'Filipino', '🇵🇭'),
  // Африка.
  StudyLanguage('sw', 'Kiswahili', '🇰🇪'),
  StudyLanguage('af', 'Afrikaans', '🇿🇦'),
  // Прочее.
  StudyLanguage('eo', 'Esperanto', '🌍'),
];

/// Язык по коду (или null, если такого во встроенном списке нет).
StudyLanguage? languageByCode(String code) {
  for (final l in kStudyLanguages) {
    if (l.code == code) return l;
  }
  return null;
}
