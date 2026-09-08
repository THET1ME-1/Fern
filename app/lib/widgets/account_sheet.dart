import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/fern_account.dart';
import '../theme/app_theme.dart';

/// Вход в аккаунт Fern.
///
/// Открывается только оттуда, где без аккаунта не обойтись — с подписки.
/// Человек, который не платит, этого листа не видит никогда.
///
/// Лист снизу, а не отдельный экран: подписку оформляют, не уходя с того
/// места, где она понадобилась.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  /// Возвращает `true`, если человек вошёл.
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const AccountSheet(),
    );
    return result ?? false;
  }

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _signUp = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Что сказать человеку про исход. Ошибки названы своими именами: «не
  /// получилось» отправляет его гадать, а «пароль не подошёл» — вспоминать.
  String _message(AuthOutcome outcome) => switch (outcome) {
        AuthOutcome.wrongPassword => tr('sub_err_wrong'),
        AuthOutcome.emailTaken => tr('sub_err_taken'),
        AuthOutcome.invalidEmail => tr('sub_err_email'),
        AuthOutcome.weakPassword => tr('sub_err_weak'),
        AuthOutcome.network => tr('sub_err_net'),
        AuthOutcome.cancelled => '',
        _ => tr('sub_err_failed'),
      };

  Future<void> _run(Future<AuthOutcome> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final outcome = await action();
    if (!mounted) return;
    if (outcome == AuthOutcome.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = _message(outcome);
    });
  }

  Future<void> _forgot() async {
    final ok =
        await FernAccount.instance.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _error = ok ? null : tr('sub_err_email');
      _notice = ok ? tr('sub_reset_sent') : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _signUp ? tr('sub_signup_title') : tr('sub_signin_title'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  height: 1.25,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('sub_signin_lead'),
                style: TextStyle(
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: tr('sub_email'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: tr('sub_password'),
                  helperText: _signUp ? tr('sub_password_hint') : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 10),
                Text(_notice!, style: TextStyle(color: scheme.primary)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => _signUp
                        ? FernAccount.instance
                            .signUp(_email.text, _password.text)
                        : FernAccount.instance
                            .signIn(_email.text, _password.text)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_signUp ? tr('sub_signup') : tr('sub_signin')),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _signUp = !_signUp;
                          _error = null;
                        }),
                child: Text(_signUp ? tr('sub_have_account') : tr('sub_no_account')),
              ),
              if (!_signUp)
                TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: Text(tr('sub_forgot')),
                ),
              Row(
                children: [
                  Expanded(child: Divider(color: scheme.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      tr('sub_or'),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  Expanded(child: Divider(color: scheme.outlineVariant)),
                ],
              ),
              const SizedBox(height: 10),
              // Кнопки провайдеров — «таблетки» той же высоты, что и главная:
              // выбор способа входа не должен выглядеть второсортным.
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _run(FernAccount.instance.signInWithGoogle),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: Text(tr('sub_google')),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _run(FernAccount.instance.signInWithApple),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                ),
                child: Text(tr('sub_apple')),
              ),
              const SizedBox(height: 14),
              Text(
                tr('sub_account_fine'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
