import 'package:flutter/material.dart';

import 'main.dart' show startFern;
import 'startup.dart';
import 'services/backup_service.dart';
import 'services/deck_repository.dart';

/// Аварийный экран: показывается, когда приложение не смогло запуститься
/// (обычно — повреждённый файл БД или нет места на диске).
///
/// Намеренно ни от чего не зависит: ни от темы, ни от загруженной локали, ни от
/// репозитория — всё это в момент отказа может быть не инициализировано. Язык
/// берём из системной локали, тексты держим прямо здесь.
class RecoveryApp extends StatelessWidget {
  final StartupError failure;
  const RecoveryApp({super.key, required this.failure});

  @override
  Widget build(BuildContext context) {
    final ru = WidgetsBinding.instance.platformDispatcher.locale.languageCode
        .startsWith('ru');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D5B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _RecoveryScreen(failure: failure, ru: ru),
    );
  }
}

class _RecoveryScreen extends StatefulWidget {
  final StartupError failure;
  final bool ru;
  const _RecoveryScreen({required this.failure, required this.ru});

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  bool _busy = false;
  String? _failure;

  bool get _ru => widget.ru;
  bool get _storage => widget.failure.isStorage;

  /// Повторяет запуск, ничего не трогая: сбой мог быть разовым (плагин не
  /// поднялся, файл был занят).
  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await startFern();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = '$e';
      });
    }
  }

  /// Чинит хранилище и повторяет обычный запуск. `restoreBackup` — вернуть
  /// слова из последней авто-копии (она пишется раз в сутки и лежит отдельным
  /// файлом, поэтому переживает поломку БД).
  Future<void> _recover({required bool restoreBackup}) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await DeckRepository.instance.recoverFromCorruptedDatabase();
      if (restoreBackup) {
        final path = await BackupService.autoBackupPath();
        if (path != null) await BackupService.restoreFile(path);
      }
      await startFern();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _storage
                      ? Icons.healing_rounded
                      : Icons.error_outline_rounded,
                  size: 56,
                  color: t.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  _storage
                      ? (_ru
                          ? 'Не удалось открыть данные'
                          : 'Cannot open your data')
                      : (_ru
                          ? 'Приложение не запустилось'
                          : 'Fern could not start'),
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _storage
                      ? (_ru
                          ? 'Хранилище словаря повреждено. Можно вернуть слова из последней резервной копии — Fern делает её автоматически раз в сутки.'
                          : 'The word storage is damaged. You can restore your words from the latest automatic backup — Fern makes one every day.')
                      : (_ru
                          ? 'Не поднялось: ${widget.failure.step.title(ru: true)}. Словарь при этом цел — трогать его незачем.'
                          : 'Failed to load: ${widget.failure.step.title(ru: false)}. Your words are intact.'),
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                // Кнопки, уводящие базу в карантин, показываем только когда
                // сломана именно база. В остальных случаях предлагаем повтор:
                // словарь цел, и стирать его не за что.
                else if (_storage) ...[
                  FilledButton.icon(
                    onPressed: () => _recover(restoreBackup: true),
                    icon: const Icon(Icons.settings_backup_restore_rounded),
                    label: Text(
                      _ru
                          ? 'Восстановить из копии'
                          : 'Restore from backup',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _recover(restoreBackup: false),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(_ru ? 'Начать заново' : 'Start over'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_ru ? 'Повторить' : 'Retry'),
                  ),
                if (_failure != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _storage
                        ? (_ru
                            ? 'Восстановить не вышло. Переустановите приложение.'
                            : 'Recovery failed. Please reinstall the app.')
                        : (_ru
                            ? 'Снова не вышло: $_failure'
                            : 'Failed again: $_failure'),
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Техническая причина: её можно переслать в issue целиком.
                SelectableText(
                  '${widget.failure.cause}',
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant.withValues(alpha: .6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
