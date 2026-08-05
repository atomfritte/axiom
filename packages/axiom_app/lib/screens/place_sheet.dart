/// Der Ort — als Kontext, nicht als Koordinate.
///
/// **Warum kein Geofence.** Ein Geofence beantwortet „wo bin ich". Die
/// eigentliche Frage ist „was geht hier", und die steht in keiner Koordinate.
/// Er kostet `ACCESS_BACKGROUND_LOCATION` — die eingriffstiefste Berechtigung,
/// die Android kennt —, verlangt entweder Play Services oder einen dauerhaft
/// messenden Dienst, und legt in einer Datenbank mit Gesundheitsdaten ein
/// Bewegungsprofil an. Der Gegenwert wäre ein Kreis mit 200 m Radius, der
/// nicht weiß, ob der Baumarkt offen hat.
///
/// Stattdessen: ein Name. Gesetzt mit zwei Tipps hier, oder von einer
/// Samsung-Routine über den Broadcast `de.atomfritte.axiom.PLACE` — „WLAN Büro
/// verbunden" ist genauer als jeder Kreis und kostet keine Berechtigung. [D2]
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../state/providers.dart';

/// Öffnet die Ortsauswahl. Ein Tipp hierher, ein Tipp auf den Eintrag —
/// mehr darf das Umschalten nicht kosten (G1).
Future<void> showPlaceSheet(
  BuildContext context, {
  required String? current,
  required List<String> known,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlaceSheet(current: current, known: known),
    );

class _PlaceSheet extends ConsumerStatefulWidget {
  final String? current;
  final List<String> known;
  const _PlaceSheet({required this.current, required this.known});

  @override
  ConsumerState<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<_PlaceSheet> {
  final _entry = TextEditingController();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Future<void> _pick(String? place) async {
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.setPlace(place);
    await HapticFeedback.selectionClick();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;

    return SafeArea(
      child: SingleChildScrollView(
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
            Text(context.t('ORT'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            Text(
              context.t('Der Ort entscheidet, was hier vorgeschlagen wird. Ohne Ort steht alles zur Auswahl — es wird nichts ausgeblendet, was du nicht selbst eingeschaltet hast.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.lg),

            _Choice(
              label: context.t('Kein Ort'),
              selected: widget.current == null,
              onTap: () => _pick(null),
            ),
            for (final place in widget.known)
              _Choice(
                label: place,
                selected: widget.current != null &&
                    place.toLowerCase() == widget.current!.toLowerCase(),
                onTap: () => _pick(place),
              ),

            const SizedBox(height: Space.lg),
            Text(context.t('Anderer Ort'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _entry,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t('Baumarkt, Büro, Zuhause …'),
              ),
              onSubmitted: (value) =>
                  value.trim().isEmpty ? null : _pick(value.trim()),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () =>
                  _entry.text.trim().isEmpty ? null : _pick(_entry.text.trim()),
              child: Text(context.t('Setzen')),
            ),
            const SizedBox(height: Space.md),
            Text(
              context.t('Eine Geräteroutine kann das auch: Broadcast de.atomfritte.axiom.PLACE mit dem Zusatz „place". Ohne Standortberechtigung.'),
              style: monoStyle(context, size: 11, color: p.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Panel(
        accent: selected ? p.signal.withValues(alpha: 0.55) : null,
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md),
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? p.signal : p.inkFaint,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ortswahl beim Sortieren einer Notiz.
///
/// Chips statt Freitextfeld an erster Stelle: Im Sortiermoment ist Tippen die
/// teuerste Eingabe, und die üblichen Orte stehen ohnehin schon da. „Überall"
/// ist die Voreinstellung — eine Aufgabe ohne Ortsbindung ist der Normalfall,
/// und Ortsbindung eine bewusste Einschränkung.
class PlaceChips extends StatelessWidget {
  final String? value;
  final List<String> known;
  final ValueChanged<String?> onChanged;

  const PlaceChips({
    super.key,
    required this.value,
    required this.known,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Ein selbst getippter Ort muss als Chip erscheinen, sonst sieht es aus,
    // als waere die Eingabe verlorengegangen.
    final options = [
      ...known,
      if (value != null &&
          !known.any((p) => p.toLowerCase() == value!.toLowerCase()))
        value!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('Geht das nur an einem Ort?'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        Text(context.t('Nur nötig, wenn die Aufgabe woanders nicht geht. Kein Standortzugriff — nur ein Name.'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            ChoiceChip(
              label: Text(context.t('überall')),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final place in options)
              ChoiceChip(
                label: Text(place),
                selected: value != null &&
                    place.toLowerCase() == value!.toLowerCase(),
                onSelected: (_) => onChanged(place),
              ),
            ActionChip(
              label: Text(context.t('Ort …')),
              onPressed: () async {
                final entered = await _askForPlace(context);
                if (entered != null) onChanged(entered);
              },
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _askForPlace(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('Ort')),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: context.t('Baumarkt, Büro, Zuhause …'),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        // TextButton, nicht FilledButton: Der gefuellte Knopf ist in diesem
        // Theme auf volle Breite gestellt und sprengt eine Dialogzeile.
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Abbrechen')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.t('Übernehmen')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result == null || result.isEmpty ? null : result;
}
