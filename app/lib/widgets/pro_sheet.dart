import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/billing_service.dart';
import '../services/license_service.dart';
import '../services/pro.dart';
import '../utils/build_config.dart';

/// Предложение купить Fern Pro.
///
/// Кассы две, и какая работает — решает канал сборки. В магазинной сборке
/// покупка идёт через Play, в сборке с GitHub — ключом из бота: Google не
/// принимает платежи в России, а бот с оплатой звёздами Telegram принимает.
/// Правила Play запрещают уводить на внешнюю оплату изнутри магазинной сборки,
/// поэтому ветки именно две, а не одна с двумя кнопками.
class ProSheet extends StatefulWidget {
  /// С какой возможности человек сюда пришёл — с неё и начинаем разговор.
  final ProFeature? feature;

  const ProSheet({super.key, this.feature});

  static Future<void> show(BuildContext context, {ProFeature? feature}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ProSheet(feature: feature),
    );
  }

  @override
  State<ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends State<ProSheet> {
  bool _busy = false;
  bool _keyMode = false;
  String? _error;
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _buy() async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    final started = await BillingService.instance.buy();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = started ? null : tr('pro_store_unavailable');
    });
    // Магазин закрывает лист сам, когда покупка дошла: слушаем состояние.
    if (started && Pro.active) Navigator.of(context).maybePop();
  }

  Future<void> _applyKey() async {
    final raw = _keyController.text.trim();
    if (raw.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final info = await LicenseService.instance.apply(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = info == null ? tr('pro_key_bad') : null;
    });
    if (info != null) {
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('pro_key_ok'))),
      );
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _keyController.text = text;
    await _applyKey();
  }

  Future<void> _openBot() async {
    final uri = Uri.parse('https://t.me/FernProBot');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('open_link_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = BillingService.instance.price;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 26),
                const SizedBox(width: 10),
                Text(
                  tr('pro_title'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.feature == ProFeature.deckImport
                  ? tr('pro_lead_import')
                  : tr('pro_lead_library'),
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 18),
            for (final line in [
              tr('pro_point_books'),
              tr('pro_point_video'),
              tr('pro_point_import'),
              tr('pro_point_forever'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 19, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(line, style: const TextStyle(height: 1.35))),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 14),
            if (kPlayBuild) ..._storeButtons(price) else ..._keyButtons(),
          ],
        ),
      ),
    );
  }

  List<Widget> _storeButtons(String? price) => [
        FilledButton(
          onPressed: _busy ? null : _buy,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: Text(price == null
              ? tr('pro_buy')
              : trf('pro_buy_price', {'price': price})),
        ),
        TextButton(
          onPressed: _busy ? null : () => BillingService.instance.restore(),
          child: Text(tr('pro_restore')),
        ),
      ];

  List<Widget> _keyButtons() => [
        if (_keyMode) ...[
          TextField(
            controller: _keyController,
            maxLines: 3,
            minLines: 1,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: tr('pro_key_label'),
              hintText: 'FERN…',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _applyKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(tr('pro_key_apply')),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste_rounded),
                tooltip: tr('pro_key_paste'),
              ),
            ],
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: _busy ? null : _openBot,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.send_rounded),
            label: Text(tr('pro_open_bot')),
          ),
          TextButton(
            onPressed: () => setState(() => _keyMode = true),
            child: Text(tr('pro_have_key')),
          ),
        ],
      ];
}

/// Пропускает дальше или показывает предложение купить.
///
/// Экраны зовут это перед действием и не прячут кнопки: спрятанная кнопка не
/// объясняет, что приложение вообще умеет, и человек не узнает, за что платить.
Future<bool> requirePro(BuildContext context, ProFeature feature) async {
  if (await Pro.allows(feature)) return true;
  if (!context.mounted) return false;
  await ProSheet.show(context, feature: feature);
  return Pro.allows(feature);
}
