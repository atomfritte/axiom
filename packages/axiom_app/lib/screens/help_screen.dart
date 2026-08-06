/// Die Hilfe — vierzehn Kapitel als Markdown-Assets.
///
/// **Warum sie im Ruhezustand nichts belegt.** Vierzehn Kapitel mit
/// Bildschirmfotos sind, einmal dekodiert, mehr Arbeitsspeicher als der Rest
/// der App zusammen: Ein Bild in voller Auflösung kostet rund 13 MB, und
/// Flutters `ImageCache` behält es, auch wenn das Widget längst weg ist. Eine
/// Hilfe, die man einmal im Quartal aufschlägt, darf dafür nicht dauerhaft
/// bezahlen. Also drei Regeln, die im Code stehen und nicht bloß gemeint
/// sind:
///
///   1. Ein Kapitel wird erst geladen, wenn es geöffnet wird — nie beim
///      Start, nie „schon mal vorsorglich".
///   2. Der Text hängt an keinem Provider, sondern am Zustand des
///      Bildschirms. Wer die Hilfe verlässt, nimmt ihn mit.
///   3. `loadString(cache: false)`, weil `rootBundle` sonst jede gelesene
///      Datei für die Laufzeit der App behält — die Freigabe wäre sonst
///      eine Buchhaltung ohne Wirkung.
///
/// **Warum die Zeit hier nicht auf das Meta-Work-Budget zählt (G4).** Das
/// Budget deckelt das *Schrauben* am System — den Systemscreen, den
/// Regeleditor, den Review. Nachlesen, wie das System entscheidet, ist das
/// Gegenteil davon: Wer die Hilfe liest, ändert nichts. Ein Deckel darauf
/// würde ausgerechnet die billigste Form von Verständnis rationieren und
/// die teuerste (Ausprobieren) übrig lassen. Deshalb steht hier bewusst
/// kein `MetaTimedScope` — das ist eine Entscheidung, keine Lücke.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../design/widgets/prose.dart';
import '../i18n/i18n.dart';
import '../state/providers.dart';

/// Verzeichnis der Hilfe-Assets.
const String kHelpBase = 'assets/help/';

/// `assets/help/de/06-regelwerk.md` → Sprache, Nummer, Kurzname.
final _assetPattern = RegExp(r'^assets/help/(de|en)/(\d{2})[-_]?([^/]*)\.md$');

/// Ein Kapitel, so wie es im Asset-Verzeichnis liegt.
///
/// Bewusst ohne Titel: Den Titel trägt die `# `-Zeile *in* der Datei, und die
/// zu lesen hieße, alle vierzehn Dateien zu öffnen, um vierzehn Zeilen zu
/// beschriften. Die Übersicht steht deshalb in `00-index.md` und wird von
/// dort verlinkt; die Fußzeile kommt mit der Kapitelnummer aus.
@immutable
final class HelpChapter {
  /// Zweistellig, wie im Dateinamen: "00" … "13".
  final String number;

  /// Der Teil hinter der Nummer — nur für die Notfallübersicht.
  final String slug;

  final String assetDe;

  /// Fehlt, solange das Kapitel nicht übersetzt ist.
  final String? assetEn;

  const HelpChapter({
    required this.number,
    required this.slug,
    required this.assetDe,
    this.assetEn,
  });

  bool get isIndex => number == '00';

  bool translated(AppLanguage language) =>
      language == AppLanguage.de || assetEn != null;

  String assetFor(AppLanguage language) =>
      language == AppLanguage.en ? (assetEn ?? assetDe) : assetDe;
}

/// Liest das Verzeichnis der Kapitel aus dem Asset-Manifest.
///
/// Aus dem Manifest und nicht aus einer Liste im Quelltext: Eine Liste, die
/// man beim Anlegen eines Kapitels vergisst, führt zu einer Hilfe, die es
/// gibt und die niemand findet.
Future<List<HelpChapter>> loadHelpChapters([AssetBundle? bundle]) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
  final german = <String, ({String slug, String asset})>{};
  final english = <String, String>{};

  for (final asset in manifest.listAssets()) {
    final match = _assetPattern.firstMatch(asset);
    if (match == null) continue;
    final number = match.group(2)!;
    if (match.group(1) == 'de') {
      german[number] = (slug: match.group(3)!, asset: asset);
    } else {
      english[number] = asset;
    }
  }

  final numbers = german.keys.toList()..sort();
  return [
    for (final number in numbers)
      HelpChapter(
        number: number,
        slug: german[number]!.slug,
        assetDe: german[number]!.asset,
        assetEn: english[number],
      ),
  ];
}

