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
import '../i18n/i18n.dart';
import '../platform/android_bridge.dart';
import '../state/providers.dart';

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
  bool _listening = false;
  bool _speech = false;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    // Tastatur sofort — kein zusaetzlicher Tap.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _focus.requestFocus();
      final available = await AndroidBridge.speechAvailable();
      if (mounted) setState(() => _speech = available);
    });
  }

  /// Diktieren.
  ///
  /// Der Sinn ist nicht Bequemlichkeit, sondern Reibung: Tippen dauert im
  /// Gehen, im Auto, mit vollen Händen zu lange — und was in diesen
  /// Sekunden nicht festgehalten ist, ist weg [D9].
  ///
  /// Erkannter Text wird **angehängt, nicht ersetzt**. Wer zweimal spricht,
  /// hat zwei Sätze; wer schon getippt hat, verliert nichts.
  Future<void> _dictate() async {
    if (_listening) return;
    setState(() => _listening = true);
    final heard = await AndroidBridge.listen();
    if (!mounted) return;
    setState(() => _listening = false);
    if (heard == null || heard.isEmpty) return;

    final existing = _controller.text.trim();
    final merged = existing.isEmpty ? heard : '$existing $heard';
    _controller
      ..text = merged
      ..selection = TextSelection.collapsed(offset: merged.length);
    await HapticFeedback.selectionClick();
    _focus.requestFocus();
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
              hintText: _listening
                  ? context.t('Hört zu …')
                  : context.t('Was ist dir gerade eingefallen?'),
              // Das Mikrofon sitzt im Feld, nicht daneben: Es ist der
              // zweite Weg in dasselbe Feld, keine zweite Funktion.
              suffixIcon: _speech
                  ? Padding(
                      padding: const EdgeInsets.only(right: Space.xs),
                      child: _MicButton(
                        listening: _listening,
                        onTap: _dictate,
                      ),
                    )
                  : null,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 56, minHeight: 56),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            _speech
                ? context.t('Rein damit — tippen oder sprechen. Sortieren kannst du später.')
                : context.t('Rein damit. Sortieren kannst du später.'),
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

/// Mikrofon im Eingabefeld.
///
/// Groß genug zum Treffen, ohne hinzusehen: 56 dp. Beim Zuhören wechselt
/// nur die Farbe und der Rahmen pulst nicht — eine Animation, die um
/// Aufmerksamkeit bittet, wäre hier genau falsch.
class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;

  const _MicButton({required this.listening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Semantics(
      button: true,
      label: context.t('Diktieren'),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: listening
                ? p.signal.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: listening ? p.signal : p.rule,
            ),
          ),
          child: Icon(
            listening ? Icons.graphic_eq : Icons.mic_none,
            size: 22,
            color: listening ? p.signal : p.inkDim,
          ),
        ),
      ),
    );
  }
}
