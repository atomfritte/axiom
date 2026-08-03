/// Datenausgleich und Wirkfenster — Stufe 4.
///
/// **Export/Import statt Server-Sync.** Ein selbst gehosteter Abgleich
/// bräuchte die `INTERNET`-Berechtigung und würde die stärkste Zusicherung
/// des Projekts aufheben: dass Gesundheitsdaten das Gerät auf
/// Betriebssystemebene nicht verlassen können (ADR-0002).
///
/// Für den tatsächlichen Zweck — Telefon und Rechner abgleichen, ein Backup
/// halten — genügt eine verschlüsselte Datei. Events sind unveränderlich,
/// also ist ihre Vereinigung konfliktfrei: Beide Seiten importieren die
/// Datei der anderen, und beide haben danach alles.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';

class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daten')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: const [
          _ExportCard(),
          SizedBox(height: Space.lg),
          _ImportCard(),
          SizedBox(height: Space.xxl),
          SectionLabel('Wirkfenster'),
          _MedSection(),
        ],
      ),
    );
  }
}

// ── Export ──────────────────────────────────────────────────────────────

class _ExportCard extends ConsumerStatefulWidget {
  const _ExportCard();

  @override
  ConsumerState<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends ConsumerState<_ExportCard> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _lastPath;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final runtime = await ref.read(runtimeProvider.future);
      final bytes = await runtime.exportVault(_passphrase.text);

      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final name = 'axiom-'
          '${now.year}${now.month.toString().padLeft(2, "0")}'
          '${now.day.toString().padLeft(2, "0")}.axiom';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      setState(() => _lastPath = file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportiert: $name')),
      );
      await HapticFeedback.mediumImpact();
    } on VaultError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXPORT', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Alle Ereignisse in eine verschlüsselte Datei. Ohne das Kennwort '
            'ist sie nicht lesbar — auch nicht von dir.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _passphrase,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Kennwort, mindestens acht Zeichen',
            ),
          ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed:
                _busy || _passphrase.text.length < 8 ? null : _export,
            child: Text(_busy ? 'Läuft…' : 'Exportieren'),
          ),
          if (_lastPath != null) ...[
            const SizedBox(height: Space.md),
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _lastPath!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pfad kopiert.')),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: p.base,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: p.rule),
                ),
                child: Text(_lastPath!,
                    style: monoStyle(context, size: 10.5)),
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            'Das Kennwort steht nirgends. Geht es verloren, ist die Datei '
            'unbrauchbar — das ist der Preis dafür, dass sie sonst niemand '
            'lesen kann.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Import ──────────────────────────────────────────────────────────────

class _ImportCard extends ConsumerStatefulWidget {
  const _ImportCard();

