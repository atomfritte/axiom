/// Erfassung — der wichtigste Screen der App.
///
/// Zielwert: unter 3 Sekunden vom Impuls bis erfasst. Zwischen "Gedanke
/// entsteht" und "sicher notiert" liegen wenige Sekunden; jede Reibung in
/// diesem Fenster fuehrt zum Totalverlust. [D9]
///
/// Deshalb: Feld ist sofort fokussiert, Tastatur ist offen, Enter speichert.
/// Keine Kategorie, kein Projekt, keine Prioritaet, kein Datum. Triage
/// passiert spaeter — hier zaehlt nur, dass der Gedanke drin ist.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

Future<void> showCaptureSheet(BuildContext context, {String? initialText}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CaptureSheet(initialText: initialText),
    );

class _CaptureSheet extends ConsumerStatefulWidget {
  final String? initialText;
  const _CaptureSheet({this.initialText});

  @override
  ConsumerState<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<_CaptureSheet> {
  late final _controller = TextEditingController(text: widget.initialText);
  final _focus = FocusNode();
  bool _saving = false;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    // Tastatur sofort — kein zusaetzlicher Tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save({bool keepOpen = false}) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);

    final runtime = await ref.read(runtimeProvider.future);
    await runtime.capture(text);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);

    if (!mounted) return;
    if (keepOpen) {
      _controller.clear();
      _focus.requestFocus();
      setState(() {
        _saving = false;
        _savedCount++;
      });
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('Erfasst.')),
          duration: Duration(milliseconds: 1200),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        top: Space.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.t('ERFASSEN'), style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              if (_savedCount > 0)
                Text(context.t('{0} gespeichert', [_savedCount]),
                    style: monoStyle(context, size: 11, color: p.calm)),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: context.t('Was ist dir gerade eingefallen?'),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            context.t('Rein damit. Sortieren kannst du später.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(keepOpen: true),
                  child: Text(context.t('Speichern & weiter')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: Text(context.t('Speichern')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
