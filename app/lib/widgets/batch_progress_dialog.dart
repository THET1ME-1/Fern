import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Прогресс пакетного добавления слов (книга / видео / OCR — один и тот же
/// диалог).
///
/// Системная «Назад» здесь означает отмену, а не закрытие: раньше диалог
/// закрывался, цикл продолжал работать, а финальный `pop()` сносил уже сам
/// экран книги — человека без объяснений выбрасывало в библиотеку.
class BatchProgressDialog extends StatelessWidget {
  final int total;
  final ValueNotifier<int> progress;
  final VoidCallback onCancel;

  const BatchProgressDialog({
    super.key,
    required this.total,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onCancel();
      },
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Text(trf('batch_adding', {'i': done, 'n': total})),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: onCancel, child: Text(tr('cancel'))),
        ],
      ),
    );
  }
}
