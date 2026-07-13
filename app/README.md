# Fern — приложение (Flutter)

Здесь живёт сам Flutter-проект. Описание приложения, скриншоты и установка —
в [README репозитория](../README.md).

## Разработка

```bash
cd app
flutter pub get
flutter analyze     # должно быть 0 issues
flutter test        # все тесты зелёные
flutter run
```

## Релизная сборка

```bash
./tool/build_release.sh      # split-APK по ABI → app/dist/Fern-<версия>-<abi>.apk
```

Скрипт сам гоняет `analyze` и тесты, подписывает релизным ключом и печатает
SHA-256 готовых файлов.

**Ключ подписи** лежит вне репозитория: `android/key.properties` +
`android/fern-release.jks` (оба в `.gitignore`, копия — в `~/keys/`). Без них
сборка возьмёт отладочный ключ, и такой APK не встанет поверх боевого.

## Что где

| Каталог | Что внутри |
|---|---|
| `lib/models` | Карточка, колода, пак, FSRS, журнал повторов |
| `lib/services` | Хранилище (SQLite), бэкап, импорт книг и колод, анализ текста, перевод, TTS, OCR |
| `lib/study` | Сессия повторов, упражнения, читалка книг |
| `lib/video` | Разбор видео по субтитрам |
| `lib/l10n` | Строки интерфейса (7 языков) |
| `assets/seed`, `assets/starter` | Колоды по умолчанию |
| `assets/pos` | Офлайн-словарь частей речи (Moby POS) |
