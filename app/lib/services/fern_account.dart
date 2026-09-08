import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import 'license_service.dart';

/// Аккаунт Fern: вход почтой с паролем, через Google и через Apple.
///
/// Слой перенесён из Togetherly (`pb_auth_service.dart`) вместе с его
/// граблями — они оплачены живыми жалобами, и переписывать их заново незачем:
/// таймауты против «вечного спиннера» на iOS, встроенный браузер для OAuth
/// (внешний уводит приложение в фон и рвёт сокет), запасной заход системным
/// браузером, повторная проверка входом после таймаута регистрации.
///
/// Отличие одно, и оно главное: коллекция своя — `fern_users`. Аккаунты Fern и
/// Togetherly не смешиваются: разные записи, разные сессии, разные подписки.
/// Общий у приложений только сервер и OAuth-клиент, которым человек
/// доказывает, что почта его.
///
/// Аккаунт нужен ради подписки: она платится каждый месяц, и её надо к кому-то
/// привязать. Кто не платит — тот про аккаунт и не слышит.
enum AuthOutcome {
  ok,

  /// Пара «почта и пароль» не подошла.
  wrongPassword,

  /// На эту почту аккаунт уже заведён.
  emailTaken,

  /// В адресе нет собаки или он пуст.
  invalidEmail,

  /// Пароль короче восьми знаков — требование PocketBase.
  weakPassword,

  /// До сервера не достучались.
  network,

  /// Человек закрыл окно входа сам.
  cancelled,

  /// Сервер ответил, но чем-то незнакомым.
  failed,
}

class FernAccount extends ChangeNotifier {
  FernAccount._();

  static final FernAccount instance = FernAccount._();

