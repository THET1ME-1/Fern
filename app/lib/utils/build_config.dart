/// Откуда приехала сборка. Задаётся при компиляции:
/// `--dart-define=STORE=play` для Google Play, иначе — сборка для GitHub.
///
/// Зачем: Play запрещает приложениям обновлять себя мимо магазина
/// (политика «Device and Network Abuse»). Поэтому в Play-сборке встроенный
/// апдейтер и разрешение на установку пакетов выключены, а обновления
/// доставляет сам магазин.
const String kStore = String.fromEnvironment('STORE', defaultValue: 'github');

/// Сборка для Google Play: без самообновления из GitHub.
const bool kPlayBuild = kStore == 'play';

/// Сборка для sideload (GitHub / Obtainium): апдейтер внутри приложения.
const bool kSelfUpdate = !kPlayBuild;
