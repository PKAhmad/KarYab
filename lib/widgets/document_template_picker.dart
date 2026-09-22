import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_template.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CV template picker — a bottom sheet shown before CV generation so the user
// can pick one of the 5 visual templates. Persists the choice to
// SharedPreferences under whatever key the caller passes in — this picker is
// reused by multiple independent flows (e.g. the regular CV screen and,
// separately, Ausbildung), each of which MUST use its own distinct key so
// their template choices never share state.
//
// showAnschreibenTemplatePicker() below mirrors this exact pattern for the 5
// Anschreiben (Cover Letter) templates — kept as a parallel set of
// functions/widgets (not a generic rewrite of the above) since the two enums
// aren't interchangeable and every other private widget in this codebase is
// already duplicated per-context rather than shared through a generic type.
// ─────────────────────────────────────────────────────────────────────────────

Future<DocumentTemplate> loadSelectedDocumentTemplate(String prefsKey) async {
  final prefs = await SharedPreferences.getInstance();
  return DocumentTemplateInfo.fromStorageKey(prefs.getString(prefsKey));
}

Future<void> saveSelectedDocumentTemplate(
    String prefsKey, DocumentTemplate template) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsKey, template.storageKey);
}

/// Shows the template picker bottom sheet and returns the chosen template.
/// Returns [current] unchanged if the sheet is dismissed without a pick.
Future<DocumentTemplate> showDocumentTemplatePicker(
  BuildContext context, {
  required DocumentTemplate current,
}) async {
  final result = await showModalBottomSheet<DocumentTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DocumentTemplateSheet(initial: current),
  );
  return result ?? current;
}

class _DocumentTemplateSheet extends StatefulWidget {
  final DocumentTemplate initial;
  const _DocumentTemplateSheet({required this.initial});

  @override
  State<_DocumentTemplateSheet> createState() =>
      _DocumentTemplateSheetState();
}

class _DocumentTemplateSheetState extends State<_DocumentTemplateSheet> {
  static const Color _navy = Color(0xFF091733);
  static const Color _muted = Color(0xFF65738A);

  late DocumentTemplate _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    // Bug fix: this content used to be a plain, non-scrolling Column. On
    // shorter viewports (smaller/older phones, larger accessibility font
    // scaling, landscape) it could overflow far enough that the "Use this
    // Template" button ended up outside the tappable area entirely. When a
    // user couldn't reach it, dismissing the sheet any other way (tap
    // outside, back gesture) made showDocumentTemplatePicker() fall back to
    // the *previous* template (see showDocumentTemplatePicker's `?? current`
    // below), silently discarding whatever card they'd tapped — the exact
    // "I picked a different template but the download didn't change" bug.
    // Constraining height + wrapping in a scroll view guarantees the button
    // is always reachable regardless of screen size.
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D9E6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose a CV Template',
              style: TextStyle(
                  color: _navy, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            const Text(
              'You can change this anytime',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            // 3 columns x 2 rows fits all 5 templates without scrolling
            // (tap-to-select below also removed the confirm button, which on
            // its own freed most of the room this needed).
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.8,
              children: DocumentTemplate.values
                  .map((t) => _TemplateCard(
                        template: t,
                        selected: _selected == t,
                        // Tap-to-select: highlight immediately, then close
                        // the sheet with this template after a brief beat so
                        // the highlight is actually visible - no separate
                        // confirm button anymore.
                        onTap: () {
                          setState(() => _selected = t);
                          Future.delayed(const Duration(milliseconds: 180), () {
                            if (mounted) Navigator.pop(context, t);
                          });
                        },
                      ))
                  .toList(),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final DocumentTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _green : Colors.white.withOpacity(0.9),
            width: selected ? 2.2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _green.withOpacity(0.28)
                  : Colors.black.withOpacity(0.08),
              blurRadius: selected ? 18 : 10,
              spreadRadius: selected ? 1 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                template.thumbnailAsset,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stack) =>
                    _MissingThumbnail(label: template.displayName),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      template.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.check_circle_rounded,
                        color: _green, size: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder shown in place of a template's thumbnail PNG when that asset
// file doesn't exist yet (e.g. the 5 new Anschreiben templates and the new
// CV "Braun Icon-Set" template added alongside this picker update - their
// thumbnailAsset paths are wired up but the actual design PNGs still need to
// be produced and dropped into assets/templates/thumbnails/). Renders a
// neutral icon + template name instead of Flutter's default broken-image box
// so the picker stays usable in the meantime.
class _MissingThumbnail extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);

  final String label;
  const _MissingThumbnail({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F3F8),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined, color: _navy, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _navy,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Anschreiben template picker — same shape as the CV picker above, over
// AnschreibenTemplate instead of DocumentTemplate.
// ─────────────────────────────────────────────────────────────────────────────

Future<AnschreibenTemplate> loadSelectedAnschreibenTemplate(
    String prefsKey) async {
  final prefs = await SharedPreferences.getInstance();
  return AnschreibenTemplateInfo.fromStorageKey(prefs.getString(prefsKey));
}

Future<void> saveSelectedAnschreibenTemplate(
    String prefsKey, AnschreibenTemplate template) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsKey, template.storageKey);
}

