import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'models/feedback.dart';
import 'services/feedback_service.dart';
import 'theme/app_theme.dart';

/// «Сообщить о проблеме»: обращение уходит на наш сервер прямо из приложения.
///
/// Google Play требует, чтобы о проблеме можно было сообщить, не выходя из
/// приложения: Togetherly отклонили 11.11.2026, потому что поддержка
/// открывала почту и Telegram. Отсюда правило экрана: никаких внешних
/// переходов. Раскладка та же, что в Togetherly.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({
    super.key,
    required this.version,
    this.accountEmail = '',
    this.send,
  });

  /// Версия приложения: без неё разбирать ошибку вслепую.
  final String version;

  /// Почта аккаунта: на неё придёт ответ. Пустая — человек не вошёл, и почту
  /// он может вписать сам.
  final String accountEmail;

  /// Отправка; в тесте подменяется, в приложении — [FeedbackService].
  final Future<FeedbackSent> Function(FeedbackDraft draft)? send;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _text = TextEditingController();
  final _email = TextEditingController();
  FeedbackKind _kind = FeedbackKind.bug;
  bool _sending = false;
  bool _sent = false;

  /// Куда обещаем ответ после отправки; пусто — почты нет.
  String _replyTo = '';

  /// Что показать под полем после отказа.
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_clearError);
    _email.addListener(_clearError);
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  void dispose() {
    _text.dispose();
    _email.dispose();
    super.dispose();
  }

  static String _labelOf(FeedbackKind kind) => switch (kind) {
        FeedbackKind.bug => tr('fb_kind_bug'),
        FeedbackKind.idea => tr('fb_kind_idea'),
        FeedbackKind.payment => tr('fb_kind_payment'),
        FeedbackKind.other => tr('fb_kind_other'),
      };

  static IconData _iconOf(FeedbackKind kind) => switch (kind) {
        FeedbackKind.bug => Icons.bug_report_rounded,
        FeedbackKind.idea => Icons.lightbulb_rounded,
        FeedbackKind.payment => Icons.payments_rounded,
        FeedbackKind.other => Icons.chat_bubble_rounded,
      };

  static String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (!feedbackReady(_text.text)) {
      setState(() => _error = tr('fb_too_short'));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final email = widget.accountEmail.isNotEmpty
        ? widget.accountEmail
        : _email.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    final draft = FeedbackDraft(
      kind: _kind,
      text: _text.text.trim(),
      email: widget.accountEmail.isNotEmpty ? '' : email,
      app: widget.version,
      platform: _platform(),
      lang: LocaleController.instance.code,
    );
    final send = widget.send ?? const FeedbackService().send;
    final result = await send(draft);
    if (!mounted) return;
    setState(() {
      _sending = false;
      switch (result) {
        case FeedbackSent.ok:
          _sent = true;
          _replyTo = email;
        case FeedbackSent.tooMany:
          _error = tr('fb_err_too_many');
        case FeedbackSent.badEmail:
          _error = tr('fb_err_email');
        case FeedbackSent.failed:
          _error = tr('fb_err_failed');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          tr('fb_title'),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
      body: SafeArea(child: _sent ? _done(cs) : _form(cs)),
    );
  }

  TextStyle _body(ColorScheme cs, {double size = 15, Color? color}) =>
      TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: size,
        height: 1.35,
        color: color ?? cs.onSurfaceVariant,
      );

  InputDecoration _decoration(ColorScheme cs, String hint,
          {String? errorText}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: _body(cs, size: 16),
        errorText: errorText,
        errorMaxLines: 3,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      );

  Widget _form(ColorScheme cs) {
    // Кнопка закреплена под списком: на невысоком экране с открытой
    // клавиатурой она иначе уезжала за край, и отправить было нечем.
    return Column(
      children: [
        Expanded(child: _fields(cs)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const Key('feedback_send'),
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              child: _sending
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      tr('fb_send'),
                      style: const TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fields(ColorScheme cs) {
    final signedIn = widget.accountEmail.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Text(tr('fb_intro'), style: _body(cs)),
        const SizedBox(height: 16),
        _kinds(cs),
        const SizedBox(height: 16),
        TextField(
          key: const Key('feedback_text'),
          controller: _text,
          enabled: !_sending,
          minLines: 6,
          maxLines: 12,
          maxLength: kFeedbackMax,
          textCapitalization: TextCapitalization.sentences,
          style: _body(cs, size: 16, color: cs.onSurface),
          decoration: _decoration(cs, tr('fb_hint'), errorText: _error),
        ),
        const SizedBox(height: 4),
        if (signedIn)
          Text(trf('fb_reply_to', {'email': widget.accountEmail}),
              style: _body(cs, size: 13))
        else ...[
          TextField(
            key: const Key('feedback_email'),
            controller: _email,
            enabled: !_sending,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            style: _body(cs, size: 16, color: cs.onSurface),
            decoration: _decoration(cs, tr('fb_email_hint')),
          ),
          const SizedBox(height: 6),
          Text(tr('fb_email_note'), style: _body(cs, size: 13)),
        ],
      ],
    );
  }

  /// Виды обращения парами: чипы в строку рвались по-разному на каждом
  /// языке, а плитка держит подпись в две строки.
  Widget _kinds(ColorScheme cs) {
    Widget pair(FeedbackKind left, FeedbackKind right) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _kindTile(cs, left)),
              const SizedBox(width: 8),
              Expanded(child: _kindTile(cs, right)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(FeedbackKind.bug, FeedbackKind.idea),
        const SizedBox(height: 8),
        pair(FeedbackKind.payment, FeedbackKind.other),
      ],
    );
  }

  Widget _kindTile(ColorScheme cs, FeedbackKind kind) {
    final selected = _kind == kind;
    final ink = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Material(
      key: Key('feedback_kind_${kind.wire}'),
      color: selected ? cs.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? Colors.transparent : cs.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _sending ? null : () => setState(() => _kind = kind),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(_iconOf(kind), size: 18, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _labelOf(kind),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _done(ColorScheme cs) {
    final reply = _replyTo.isEmpty
        ? tr('fb_sent_no_mail')
        : trf('fb_sent_body', {'email': _replyTo});
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  size: 44, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('fb_sent_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(reply, textAlign: TextAlign.center, style: _body(cs)),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(context).maybePop(),
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              child: Text(
                tr('fb_done'),
                style: const TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
