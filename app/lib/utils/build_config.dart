/// Откуда приехала сборка. Задаётся при компиляции:
/// `--dart-define=STORE=play` для Google Play, `appstore` для App Store,
/// `rustore` для RuStore, иначе — сборка для GitHub.
///
/// Зачем: Play запрещает приложениям обновлять себя мимо магазина
/// (политика «Device and Network Abuse»). Поэтому в Play-сборке встроенный
/// апдейтер и разрешение на установку пакетов выключены, а обновления
/// доставляет сам магазин.
const String kStore = String.fromEnvironment('STORE', defaultValue: 'github');

/// Сборка для Google Play: без самообновления из GitHub.
const bool kPlayBuild = kStore == 'play';

/// Сборка для App Store: покупка Pro идёт через StoreKit.
///
/// Ключ из бота там не показывается вовсе. Правило 3.1.1 запрещает открывать
/// платные возможности покупкой мимо Apple, и одного поля ввода ключа хватает
/// на отказ в ревью.
const bool kAppStoreBuild = kStore == 'appstore';

/// Есть ли в этой сборке магазинная касса.
///
/// Play и App Store работают через один `in_app_purchase` и один товар
/// `fern_pro`, поэтому развилка в коде общая. Отдельный [kPlayBuild] остался
/// там, где речь именно про Google: In-App Update и разрешение на установку.
const bool kStoreBilling = kPlayBuild || kAppStoreBuild;

/// Сборка для RuStore: обновления доставляет магазин.
const bool kRuStoreBuild = kStore == 'rustore';

/// Сборка для sideload (GitHub / Obtainium): апдейтер внутри приложения.
///
/// Именно `kStore == 'github'`, а НЕ `!kPlayBuild`: у RuStore-сборки своего
/// апдейтера тоже нет, и разрешение на установку пакетов ей не выдаётся.
const bool kSelfUpdate = kStore == 'github';