  @override
  ConsumerState<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends ConsumerState<_ImportCard> {
  final _path = TextEditingController();
  final _passphrase = TextEditingController();
  bool _busy = false;
  VaultImportResult? _result;
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _run({required bool dryRun}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = File(_path.text.trim());
      if (!file.existsSync()) throw VaultError('Datei nicht gefunden.');
      final data = Uint8List.fromList(await file.readAsBytes());

      final runtime = await ref.read(runtimeProvider.future);
      final result = await runtime.importVault(
        data,
        _passphrase.text,
        dryRun: dryRun,
      );

      if (!mounted) return;
      setState(() => _result = result);
      if (!dryRun) {
        refreshAxiom(ref);
        await HapticFeedback.mediumImpact();
      }
    } on VaultError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final ready = _path.text.trim().isNotEmpty && _passphrase.text.length >= 8;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IMPORT', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          Text(
            'Spielt fehlende Ereignisse ein. Vorhandene bleiben unberührt — '
            'der Import ist wiederholbar, und zwei Geräte gleichen sich an, '
            'ohne dass etwas verlorengeht.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _path,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Pfad zur .axiom-Datei'),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _passphrase,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Kennwort'),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _busy || !ready ? null : () => _run(dryRun: true),
                  child: const Text('Probelauf'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  onPressed:
                      _busy || !ready ? null : () => _run(dryRun: false),
                  child: const Text('Einspielen'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: p.caution.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(_error!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: p.calm.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_result!.summary,
                      style: monoStyle(context, size: 12, color: p.ink)),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Aus Export vom '
                    '${_result!.manifest.createdAt.toLocal().day}.'
                    '${_result!.manifest.createdAt.toLocal().month}. · '
                    'Schema v${_result!.manifest.schemaVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Wirkfenster (M13) ───────────────────────────────────────────────────

class _MedSection extends ConsumerWidget {
  const _MedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider).value;
    final enabled = runtime?.medEnabled ?? false;
    final state = ref.watch(medStateProvider).value;
    final entries = ref.watch(medEntriesProvider).value ?? const [];
    final p = context.axiom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Wirkfenster protokollieren',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: (value) async {
                      final rt = await ref.read(runtimeProvider.future);
                      rt.medEnabled = value;
                      refreshAxiom(ref);
                    },
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(kMedDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall),

              if (enabled) ...[
                const SizedBox(height: Space.lg),
                if (state?.active != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.info.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: Text(
                      runtime?.describeMedWindow(state!) ?? '',
                      style: monoStyle(context, size: 12, color: p.ink),
                    ),
                  ),
                const SizedBox(height: Space.md),
                OutlinedButton.icon(
                  onPressed: () => _logEntry(context, ref),
                  icon: Icon(Icons.add, size: 18, color: p.signal),
                  label: const Text('Einnahme eintragen'),
                ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Text('LETZTE EINTRÄGE',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: Space.sm),
                  for (final entry in entries.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.label}'
                              '${entry.dose == null ? "" : " · ${entry.dose}"}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '${entry.takenAt.day}.${entry.takenAt.month}. '
                            '${entry.takenAt.hour.toString().padLeft(2, "0")}:'
                            '${entry.takenAt.minute.toString().padLeft(2, "0")}',
                            style: monoStyle(context, size: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _logEntry(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _MedSheet(),
      );
}

class _MedSheet extends ConsumerStatefulWidget {
  const _MedSheet();

  @override
  ConsumerState<_MedSheet> createState() => _MedSheetState();
}

class _MedSheetState extends ConsumerState<_MedSheet> {
  final _label = TextEditingController();
  final _dose = TextEditingController();
  int _onset = 30;
  int _duration = 360;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Letzten Eintrag als Vorbelegung: Dieselben Angaben wiederholt zu
    // tippen ist genau die Reibung, an der Erfassung stirbt.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final runtime = await ref.read(runtimeProvider.future);
      final last = await runtime.lastMedEntry();
      if (!mounted || last == null || _loaded) return;
      setState(() {
        _label.text = last.label;
        _dose.text = last.dose ?? '';
        _onset = last.onset.inMinutes;
        _duration = last.duration.inMinutes;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _label.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_label.text.trim().isEmpty) return;
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.logMedEntry(
      label: _label.text.trim(),
      dose: _dose.text.trim().isEmpty ? null : _dose.text.trim(),
      onset: Duration(minutes: _onset),
      duration: Duration(minutes: _duration),
    );
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
            Text('EINNAHME', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _label,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Bezeichnung, wie du sie führst',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _dose,
              decoration: const InputDecoration(hintText: 'Dosis (optional)'),
            ),

            const SizedBox(height: Space.xl),
            Text('Wann setzt es bei dir ein?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Aus deiner Beobachtung. AXIOM schlägt hier nichts vor — das '
              'hängt von Präparat, Person und Tag ab.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final option in [0, 15, 30, 45, 60, 90])
                  ChoiceChip(
                    label: Text('$option min'),
                    selected: _onset == option,
                    onSelected: (_) => setState(() => _onset = option),
                  ),
              ],
            ),

            const SizedBox(height: Space.lg),
            Text('Wie lange hält es an?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final option in [120, 240, 360, 480, 720])
                  ChoiceChip(
                    label: Text('${(option / 60).round()} h'),
                    selected: _duration == option,
                    onSelected: (_) => setState(() => _duration = option),
                  ),
              ],
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _label.text.trim().isEmpty ? null : _save,
              child: const Text('Eintragen'),
            ),
            const SizedBox(height: Space.md),
            Text(kMedDisclaimer,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
