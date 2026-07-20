import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/word_card.dart';
import '../services/deck_repository.dart';
import '../services/word_links.dart';
import '../theme/app_theme.dart';

/// Секция «Связи» карточки: синонимы, антонимы, однокоренные.
///
/// Часть связей вычисляется (помечена точкой), часть проставлена руками. Связь
/// всегда двусторонняя, поэтому правки пишутся в репозиторий сразу — иначе
/// вторая карточка осталась бы без своей половины.
class WordLinksSection extends StatefulWidget {
  final WordCard card;
  final String languageCode;

  const WordLinksSection({
    super.key,
    required this.card,
    required this.languageCode,
  });

  @override
  State<WordLinksSection> createState() => _WordLinksSectionState();
}

class _WordLinksSectionState extends State<WordLinksSection> {
  final DeckRepository _repo = DeckRepository.instance;
  List<WordCard> _pool = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPool();
  }

  Future<void> _loadPool() async {
    await _repo.loadCards();
    if (!mounted) return;
    setState(() {
      _pool = _repo
          .cardsByFrontForLanguage(widget.languageCode)
          .values
          .toList();
      _loading = false;
    });
  }

  Color _kindColor(LinkKind kind, ColorScheme scheme) => switch (kind) {
        LinkKind.synonym => scheme.secondaryContainer,
        LinkKind.antonym => scheme.errorContainer,
        LinkKind.root => scheme.tertiaryContainer,
      };

  Color _kindTextColor(LinkKind kind, ColorScheme scheme) => switch (kind) {
        LinkKind.synonym => scheme.onSecondaryContainer,
        LinkKind.antonym => scheme.onErrorContainer,
        LinkKind.root => scheme.onTertiaryContainer,
      };

  /// Лист добавления: сперва тип связи, потом слово из того же языка.
  Future<void> _addLink() async {
    final kind = await showModalBottomSheet<LinkKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in LinkKind.values)
              ListTile(
                leading: Icon(switch (k) {
                  LinkKind.synonym => Icons.swap_horiz_rounded,
                  LinkKind.antonym => Icons.compare_arrows_rounded,
                  LinkKind.root => Icons.account_tree_rounded,
                }),
                title: Text(tr(k.titleKey)),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    final target = await showModalBottomSheet<WordCard>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WordPickerSheet(
        cards: _pool.where((c) => c.id != widget.card.id).toList(),
        title: tr(kind.titleKey),
      ),
    );
    if (target == null) return;

    WordLinks.connect(widget.card, target, kind);
    await _repo.upsertCard(widget.card);
    await _repo.upsertCard(target);
    if (mounted) setState(() {});
  }

  Future<void> _removeLink(WordLink link) async {
    WordLinks.disconnect(widget.card, link.card);
    await _repo.upsertCard(widget.card);
    await _repo.upsertCard(link.card);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const SizedBox.shrink();

    final grouped =
        WordLinks.grouped(widget.card, _pool, widget.languageCode);
    final autoCount = grouped.values
        .expand((l) => l)
        .where((l) => l.auto)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              tr('links_section'),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addLink,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr('link_add')),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (grouped.isEmpty)
          Text(
            tr('links_empty'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final kind in LinkKind.values)
            if (grouped[kind] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr(kind.titleKey),
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12,
                            color: scheme.outline,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final link in grouped[kind]!)
                            _linkChip(link, scheme),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        if (autoCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              trf('links_auto_note', {'n': '$autoCount'}),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 11.5,
                height: 1.4,
                color: scheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _linkChip(WordLink link, ColorScheme scheme) {
    final fg = _kindTextColor(link.kind, scheme);
    return Material(
      color: _kindColor(link.kind, scheme),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: link.auto ? null : () => _removeLink(link),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (link.auto) ...[
                Icon(Icons.auto_awesome_rounded, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                link.card.front,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (!link.auto) ...[
                const SizedBox(width: 5),
                Icon(Icons.close_rounded, size: 14, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Выбор карточки из того же языка — с поиском, потому что словарь большой.
class _WordPickerSheet extends StatefulWidget {
  final List<WordCard> cards;
  final String title;

  const _WordPickerSheet({required this.cards, required this.title});

  @override
  State<_WordPickerSheet> createState() => _WordPickerSheetState();
}

class _WordPickerSheetState extends State<_WordPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.cards
        : widget.cards
            .where((c) =>
                c.front.toLowerCase().contains(q) ||
                c.back.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    labelText: widget.title,
                    hintText: tr('search_cards'),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(tr('links_no_words')))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(list[i].front),
                          subtitle: Text(list[i].back),
                          onTap: () => Navigator.pop(context, list[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
