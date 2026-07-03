import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fern/services/deck_repository.dart';

/// Ставит чистое in-memory хранилище под ОБА API (legacy + async) и сбрасывает
/// кэш репозитория. Зовём в `setUp` каждого теста, работающего с данными.
Future<void> resetStorage() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  DeckRepository.instance.resetForTest();
}
