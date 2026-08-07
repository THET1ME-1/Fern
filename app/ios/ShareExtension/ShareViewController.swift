import receive_sharing_intent

/// Приём «Поделиться» на iOS.
///
/// Вся работа лежит в `RSIShareViewController` из пакета: он забирает
/// вложения, складывает их в общий контейнер App Group и открывает Fern по
/// схеме `ShareMedia-com.fern.flashcards`. Дальше материал разбирает
/// `lib/share/share_import.dart` — тот же код, что и на Android.
class ShareViewController: RSIShareViewController {
  /// Открывать приложение сразу, без промежуточного окна: человек уже выбрал
  /// Fern в системном листе, спрашивать его второй раз незачем.
  override func shouldAutoRedirect() -> Bool {
    return true
  }
}