  /// Адрес сервера. Переопределяется на сборке:
  /// `--dart-define=FERN_PB_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'FERN_PB_URL',
    defaultValue: 'https://togetherly.duckdns.org',
  );

  /// Коллекция аккаунтов Fern.
  static const String collection = 'fern_users';

  /// Минимальная длина пароля в PocketBase.
  static const int minPasswordLength = 8;

  static const String _authPrefsKey = 'fernPbAuth';

  /// Сколько ждём ответ сервера. Регистрации дают больше: сервер пишет запись
  /// и прогоняет хуки, и в вечер наплыва у Togetherly ответ шёл по двадцать
  /// пять секунд — клиент сдавался, а аккаунт при этом создавался.
  static const Duration netTimeout = Duration(seconds: 20);
  static const Duration createTimeout = Duration(seconds: 45);

  /// Подменный клиент для тестов: сети в них нет.
  @visibleForTesting
  static PocketBase? debugClient;

  PocketBase? _pb;
  bool _initialized = false;

  PocketBase get pb {
    final c = debugClient ?? _pb;
    if (c == null) throw StateError('FernAccount.init() ещё не вызван');
    return c;
  }

  bool get signedIn => (debugClient ?? _pb)?.authStore.isValid ?? false;
  RecordModel? get record => pb.authStore.record;
  String? get uid => record?.id;
  String? get email => record?.getStringValue('email');
  String? get token => pb.authStore.token;

  /// Поднимает клиент и восстанавливает сессию с диска. Идемпотентно.
  Future<void> init() async {
    if (_initialized || debugClient != null) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_authPrefsKey);
    final authStore = AsyncAuthStore(
      initial: stored,
      save: (String data) async {
        final p = await SharedPreferences.getInstance();
        await p.setString(_authPrefsKey, data);
      },
      clear: () async {
        final p = await SharedPreferences.getInstance();
        await p.remove(_authPrefsKey);
      },
    );
    _pb = PocketBase(baseUrl, authStore: authStore);
    _initialized = true;
    notifyListeners();
  }

  Future<AuthOutcome> signIn(String email, String password) async {
    final address = _clean(email);
    if (!_looksLikeEmail(address)) return AuthOutcome.invalidEmail;
    try {
      await pb
          .collection(collection)
          .authWithPassword(address, password)
          .timeout(netTimeout);
      notifyListeners();
      return AuthOutcome.ok;
    } on TimeoutException {
      return AuthOutcome.network;
    } catch (e) {
      return _outcomeOf(e, wrongPasswordOn400: true);
    }
  }

  /// Заводит аккаунт и сразу входит: PocketBase при создании записи токена не
  /// отдаёт, а человек, нажавший «Создать аккаунт», ждёт, что он уже внутри.
  Future<AuthOutcome> signUp(String email, String password) async {
    final address = _clean(email);
    if (!_looksLikeEmail(address)) return AuthOutcome.invalidEmail;
    if (password.length < minPasswordLength) return AuthOutcome.weakPassword;

    try {
      await pb.collection(collection).create(body: {
        'email': address,
        'password': password,
        'passwordConfirm': password,
      }).timeout(createTimeout);
    } on TimeoutException {
      // Ответа не дождались, но запись могла лечь. Проверяем это входом: если
      // пускает — регистрация состоялась, и пугать человека нечем.
      final outcome = await signIn(address, password);
      return outcome == AuthOutcome.ok ? AuthOutcome.ok : AuthOutcome.network;
    } catch (e) {
      final outcome = _outcomeOf(e);
      // Почта занята — возможно, своим же прошлым заходом: пробуем войти.
      if (outcome == AuthOutcome.emailTaken) {
        final second = await signIn(address, password);
        if (second == AuthOutcome.ok) return AuthOutcome.ok;
      }
      return outcome;
    }
    return signIn(address, password);
  }

  /// Вход через провайдера (web-flow PocketBase).
  ///
  /// Страница открывается ВСТРОЕННЫМ браузером: внешний уводит приложение в
  /// фон, и сокет, по которому PocketBase возвращает сессию, обрывается. Если
  /// встроенный не справился — пробуем системный: один шанс лучше отказа.
  Future<AuthOutcome> signInWithProvider(String provider) async {
    try {
      await pb.collection(collection).authWithOAuth2(provider, (url) async {
        try {
          final opened =
              await launchUrl(url, mode: LaunchMode.inAppBrowserView);
          if (opened) return;
        } catch (e) {
          debugPrint('FernAccount: встроенный браузер не открыл вход — $e');
        }
        await launchUrl(url, mode: LaunchMode.externalApplication);
      });
      try {
        await closeInAppWebView();
      } catch (_) {}
      notifyListeners();
      return AuthOutcome.ok;
    } catch (e) {
      debugPrint('FernAccount.signInWithProvider($provider): $e');
      return _outcomeOf(e);
    }
  }

  Future<AuthOutcome> signInWithGoogle() => signInWithProvider('google');

  /// Вход через Apple.
  ///
  /// На iPhone сперва системным диалогом: у Togetherly вход через браузер
  /// отказывал у части людей (77 обрывов загрузки `appleid.apple.com` против
  /// 33 удачных входов за сутки), и лечится это не браузером, а способом.
  Future<AuthOutcome> signInWithApple() async {
    if (!kIsWeb && Platform.isIOS) {
      final outcome = await _signInWithAppleNative();
      if (outcome == AuthOutcome.ok || outcome == AuthOutcome.cancelled) {
        return outcome;
      }
    }
    return signInWithProvider('apple');
  }

  Future<AuthOutcome> _signInWithAppleNative() async {
    try {
      final raw = _randomNonce();
      final nonce = sha256.convert(raw.codeUnits).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        return AuthOutcome.failed;
      }
      final answer = await pb.send(
        '/api/fern/apple',
        method: 'POST',
        body: {'identityToken': identityToken, 'nonce': raw},
      ).timeout(netTimeout);
      if (answer is! Map || answer['token'] is! String) return AuthOutcome.failed;
      pb.authStore.save(
        answer['token'] as String,
        RecordModel.fromJson(
            Map<String, dynamic>.from(answer['record'] as Map)),
      );
      notifyListeners();
      return AuthOutcome.ok;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return AuthOutcome.cancelled;
      return AuthOutcome.failed;
    } catch (e) {
      debugPrint('FernAccount: системный вход Apple не сложился — $e');
      return AuthOutcome.failed;
    }
  }

  /// Письмо со ссылкой на смену пароля.
  Future<bool> requestPasswordReset(String email) async {
    final address = _clean(email);
    if (!_looksLikeEmail(address)) return false;
    try {
      await pb
          .collection(collection)
          .requestPasswordReset(address)
          .timeout(netTimeout);
      return true;
    } catch (e) {
      debugPrint('FernAccount.requestPasswordReset: $e');
      return false;
    }
  }

  /// Выход. Талон подписки уходит вместе с сессией: подписка принадлежит
  /// аккаунту. Ключ навсегда остаётся — он куплен разово и устройством.
  Future<void> signOut() async {
    try {
      pb.authStore.clear();
    } catch (_) {}
    await LicenseService.instance.clearTicket();
    notifyListeners();
  }

  /// Освежает сессию. `false` — токен больше не годен.
  Future<bool> refresh() async {
    if (!signedIn) return false;
    try {
      await pb.collection(collection).authRefresh().timeout(netTimeout);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('FernAccount.refresh: $e');
      return false;
    }
  }

  static AuthOutcome _outcomeOf(Object e, {bool wrongPasswordOn400 = false}) {
    if (e is ClientException) {
      final code = e.statusCode;
      if (code == 0) return AuthOutcome.network;
      if (code == 400 || code == 403) {
        final text = e.response.toString();
        if (text.contains('email')) return AuthOutcome.emailTaken;
        if (wrongPasswordOn400) return AuthOutcome.wrongPassword;
        return AuthOutcome.failed;
      }
      return AuthOutcome.failed;
    }
    return AuthOutcome.network;
  }

  static String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  static String _clean(String email) => email.trim().toLowerCase();

  /// Проверка на глаз: сервер проверит строже, а человеку важно не улететь в
  /// сеть с опечаткой вроде «вася».
  static bool _looksLikeEmail(String email) {
    final at = email.indexOf('@');
    return at > 0 && email.indexOf('.', at) > at + 1 && !email.contains(' ');
  }
}
