import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fern/services/notification_service.dart';
import 'package:fern/services/quick_review.dart';

/// iOS отдаёт уведомления приложению не сам по себе: половина работы лежит в
/// нативной части, и её нечем проверить из Dart на этой машине — Mac и iPhone
/// в хозяйстве нет. Поэтому страж сверяет ровно то, что можно прочитать: связку
/// в `AppDelegate.swift` и настройки, которые уезжают в плагин.
///
/// Оба требования — из README самого плагина, и оба уже стреляли: без делегата
/// центра уведомлений iOS не показывает уведомление при открытом приложении и
/// не доносит тап до Dart, а без колбэка регистранта изолят действий остаётся
/// без плагинов, и кнопки в шторке ничего не делают.
void main() {
  group('нативная связка iOS', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    test('AppDelegate — делегат центра уведомлений', () {
      expect(
        delegate.contains('UNUserNotificationCenter.current().delegate'),
        isTrue,
        reason: 'без этой строки уведомления не доходят до плагина',
      );
    });

    test('изолят действий получает плагины', () {
      expect(
        delegate.contains(
          'FlutterLocalNotificationsPlugin.setPluginRegistrantCallback',
        ),
        isTrue,
        reason: 'иначе кнопки «Знаю»/«Забыл» в шторке ничего не делают',
      );
    });
  });

  group('категория микроповтора', () {
    test('несёт обе кнопки ответа', () {
      final category = NotificationService.darwinCategories.singleWhere(
        (c) => c.identifier == NotificationService.quickCategoryId,
      );
      expect(
        category.actions.map((a) => a.identifier),
        containsAll(<String>[QuickReview.actionKnow, QuickReview.actionForgot]),
        reason: 'на iOS кнопки берутся из категории, а не из деталей показа',
      );
    });

    test('инициализация не спрашивает разрешение сама', () {
      final settings = NotificationService.darwinInitSettings;
      expect(
        [
          settings.requestAlertPermission,
          settings.requestBadgePermission,
          settings.requestSoundPermission,
        ],
        everyElement(isFalse),
        reason: 'иначе системный диалог выскакивает при запуске, без повода, '
            'а случайный отказ убивает уведомления насовсем',
      );
    });

    test('микроповтор помечен своей категорией', () {
      expect(
        NotificationService.quickDarwinDetails.categoryIdentifier,
        NotificationService.quickCategoryId,
        reason: 'без метки iOS покажет уведомление без кнопок',
      );
    });
  });
}