/// Zweistellig, damit `kapitel:6` und `kapitel:06` dasselbe öffnen.
String normalizeChapter(String raw) {
  final digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return raw.trim();
  return digits.padLeft(2, '0');
}

/// Das Kapitel mit dieser Nummer, oder nichts.
HelpChapter? findChapter(List<HelpChapter> chapters, String number) {
  for (final chapter in chapters) {
    if (chapter.number == number) return chapter;
  }
  return null;
}

// ── Übersicht ───────────────────────────────────────────────────────────

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _query = TextEditingController();

  List<HelpChapter>? _chapters;

  /// Die geparste `00-index.md`. Hängt am Zustand dieses Bildschirms und an
  /// keinem Provider — beim Verlassen ist sie weg.
  List<ProseBlock>? _index;

  /// `null` heißt: keine Suche aktiv, es gilt die Übersicht.
  List<HelpHit>? _hits;

  bool _busy = true;
  bool _fallback = false;
  String? _failure;
  AppLanguage? _loaded;

  @override
  void dispose() {
    _query.dispose();
    // Ausdrücklich, obwohl der Zustand ohnehin verfällt: Diese Zeile ist die
    // Zusage aus dem Kopfkommentar, an der Stelle, an der sie gilt.
    _index = null;
    _hits = null;
    super.dispose();
  }

  Future<void> _load(AppLanguage language) async {
    setState(() {
      _busy = true;
      _index = null;
      _failure = null;
      // Gleich hier und nicht erst am Ende: Sonst stößt jeder Bildaufbau
      // während des Ladens einen zweiten Ladevorgang an.
      _loaded = language;
    });
    try {
      final chapters = _chapters ?? await loadHelpChapters();
      final index = findChapter(chapters, '00');
      List<ProseBlock>? blocks;
      var fallback = false;
      if (index != null) {
        final source = await rootBundle.loadString(
          index.assetFor(language),
          cache: false,
        );
        blocks = parseProse(source);
        fallback = !index.translated(language);
        // `source` ist ab hier unerreichbar. Genau deshalb steht es als
        // lokale Variable da und nicht als Feld.
      }
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _index = blocks;
        _fallback = fallback;
        _loaded = language;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = '$error';
        _busy = false;
        _loaded = language;
      });
    }
  }

  Future<void> _search(AppLanguage language) async {
    final chapters = _chapters;
    final query = _query.text.trim();
    if (chapters == null) return;
    if (query.isEmpty) {
      setState(() => _hits = null);
      return;
    }
    setState(() => _busy = true);
    final hits = await searchHelp(chapters, query, language);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _busy = false;
    });
  }

  void _open(String number) {
    final chapters = _chapters;
    if (chapters == null) return;
    final wanted = normalizeChapter(number);
    if (findChapter(chapters, wanted) == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HelpChapterScreen(chapters: chapters, number: wanted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    if (_loaded != language) {
      // Erst nach dem Aufbau, sonst setzt der Ladevorgang den Zustand
      // mitten im Bauen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loaded != language) _load(language);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Hilfe'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.huge,
        ),
        children: [
          _SearchField(
            controller: _query,
            onSubmit: () => _search(language),
            onClear: () {
              _query.clear();
              setState(() => _hits = null);
            },
            active: _hits != null,
          ),
          // Unter dem Suchfeld steht der Kapiteltitel „Inhalt" jetzt im
          // grossen Grad; 16 px darunter klebte er an der Feldkante.
          const SizedBox(height: Space.xl),
          if (_busy)
            PatientLoader(
              hint: context.t(
                'Die Hilfe braucht ungewöhnlich lange. Sie liegt in der App, nicht im Netz — ein Neustart hilft hier fast immer.',
              ),
            )
          else if (_hits != null)
            _Hits(hits: _hits!, onOpen: _open)
          else ...[
            if (_fallback) const _FallbackNote(),
            if (_index != null)
              _ProseColumn(
                child: ProseView(
                  blocks: _index!,
                  imageBase: kHelpBase,
                  onChapter: _open,
                ),
              )
            else
              _ChapterList(
                chapters: _chapters ?? const [],
                failure: _failure,
                onOpen: _open,
              ),
          ],
        ],
      ),
    );
  }
}

