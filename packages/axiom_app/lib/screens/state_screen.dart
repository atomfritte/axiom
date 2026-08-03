/// "Zustand" — alle sechs Dimensionen mit Herleitung.
///
/// Jeder Wert ist aufklappbar. Ein Score, dessen Rechenweg unsichtbar
/// bleibt, wird von diesem Nutzerprofil zu Recht verworfen (G2).
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import 'checkin_sheet.dart';

class StateScreen extends ConsumerWidget {
  const StateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final p = context.axiom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zustand'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await showCheckinSheet(context);
              refreshAxiom(ref);
            },
            icon: Icon(Icons.add_chart, size: 18, color: p.signal),
            label: Text('Check-in',
                style: TextStyle(color: p.signal)),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) {
          final s = snap.state;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.sm, Space.lg, Space.huge),
            children: [
              _LoadBanner(level: s.loadLevel),
              const SizedBox(height: Space.xl),
              const SectionLabel('Messwerte'),
              Panel(
                child: Column(
                  children: [
                    InstrumentBar(
                      label: 'Kapazität',
                      value: s.capacity,
                      color: p.signal,
                      reading: 'Wie viel exekutive Reserve heute da ist.',
                      breakdown: snap.breakdown['capacity'] ?? const [],
                      confidence: s.confidenceOf('capacity'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: 'Kompensationslast',
                      value: s.loadIndex,
                      color: p.forLoadLevel(s.loadLevel.index),
                      reading:
                          'Kumulierter Aufwand, den Alltag zu strukturieren.',
                      breakdown: snap.breakdown['load_index'] ?? const [],
                      confidence: s.confidenceOf('load_index'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: 'Reizbedarf',
                      value: s.sensationNeed,
                      color: p.caution,
                      reading: 'Ungedeckter Bedarf sucht sich den '
                          'schnellsten Kanal.',
                      breakdown: snap.breakdown['sensation_need'] ?? const [],
                      confidence: s.confidenceOf('sensation_need'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: 'Fokuslast heute',
                      value: s.focusDebt,
                      color: p.info,
                      reading: 'Verbrauchte Konzentrationszeit seit heute früh.',
                      confidence: s.confidenceOf('focus_debt'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: 'Regulationsreserve',
                      value: s.regulation,
                      color: p.calm,
                      reading: 'Puffer für emotionale Belastung.',
                      confidence: s.confidenceOf('regulation'),
                    ),
                    Divider(color: p.rule, height: Space.xl),
                    InstrumentBar(
                      label: 'Schlafschuld',
                      value: s.sleepDebt,
                      color: p.caution,
                      reading: 'Stärkster einzelner Modulator der Kapazität.',
                      confidence: s.confidenceOf('sleep_debt'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              const _Disclaimer(),
            ],
          );
        },
      ),
    );
  }
}

/// Zeigt die Load-Stufe. Wortwahl ist hier entscheidend: L3 ist ein
/// Ergebnis des Systems, kein Versagen des Nutzers (Risiko R7).
class _LoadBanner extends StatelessWidget {
  final LoadLevel level;
  const _LoadBanner({required this.level});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final color = p.forLoadLevel(level.index);
    return Panel(
      accent: color.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Text(level.name.toUpperCase(),
                    style: monoStyle(context,
                        size: 12, weight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(_headline(level),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(_body(level), style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  static String _headline(LoadLevel l) => switch (l) {
        LoadLevel.l0 => 'Normalbetrieb',
        LoadLevel.l1 => 'Last erhöht',
        LoadLevel.l2 => 'Last kritisch',
        LoadLevel.l3 => 'Erhaltungsmodus',
      };

  static String _body(LoadLevel l) => switch (l) {
        LoadLevel.l0 => 'Die Kompensationslast liegt im gewohnten Bereich.',
        LoadLevel.l1 =>
          'Die Last steigt seit einigen Tagen. Noch unauffällig nach außen — '
              'genau deshalb wird sie hier angezeigt.',
        LoadLevel.l2 =>
          'Jetzt nichts Neues zusätzlich aufnehmen. Bestehendes eher abgeben '
              'als erweitern.',
        LoadLevel.l3 =>
          'Für die nächsten Tage nur Pflicht und Erholung. Dass dieser Modus '
              'greift, ist der Zweck des Systems — nicht dein Versagen.',
      };
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EINORDNUNG', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Diese Werte sind Messungen aus deinen eigenen Angaben und '
            'Gerätedaten. Sie sind keine Diagnose und kein Befund. '
            'AXIOM ersetzt weder ärztliche noch psychotherapeutische '
            'Behandlung.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
