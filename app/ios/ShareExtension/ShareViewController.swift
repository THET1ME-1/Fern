/// Приём «Поделиться» на iOS.
///
/// Вся работа лежит в `RSIShareViewController`: он забирает вложения,
/// складывает их в общий контейнер App Group и открывает Fern по схеме
/// `ShareMedia-com.fern.flashcards`. Дальше материал разбирает
/// `lib/share/share_import.dart` — тот же код, что и на Android.
///
/// Класс лежит рядом копией из пакета, а не приходит модулем: модуль тянет
/// заголовок плагина с `Flutter/Flutter.h`, которого у расширения нет.
class ShareViewController: RSIShareViewController {
  /// Открывать приложение сразу, без промежуточного окна: человек уже выбрал
  /// Fern в системном листе, спрашивать его второй раз незачем.
  override func shouldAutoRedirect() -> Bool {
    return true
  }
}
