import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/strings.dart';
import 'quick_review.dart';

/// Обработчик кнопок уведомления В ФОНОВОМ изоляте.
///
/// Отдельная функция верхнего уровня с `vm:entry-point` — иначе движок не
/// найдёт её при холодном старте по тапу. Ничего, кроме записи в очередь, тут
/// делать нельзя: репозитория и открытой базы в этом изоляте нет.
@pragma('vm:entry-point')
void quickReviewBackground(NotificationResponse response) {
  final id = response.payload;
  if (id == null || id.isEmpty) return;
  switch (response.actionId) {
    case QuickReview.actionKnow:
      QuickReview.enqueue(id, true);
    case QuickReview.actionForgot:
      QuickReview.enqueue(id, false);
  }
}

/// Локальные уведомления: ежедневное напоминание позаниматься.
///
/// Всё обёрнуто в проверки платформы и try/catch: на десктопе/в тестах методы
/// просто ничего не делают, а не падают. Будильники НЕточные — не требуют
/// разрешения на точные будильники (SCHEDULE_EXACT_ALARM).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _dailyId = 1001;
  static const int _quickId = 1002;
  static const String _channelId = 'daily_reminder';
  static const String _quickChannelId = 'quick_review';

  bool _init = false;
  bool _tzReady = false;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _ensureInit() async {
    if (_init || !_supported) return;
    _init = true;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _tzReady = true;
    } catch (e) {
      _tzReady = false;
      debugPrint('TZ init failed: $e');
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: quickReviewBackground,
        onDidReceiveBackgroundNotificationResponse: quickReviewBackground,
      );
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  /// Спрашивает разрешение на уведомления (Android 13+/iOS). true — разрешено.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await _ensureInit();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            true;
      }
    } catch (e) {
      debugPrint('requestPermission failed: $e');
    }
    return false;
  }

  /// Планирует ежедневное напоминание на [hour]:[minute].
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    await _ensureInit();
    if (!_tzReady) return;
    try {
      await _plugin.cancel(id: _dailyId);
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        tr('notif_channel_name'),
        channelDescription: tr('notif_channel_desc'),
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.zonedSchedule(
        id: _dailyId,
        title: title,
        body: body,
        scheduledDate: _nextInstanceOf(hour, minute),
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // каждый день
      );
    } catch (e) {
      debugPrint('scheduleDaily failed: $e');
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Показывает карточку прямо в шторке: слово и две кнопки.
  ///
  /// Микроповтор существует ради тех дней, когда приложение не открывают
  /// вовсе: ответ из шторки сохраняет серию и двигает расписание, а стоит
  /// одного тапа. Ответ уезжает в очередь [QuickReview] — фоновый изолят не
  /// может писать в базу.
  Future<void> showQuickReview({
    required String cardId,
    required String word,
    required String meaning,
  }) async {
    if (!_supported) return;
    await _ensureInit();
    try {
      final android = AndroidNotificationDetails(
        _quickChannelId,
        tr('quick_channel_name'),
        channelDescription: tr('quick_channel_desc'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        actions: [
          AndroidNotificationAction(
            QuickReview.actionKnow,
            tr('quick_know'),
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            QuickReview.actionForgot,
            tr('quick_forgot'),
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );
      await _plugin.show(
        id: _quickId,
        title: word,
        // Перевод в теле уведомления не показываем: иначе ответ известен до
        // того, как человек его вспомнил.
        body: tr('quick_body'),
        notificationDetails: NotificationDetails(
          android: android,
          iOS: const DarwinNotificationDetails(),
        ),
        payload: cardId,
      );
    } catch (e) {
      debugPrint('showQuickReview failed: $e');
    }
  }

  Future<void> cancelQuickReview() async {
    if (!_supported) return;
    await _ensureInit();
    try {
      await _plugin.cancel(id: _quickId);
    } catch (e) {
      debugPrint('cancelQuickReview failed: $e');
    }
  }

  Future<void> cancelDaily() async {
    if (!_supported) return;
    await _ensureInit();
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (e) {
      debugPrint('cancelDaily failed: $e');
    }
  }
}
