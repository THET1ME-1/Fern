import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../services/translation/endpoint_provider.dart';
import '../services/translation/translation_manager.dart';
import '../services/translation/translation_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';

/// Экран «Перевод и модели»: выбор активного провайдера перевода и управление
/// своими серверами (Ollama / OpenAI-совм. / LibreTranslate / DeepL).
///
/// ML Kit остаётся дефолтным лёгким офлайн-fallback; всё остальное —
/// расширяемый слой поверх него.
class ProvidersScreen extends StatelessWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mgr = TranslationManager.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('providers_title'))),
      body: ListenableBuilder(
        listenable: mgr,
        builder: (context, _) {
          final providers = mgr.providers;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Reveal(child: _intro(scheme)),
              const SizedBox(height: 8),
              _sectionTitle(tr('providers_active'), scheme),
              for (var i = 0; i < providers.length; i++)
                Reveal(
                  delay: Duration(milliseconds: 40 * i),
                  child: _ProviderCard(
                    provider: providers[i],
                    selected: providers[i].id == mgr.activeId,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      mgr.setActive(providers[i].id);
                    },
                    onEdit: _isEndpoint(mgr, providers[i].id)
                        ? () => _openForm(
                              context,
                              existing: _endpointOf(mgr, providers[i].id),
                            )
                        : null,
                    onDelete: _isEndpoint(mgr, providers[i].id)
                        ? () => mgr.removeEndpoint(providers[i].id)
                        : null,
                  ),
                ),
              const SizedBox(height: 20),
              _sectionTitle(tr('providers_servers'), scheme),
              Reveal(
                child: PressableScale(
                  child: Material(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: Icon(Icons.dns_rounded,
                          color: scheme.onPrimaryContainer),
                      title: Text(
                        tr('providers_add_server'),
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(Icons.add_rounded,
                          color: scheme.onPrimaryContainer),
                      onTap: () => _openForm(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr('providers_hint'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isEndpoint(TranslationManager mgr, String id) =>
      mgr.endpoints.any((e) => e.id == id);

  EndpointConfig? _endpointOf(TranslationManager mgr, String id) {
    for (final e in mgr.endpoints) {
      if (e.id == id) return e;
    }
    return null;
  }

  Widget _intro(ColorScheme scheme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(Icons.translate_rounded, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                tr('providers_intro'),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  height: 1.35,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: scheme.primary,
          ),
        ),
      );

  Future<void> _openForm(BuildContext context, {EndpointConfig? existing}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ServerFormSheet(existing: existing),
    );
  }
}

/// Карточка провайдера с индикатором выбора и (для серверов) меню редактирования.
class _ProviderCard extends StatelessWidget {
  final TranslationProvider provider;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ProviderCard({
    required this.provider,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, badge) = switch (provider.kindLabel) {
      'offline' => (Icons.offline_bolt_rounded, tr('provider_offline')),
      'online' => (Icons.cloud_rounded, tr('provider_online')),
      'endpoint' => (Icons.dns_rounded, tr('provider_endpoint')),
      _ => (Icons.memory_rounded, tr('provider_local')),
    };
    final sub = switch (provider.id) {
      'mlkit' => tr('provider_mlkit_sub'),
      'google' => tr('provider_google_sub'),
      _ => badge,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: scheme.onSurfaceVariant),
                      onSelected: (v) {
                        if (v == 'edit') onEdit?.call();
                        if (v == 'delete') onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(tr('edit'))),
                        PopupMenuItem(
                            value: 'delete', child: Text(tr('delete'))),
                      ],
                    )
                  else
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: selected ? 1 : 0,
                      child: Icon(Icons.check_circle_rounded,
                          color: scheme.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Форма добавления/редактирования своего сервера перевода.
class _ServerFormSheet extends StatefulWidget {
  final EndpointConfig? existing;
  const _ServerFormSheet({this.existing});

  @override
  State<_ServerFormSheet> createState() => _ServerFormSheetState();
}

class _ServerFormSheetState extends State<_ServerFormSheet> {
  late EndpointKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? EndpointKind.ollama;
    _name = TextEditingController(text: e?.name ?? '');
    _url = TextEditingController(text: e?.baseUrl ?? '');
    _key = TextEditingController(text: e?.apiKey ?? '');
    _model = TextEditingController(text: e?.model ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  EndpointConfig _build() {
    final id =
        widget.existing?.id ?? 'ep_${DateTime.now().microsecondsSinceEpoch}';
    final name = _name.text.trim().isEmpty ? _kind.label : _name.text.trim();
    return EndpointConfig(
      id: id,
      name: name,
      kind: _kind,
      baseUrl: _url.text.trim(),
      apiKey: _key.text.trim(),
      model: _model.text.trim(),
    );
  }

  Future<void> _test() async {
    if (_url.text.trim().isEmpty && _kind != EndpointKind.deepl) {
      setState(() {
        _testOk = false;
        _testMsg = tr('field_required');
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    final provider = EndpointProvider(_build());
    final target = LocaleController.instance.code == 'en'
        ? 'ru'
        : LocaleController.instance.code;
    final res = await provider.translate('hello', 'en', target);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = res != null;
      _testMsg = res != null
          ? trf('server_test_ok', {'res': res.primary})
          : tr('server_test_fail');
    });
  }

  void _save() {
    if (_url.text.trim().isEmpty && _kind != EndpointKind.deepl) {
      setState(() {
        _testOk = false;
        _testMsg = tr('field_required');
      });
      return;
    }
    HapticFeedback.selectionClick();
    final cfg = _build();
    final mgr = TranslationManager.instance;
    if (widget.existing != null) {
      mgr.updateEndpoint(cfg);
    } else {
      mgr.addEndpoint(cfg);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr('providers_edit_server'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              // Тип сервера.
              Text(tr('server_kind'),
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in EndpointKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() {
                        _kind = k;
                        _testMsg = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: tr('server_name'),
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('server_url'),
                  hintText: _kind == EndpointKind.ollama
                      ? 'http://192.168.1.10:11434'
                      : 'https://…',
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
              ),
              if (_kind.needsKey) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr('server_key'),
                    prefixIcon: const Icon(Icons.key_rounded),
                  ),
                ),
              ],
              if (_kind.needsModel) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr('server_model'),
                    hintText: _kind == EndpointKind.ollama
                        ? 'llama3.1'
                        : 'gpt-4o-mini',
                    prefixIcon: const Icon(Icons.memory_rounded),
                  ),
                ),
              ],
              if (_testMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testOk
                        ? scheme.primaryContainer
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testOk
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 18,
                        color: _testOk
                            ? scheme.onPrimaryContainer
                            : scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testMsg!,
                          style: TextStyle(
                            fontSize: 13,
                            color: _testOk
                                ? scheme.onPrimaryContainer
                                : scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded),
                      label: Text(tr('server_test')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(tr('save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