/// Notfallübersicht: die Kapitel, wie sie im Verzeichnis stehen.
///
/// Sie erscheint, wenn `00-index.md` fehlt. Eine Hilfe, die dann gar nichts
/// zeigt, wäre der schlechteste Fall — die Kapitel sind ja da.
class _ChapterList extends StatelessWidget {
  final List<HelpChapter> chapters;
  final String? failure;
  final void Function(String number) onOpen;

  const _ChapterList({
    required this.chapters,
    required this.onOpen,
    this.failure,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    if (chapters.isEmpty) {
      return EmptyState(
        label: context.t('Keine Kapitel'),
        headline: context.t('Die Hilfe ist nicht mitgeliefert'),
        body: context.t(
          'Unter assets/help/de/ liegt keine Textdatei. Die App läuft davon unberührt weiter — es gibt nur nichts nachzulesen.',
        ),
        footnote: failure,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(
            'Die Übersicht fehlt. Die Kapitel selbst sind da — hier stehen sie so, wie sie im Verzeichnis liegen.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: Space.lg),
        // Die Kapitelnummer lief in Schreibmaschine, der Kurzname auch. Beides
        // ist keins von beidem, wofuer Mono gedacht ist: Die Nummer ist ein
        // Messwert (Tabellenziffern reichen, damit „06" unter „12" flucht),
        // der Kurzname ist ein Wort. Zusammen sahen vierzehn Zeilen aus wie
        // ein Verzeichnislisting — ausgerechnet an der Stelle, an der die
        // Uebersicht fehlt und man ohnehin schon verunsichert ist.
        for (final chapter in chapters.where((c) => !c.isIndex))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Panel(
              onTap: () => onOpen(chapter.number),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    // Waechst mit der Schrift: fest gesetzt schnitt die
                    // Spalte bei 2,4-facher Groesse die zweite Ziffer ab.
                    width: MediaQuery.textScalerOf(context).scale(30),
                    child: Text(
                      chapter.number,
                      style: readingStyle(context, size: 14, color: p.info),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      chapter.slug,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Sagt sichtbar, dass hier die deutsche Fassung steht.
///
/// Genau so hält es CLAUDE.md für Regeltexte: sichtbar unfertig ist besser
/// als stumm fehlend. Ein englischer Leser, der plötzlich Deutsch liest,
/// soll wissen, dass das an der Übersetzung liegt und nicht an ihm.
class _FallbackNote extends StatelessWidget {
  const _FallbackNote();

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Panel(
        accent: p.caution.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.translate, size: 17, color: p.caution),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                context.t(
                  'Dieses Kapitel gibt es noch nicht auf Englisch. Hier steht die deutsche Fassung.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kapitel ─────────────────────────────────────────────────────────────

/// Ein einzelnes Kapitel, mit Vor und Zurück am Fuß.
///
/// Der Kapitelwechsel legt bewusst **keine** neue Route an: Wer sich durch
/// zehn Kapitel liest, hätte sonst zehn Bildschirme auf dem Stapel und
/// zehnmal zurückzutippen, um wieder herauszukommen — und jeder davon hielte
/// seinen Text.
class HelpChapterScreen extends ConsumerStatefulWidget {
  final List<HelpChapter> chapters;
  final String number;

  const HelpChapterScreen({
    super.key,
    required this.chapters,
    required this.number,
  });

  @override
  ConsumerState<HelpChapterScreen> createState() => _HelpChapterScreenState();
}

class _HelpChapterScreenState extends ConsumerState<HelpChapterScreen> {
  final _scroll = ScrollController();

  late String _number = widget.number;

  List<ProseBlock>? _blocks;
  Map<int, GlobalKey> _anchors = const {};
  bool _busy = true;
  bool _fallback = false;
  String? _failure;
  AppLanguage? _loaded;

  /// Alle Kapitel außer der Übersicht, in Lesereihenfolge.
  List<HelpChapter> get _reading =>
      widget.chapters.where((c) => !c.isIndex).toList();

  /// Vor welchem Block die Sprungmarken stehen — oder gar nicht.
  ///
  /// Das ist die erste Zwischenüberschrift: Titel und Einstiegsabsatz stehen
  /// darüber, der Rest darunter. Erst ab drei Marken, denn bei zweien ist
  /// Scrollen schneller als das Lesen der Liste.
  int? get _marksBefore {
    if (_anchors.length < 3) return null;
    return _anchors.keys.reduce((a, b) => a < b ? a : b);
  }

  @override
  void dispose() {
    _scroll.dispose();
    // Der Text geht mit dem Bildschirm. Die Bilder gibt `ProseView` frei.
    _blocks = null;
    _anchors = const {};
    super.dispose();
  }

  Future<void> _load(AppLanguage language) async {
    setState(() {
      _busy = true;
      // Vor dem Laden freigeben, nicht danach: Sonst liegen für einen
      // Augenblick zwei Kapitel gleichzeitig im Speicher.
      _blocks = null;
      _anchors = const {};
      _failure = null;
      // Siehe oben: verhindert, dass jeder Bildaufbau nachlädt.
      _loaded = language;
    });

    final chapter = findChapter(widget.chapters, _number);
    if (chapter == null) {
      setState(() {
        _busy = false;
        _loaded = language;
        _failure = context.t('Kapitel {0} gibt es nicht.', [_number]);
      });
      return;
    }

    try {
      final source = await rootBundle.loadString(
        chapter.assetFor(language),
        cache: false,
      );
      final blocks = parseProse(source);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _anchors = {
          for (var i = 0; i < blocks.length; i++)
            if (blocks[i] case ProseHeading(level: 2)) i: GlobalKey(),
        };
        _fallback = !chapter.translated(language);
        _busy = false;
        _loaded = language;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = '$error';
        _busy = false;
        _loaded = language;
      });
    }
  }

  void _go(String number) {
    final wanted = normalizeChapter(number);
    if (findChapter(widget.chapters, wanted) == null) return;
    setState(() {
      _number = wanted;
      _loaded = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _jumpTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.settle,
      curve: Motion.instrument,
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    if (_loaded != language) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loaded != language) _load(language);
      });
    }

    final p = context.axiom;
    final reading = _reading;
    final position = reading.indexWhere((c) => c.number == _number);
    final previous = position > 0 ? reading[position - 1] : null;
    final next = position >= 0 && position < reading.length - 1
        ? reading[position + 1]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Hilfe')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.lg),
            child: Center(
              child: Text(
                _number,
                style: readingStyle(context, size: 15, color: p.info),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.huge,
        ),
        children: [
          if (_busy)
            PatientLoader(
              hint: context.t(
                'Die Hilfe braucht ungewöhnlich lange. Sie liegt in der App, nicht im Netz — ein Neustart hilft hier fast immer.',
              ),
            )
          else if (_failure != null)
            EmptyState(
              label: context.t('Nicht geladen'),
              headline: context.t('Dieses Kapitel fehlt'),
              body: context.t(
                'Die Datei ist nicht mitgeliefert. Die anderen Kapitel sind davon unberührt.',
              ),
              footnote: _failure,
            )
          else ...[
            if (_fallback) const _FallbackNote(),
            _ProseColumn(
              child: ProseView(
                blocks: _blocks ?? const [],
                anchors: _anchors,
                imageBase: kHelpBase,
                onChapter: _go,
                // Die Sprungmarken standen bisher **ueber** der ganzen
                // Ansicht — also ueber dem Kapiteltitel. Man las das
                // Inhaltsverzeichnis eines Kapitels, dessen Namen man noch
                // nicht kannte, und der Titel stand darunter kleiner als der
                // Kasten darueber. Jetzt stehen sie hinter dem Einstieg und
                // vor der ersten Zwischenueberschrift: erst worum es geht,
                // dann was drin steht.
                interludeBefore: _marksBefore,
                interlude: _marksBefore == null
                    ? null
                    : _Marks(
                        blocks: _blocks ?? const [],
                        anchors: _anchors,
                        onJump: _jumpTo,
                      ),
              ),
            ),
          ],
          const SizedBox(height: Space.xl),
          _ProseColumn(
            child: _Footer(
              previous: previous?.number,
              next: next?.number,
              onGo: _go,
              onOverview: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sprungmarken: die Zwischenüberschriften eines langen Kapitels.
///
/// Erst ab drei — bei zweien ist Scrollen schneller als Lesen, was in der
/// Liste steht.
class _Marks extends StatelessWidget {
  final List<ProseBlock> blocks;
  final Map<int, GlobalKey> anchors;
  final void Function(GlobalKey key) onJump;

  const _Marks({
    required this.blocks,
    required this.anchors,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final entries = anchors.keys.toList()..sort();

    // Die Sprungmarken liegen in einer Mulde, nicht auf einer Karte: Sie sind
    // das Inhaltsverzeichnis *dieses* Kapitels und stehen damit unter dem
    // Text, nicht ueber ihm. Eine erhobene Karte haette hier mit dem Kapitel
    // selbst um die Aufmerksamkeit konkurriert.
    //
    // Unten kein Abstand: Die erste Zwischenueberschrift bringt ihren
    // eigenen mit (Space.xxl und den Abschnittsstrich). Zwei Abstaende
    // uebereinander sind ein Loch.
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Well(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        radius: BorderRadius.circular(Radii.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.md),
            Text(
              context.t('In diesem Kapitel'),
              style: sectionStyle(context),
            ),
            const SizedBox(height: Space.xs),
            for (final index in entries)
              if (blocks[index] case ProseHeading(:final plain))
                InkWell(
                  onTap: () => onJump(anchors[index]!),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      children: [
                        Expanded(
                          // Eine Sprungmarke ist Navigation, keine Fussnote
                          // — sie stand im Sekundaergrad da und war damit
                          // kleiner als der Text, in den sie fuehrt.
                          child: Text(
                            plain,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Icon(
                          Icons.arrow_downward,
                          size: 15,
                          color: p.inkFaint,
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}

/// Vor, zurück, zurück zur Übersicht — am Fuß, wo man ankommt.
class _Footer extends StatelessWidget {
  final String? previous;
  final String? next;
  final void Function(String number) onGo;
  final VoidCallback onOverview;

  const _Footer({
    required this.onGo,
    required this.onOverview,
    this.previous,
    this.next,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    // **Die Knöpfe sind so breit wie ihre Beschriftung.**
    //
    // Der `Wrap` darunter sollte sie nebeneinander stellen und erst bei
    // großer Schrift umbrechen. Er konnte das nie: Das Thema gibt jedem
    // `OutlinedButton` eine Mindestbreite von `Size.fromHeight(48)`, und
    // deren Breite ist unendlich. Jeder Knopf nahm damit eine ganze Zeile —
    // drei Balken über die volle Breite am Fuß jedes Kapitels, obwohl
    // „Kapitel 12" acht Zeichen hat. Mit einer Mindestbreite von null tut
    // der `Wrap` endlich das, wofür er dasteht.
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: p.rule),
        const SizedBox(height: Space.lg),
        // Umbrechend statt in einer Zeile: Bei 2,4-facher Schrift passen
        // drei Knöpfe nicht mehr nebeneinander.
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            if (previous != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(context.t('Kapitel {0}', [previous!])),
                onPressed: () => onGo(previous!),
                style: style,
              ),
            OutlinedButton(
              onPressed: onOverview,
              style: style,
              child: Text(context.t('Übersicht')),
            ),
            if (next != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(context.t('Kapitel {0}', [next!])),
                onPressed: () => onGo(next!),
                style: style,
              ),
          ],
        ),
      ],
    );
  }
}

// ── Suche ───────────────────────────────────────────────────────────────

/// Ein Fundstück: Kapitelnummer und die Zeile, in der es steht.
@immutable
final class HelpHit {
  final String number;
  final String snippet;
  const HelpHit(this.number, this.snippet);
}

/// Sucht über alle Kapitel — und lässt sie danach wieder los.
///
/// **Die Entscheidung, die hier getroffen wurde.** Eine schnelle Suche
/// bräuchte einen Index über alle vierzehn Kapitel, und der müsste im
/// Speicher stehen, auch wenn niemand sucht. Das widerspricht dem Zweck
/// dieses Bildschirms: im Ruhezustand nichts belegen. Eine Suche ist ein
/// seltener, ausdrücklicher Vorgang — einmal lesen ist billiger als
/// dauerhaft halten.
///
/// Deshalb: lädt beim Abschicken, sammelt die Treffer, gibt frei. Der
/// geladene Text ist eine lokale Variable im Schleifenrumpf; nach dem
/// Durchlauf hält ihn niemand mehr, und `cache: false` verhindert, dass
/// `rootBundle` ihn hinter unserem Rücken behält.
///
/// Und deshalb sucht sie **beim Abschicken**, nicht bei jedem Tastendruck:
/// Sonst läse ein getipptes Wort vierzehn Dateien je Buchstabe.
Future<List<HelpHit>> searchHelp(
  List<HelpChapter> chapters,
  String query,
  AppLanguage language, [
  AssetBundle? bundle,
]) async {
  final needle = query.trim().toLowerCase();
  if (needle.length < 2) return const [];
  final source = bundle ?? rootBundle;
  final hits = <HelpHit>[];

  for (final chapter in chapters) {
    if (chapter.isIndex) continue;
    String text;
    try {
      text = await source.loadString(chapter.assetFor(language), cache: false);
    } on Object {
      continue; // Ein fehlendes Kapitel ist kein Grund, die Suche abzubrechen.
    }

    var found = 0;
    for (final line in text.split('\n')) {
      if (found >= 2) break;
      final at = line.toLowerCase().indexOf(needle);
      if (at < 0) continue;
      hits.add(HelpHit(chapter.number, _snippet(line, at, needle.length)));
      found++;
    }
    // `text` verlässt hier den Gültigkeitsbereich.
  }
  return hits;
}

/// Ein Ausschnitt um die Fundstelle, ohne Auszeichnungszeichen.
String _snippet(String line, int at, int length) {
  final plain = line
      .replaceAll(RegExp(r'^[#>\-*\d.)\s]+'), '')
      // Auszeichnung gehört nicht in eine Trefferliste: Was hier steht, ist
      // eine Fundstelle, kein Quelltext.
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll('*', '')
      .replaceAll('`', '')
      .trim();
  if (plain.length <= 160) return plain;
  final start = (at - 60).clamp(0, plain.length);
  final end = (at + length + 100).clamp(0, plain.length);
  return '${start > 0 ? "… " : ""}${plain.substring(start, end).trim()} …';
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final bool active;

  const _SearchField({
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    // Auf den Controller hören, damit der Knopf rechts umschaltet, sobald
    // etwas im Feld steht — ohne das bliebe er stehen, bis irgendetwas
    // anderes den Bildschirm neu baut.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmit(),
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: context.t('In der Hilfe suchen'),
          prefixIcon: Icon(Icons.search, size: 19, color: p.inkDim),
          // Untergrenze statt fester Höhe: Bei 2,4-facher Schrift wächst das
          // Feld mit, bei 0,85-facher fällt es nicht unter das Tippziel.
          constraints: const BoxConstraints(minHeight: 52),
          suffixIcon: active || value.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, size: 19, color: p.inkDim),
                  tooltip: context.t('Suche zurücksetzen'),
                  onPressed: onClear,
                )
              : IconButton(
                  icon: Icon(Icons.arrow_forward, size: 19, color: p.inkDim),
                  tooltip: context.t('Suchen'),
                  onPressed: onSubmit,
                ),
        ),
      ),
    );
  }
}

class _Hits extends StatelessWidget {
  final List<HelpHit> hits;
  final void Function(String number) onOpen;

  const _Hits({required this.hits, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    if (hits.isEmpty) {
      return EmptyState(
        label: context.t('Kein Treffer'),
        headline: context.t('Dazu steht nichts in der Hilfe'),
        body: context.t(
          'Gesucht wird im Text der Kapitel, ohne Wortstammerkennung. Ein kürzeres Wort trifft oft mehr.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(context.t('{0} Fundstellen', [hits.length])),
        for (final hit in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Panel(
              onTap: () => onOpen(hit.number),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(30),
                    child: Text(
                      hit.number,
                      style: readingStyle(context, size: 14, color: p.info),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      hit.snippet,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Begrenzt die Zeilenlänge.
///
/// Eine Zeile über die volle Tabletbreite hat gut hundert Zeichen; danach
/// findet das Auge den Zeilenanfang nicht mehr zuverlässig — und ein Text,
/// den man nicht liest, erklärt nichts.
class _ProseColumn extends StatelessWidget {
  final Widget child;
  const _ProseColumn({required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kProseMaxWidth),
      child: child,
    ),
  );
}
