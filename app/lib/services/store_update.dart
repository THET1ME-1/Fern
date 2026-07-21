import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../utils/app_version.dart';
import '../utils/build_config.dart';
import '../widgets/update_sheet.dart';
import 'update_service.dart';

/// Единая точка обновления приложения. Канал зависит от того, откуда приехала
/// сборка:
///
///  * **GitHub / Obtainium** — свой апдейтер: смотрим релизы на GitHub, качаем
///    APK, ставим (для этого и нужно разрешение на установку пакетов).
///  * **Google Play** — обновление приносит сам магазин через In-App Update.
///    Самообновление мимо Play там запрещено политикой, а разрешение на
///    установку пакетов из Play-сборки вырезано.
class StoreUpdate {
  const StoreUpdate._();

  static bool get _mobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Тихая проверка при запуске: предлагает обновиться, если версия новее.
  static Future<void> checkOnStart(BuildContext context) async {
    if (!_mobile) return;
    // На iOS ставить сборку мимо App Store приложение не может: IPA
    // подписывает тот, кто её сюда принёс (Sideloadly, AltStore), и обновляет
    // тем же способом. Предлагать «скачать и установить» там нечестно.
    if (Platform.isIOS) return;

    if (kPlayBuild) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability != UpdateAvailability.updateAvailable) {
          return;
        }
        // Гибкое обновление: качается в фоне, человек продолжает заниматься.
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      } catch (e) {
        debugPrint('Play in-app update failed: $e');
      }
      return;
    }

    final current = await appVersionName();
    if (current.isEmpty) return;
    final info = (await UpdateService.checkForUpdate(current)).info;
    if (!context.mounted || info == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) UpdateSheet.show(context, info, current);
    });
  }

  /// Ручная проверка (кнопка в настройках). Возвращает текст для снекбара или
  /// null, если показывать нечего (открылось меню обновления).
  static Future<String?> checkManually(BuildContext context) async {
    if (kPlayBuild) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability != UpdateAvailability.updateAvailable) {
          return tr('up_to_date');
        }
        await InAppUpdate.performImmediateUpdate();
        return null;
      } catch (e) {
        debugPrint('Play in-app update failed: $e');
        return tr('update_check_failed');
      }
    }

    final current = await appVersionName();
    final check = current.isEmpty
        ? const UpdateCheck.failed()
        : await UpdateService.checkForUpdate(current);
    if (!context.mounted) return null;
    final info = check.info;
    if (info != null) {
      // На iOS показываем страницу релиза: файл оттуда человек ставит тем же
      // способом, каким установил приложение.
      if (Platform.isIOS) {
        await launchUrl(
          Uri.parse(UpdateService.releasesPage),
          mode: LaunchMode.externalApplication,
        );
        return null;
      }
      await UpdateSheet.show(context, info, current);
      return null;
    }
    // «Не удалось проверить» и «всё свежее» — разные вещи.
    return check.failed ? tr('update_check_failed') : tr('up_to_date');
  }
}
