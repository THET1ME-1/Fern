import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
  static const String _channelId = 'daily_reminder';

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
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        'Ежедневные напоминания',
        channelDescription: 'Напоминание позаниматься в Fern',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.zonedSchedule(
        id: _dailyId,
        title: title,
        body: body,
        scheduledDate: _nextInstanceOf(hour, minute),
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
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