/// Shows the Anschreiben template picker bottom sheet and returns the chosen
/// template. Returns [current] unchanged if the sheet is dismissed without a
/// pick.
Future<AnschreibenTemplate> showAnschreibenTemplatePicker(
  BuildContext context, {
  required AnschreibenTemplate current,
}) async {
  final result = await showModalBottomSheet<AnschreibenTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnschreibenTemplateSheet(initial: current),
  );
  return result ?? current;
}

class _AnschreibenTemplateSheet extends StatefulWidget {
  final AnschreibenTemplate initial;
  const _AnschreibenTemplateSheet({required this.initial});

  @override
  State<_AnschreibenTemplateSheet> createState() =>
      _AnschreibenTemplateSheetState();
}

class _AnschreibenTemplateSheetState extends State<_AnschreibenTemplateSheet> {
  static const Color _navy = Color(0xFF091733);
  static const Color _muted = Color(0xFF65738A);

  late AnschreibenTemplate _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    // Same overflow-safety fix as _DocumentTemplateSheet above (constrained
    // height + scroll view, so the "Use this Template" button is always
    // reachable regardless of screen size).
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose an Anschreiben Template',
                style: TextStyle(
                    color: _navy, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              const Text(
                'You can change this anytime',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              // 3 columns x 2 rows fits all 5 templates without scrolling
              // (tap-to-select below also removed the confirm button, which
              // on its own freed most of the room this needed).
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.8,
                children: AnschreibenTemplate.values
                    .map((t) => _AnschreibenTemplateCard(
                          template: t,
                          selected: _selected == t,
                          // Tap-to-select: highlight immediately, then close
                          // the sheet with this template after a brief beat
                          // so the highlight is actually visible - no
                          // separate confirm button anymore.
                          onTap: () {
                            setState(() => _selected = t);
                            Future.delayed(const Duration(milliseconds: 180), () {
                              if (mounted) Navigator.pop(context, t);
                            });
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnschreibenTemplateCard extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final AnschreibenTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _AnschreibenTemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _green : Colors.white.withOpacity(0.9),
            width: selected ? 2.2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _green.withOpacity(0.28)
                  : Colors.black.withOpacity(0.08),
              blurRadius: selected ? 18 : 10,
              spreadRadius: selected ? 1 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                template.thumbnailAsset,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stack) =>
                    _MissingThumbnail(label: template.displayName),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      template.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.check_circle_rounded,
                        color: _green, size: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deckblatt template picker — same shape as the pickers above, over
// DeckblattTemplate. Only 2 designs exist so far, so a 2-column grid (one
// row) fits both without the 3-column layout the other two pickers need for
// 5 items.
// ─────────────────────────────────────────────────────────────────────────────

Future<DeckblattTemplate> loadSelectedDeckblattTemplate(String prefsKey) async {
  final prefs = await SharedPreferences.getInstance();
  return DeckblattTemplateInfo.fromStorageKey(prefs.getString(prefsKey));
}

Future<void> saveSelectedDeckblattTemplate(
    String prefsKey, DeckblattTemplate template) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsKey, template.storageKey);
}

/// Shows the Deckblatt template picker bottom sheet and returns the chosen
/// template. Returns [current] unchanged if the sheet is dismissed without a
/// pick.
Future<DeckblattTemplate> showDeckblattTemplatePicker(
  BuildContext context, {
  required DeckblattTemplate current,
}) async {
  final result = await showModalBottomSheet<DeckblattTemplate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeckblattTemplateSheet(initial: current),
  );
  return result ?? current;
}

class _DeckblattTemplateSheet extends StatefulWidget {
  final DeckblattTemplate initial;
  const _DeckblattTemplateSheet({required this.initial});

  @override
  State<_DeckblattTemplateSheet> createState() =>
      _DeckblattTemplateSheetState();
}

class _DeckblattTemplateSheetState extends State<_DeckblattTemplateSheet> {
  static const Color _navy = Color(0xFF091733);
  static const Color _muted = Color(0xFF65738A);

  late DeckblattTemplate _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D9E6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose a Deckblatt Template',
                style: TextStyle(
                    color: _navy, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              const Text(
                'You can change this anytime',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.8,
                children: DeckblattTemplate.values
                    .map((t) => _DeckblattTemplateCard(
                          template: t,
                          selected: _selected == t,
                          // Tap-to-select: highlight immediately, then close
                          // the sheet with this template after a brief beat
                          // so the highlight is actually visible - no
                          // separate confirm button.
                          onTap: () {
                            setState(() => _selected = t);
                            Future.delayed(const Duration(milliseconds: 180), () {
                              if (mounted) Navigator.pop(context, t);
                            });
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckblattTemplateCard extends StatelessWidget {
  static const Color _navy = Color(0xFF091733);
  static const Color _green = Color(0xFF39EA2B);

  final DeckblattTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _DeckblattTemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _green : Colors.white.withOpacity(0.9),
            width: selected ? 2.2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _green.withOpacity(0.28)
                  : Colors.black.withOpacity(0.08),
              blurRadius: selected ? 18 : 10,
              spreadRadius: selected ? 1 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Image.asset(
                template.thumbnailAsset,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stack) =>
                    _MissingThumbnail(label: template.displayName),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      template.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _navy,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.check_circle_rounded,
                        color: _green, size: 14),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
