import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Очень лёгкий рендер Markdown без сторонних пакетов — ровно для заметок к
/// релизу: заголовки (`#`/`##`/`###`), списки (`- `/`* `), жирный (`**…**`),
/// горизонтальная линия (`---`) и пустые строки как отступы. Эмодзи проходят
/// как обычный текст.
class MarkdownLite extends StatelessWidget {
  final String text;
  final Color color;
  final Color headingColor;
  final double fontSize;

  const MarkdownLite({
    super.key,
    required this.text,
    required this.color,
    required this.headingColor,
    this.fontSize = 13.5,
  });

  TextStyle get _body => TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: fontSize,
        height: 1.4,
        color: color,
      );

  List<TextSpan> _inline(String s, TextStyle base) {
    final spans = <TextSpan>[];
    final parts = s.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      final bold = i.isOdd; // текст между парами ** — жирный
      spans.add(TextSpan(
        text: parts[i],
        style: bold ? base.copyWith(fontWeight: FontWeight.w800) : base,
      ));
    }
    return spans;
  }

  Widget _heading(String s, double size) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: RichText(
          text: TextSpan(
            children: _inline(
              s,
              TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: size,
                height: 1.25,
                color: headingColor,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final lines = text.replaceAll('\r\n', '\n').split('\n');

    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }
      if (t.startsWith('### ')) {
        blocks.add(_heading(t.substring(4), fontSize + 1.5));
        continue;
      }
      if (t.startsWith('## ')) {
        blocks.add(_heading(t.substring(3), fontSize + 3));
        continue;
      }
      if (t.startsWith('# ')) {
        blocks.add(_heading(t.substring(2), fontSize + 5));
        continue;
      }
      if (t == '---' || t == '***' || t == '___') {
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: color.withValues(alpha: 0.3)),
        ));
        continue;
      }
      if (t.startsWith('- ') || t.startsWith('* ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: _body),
              Expanded(
                child: RichText(
                  text: TextSpan(children: _inline(t.substring(2), _body)),
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(text: TextSpan(children: _inline(t, _body))),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}
