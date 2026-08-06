/// Die Verträge über die Brücke — jede Zeichenkette, die auf beiden Seiten
/// stehen muss.
///
/// **Warum das eine eigene Datei ist.** Zwischen Dart und Kotlin liegt ein
/// MethodChannel, und der prüft nichts. Ein Tippfehler im Methodennamen wird
/// zu `notImplemented`, ein umbenannter Argumentschlüssel zu `null`, ein
/// verschobener Antwortschlüssel zu einem Wert, der von da an dauerhaft
/// `false` heißt. Keiner dieser drei Fehler wirft, keiner steht im Log, und
/// keiner fällt beim Bauen auf — die Funktion tut einfach nichts mehr. Genau
/// das ist der teuerste Fehlermodus dieses Projekts: „passiert nichts" ist
/// von außen nicht diagnostizierbar.
///
/// **Was hier nicht geprüft wird.** Ob der Kotlin-Code tut, was er behauptet.
/// Dafür bräuchte es ein Gerät. Geprüft wird die *Naht*: Mengen gegen Mengen,
/// nicht Stichproben. Ein Test, der eine einzelne Zeichenkette im Quelltext
/// sucht, bleibt grün, sobald eine Seite eine **zweite** dazubekommt — und
/// genau das ist der Fall, der hier gefunden werden muss.
///
/// Jede Prüfung stellt zuerst fest, dass ihre eigene Ausbeute nicht leer ist.
/// Ein Mengenvergleich gegen eine leere Menge ist immer grün; ein Wächter,
/// dessen Muster ins Leere greift, wäre von einem funktionierenden nicht zu
/// unterscheiden.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── Quelltext lesen ─────────────────────────────────────────────────────

String read(String path) => File(path).readAsStringSync();

String androidFile(String path) => read('android/app/src/main/$path');

String kotlinFile(String name) =>
    androidFile('kotlin/de/atomfritte/axiom/$name.kt');

List<File> kotlinFiles() =>
    Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

List<File> dartFiles() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Quelltext ohne Kommentare.
///
/// Nötig, weil die Kommentare in diesem Projekt genau die Namen nennen, um
/// die es geht — sie erklären ja, warum sie so heißen. Ohne diesen Schritt
/// verböte der Test das Erklären.
String withoutComments(String source) => source
    .split('\n')
    .where((line) {
      final t = line.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

// ── Klammern zählen statt raten ─────────────────────────────────────────
//
// Reguläre Ausdrücke können keine geschachtelten Klammern. Für einen
// Argumentblock, eine Kotlin-Funktion oder ein `mapOf(…)` braucht es aber
// genau das — sonst endet die Ausbeute je nach Formatierung mal hier und mal
// dort, und der Test misst die Einrückung statt den Vertrag.

/// Der Inhalt zwischen der Klammer an [from] und ihrer Gegenstelle.
String balanced(String source, int from, String open, String close) {
  var depth = 0;
  for (var i = from; i < source.length; i++) {
    final c = source[i];
    if (c == open) {
      depth++;
    } else if (c == close) {
      depth--;
      if (depth == 0) return source.substring(from + 1, i);
    }
  }
  throw StateError('Klammer ab $from wird nie geschlossen');
}

/// Der Rumpf der Funktion, deren Kopf bei [at] beginnt.
String bodyAfter(String source, int at, {String open = '{', String close = '}'}) {
  final start = source.indexOf(open, at);
  if (start < 0) throw StateError('kein $open nach $at');
  return balanced(source, start, open, close);
}

/// Der Rumpf einer Kotlin-Funktion, gefunden über ihren Namen.
String kotlinFunction(String source, String name) {
  final at = source.indexOf(RegExp('fun $name\\b'));
  if (at < 0) throw StateError('fun $name nicht gefunden');
  return bodyAfter(source, at);
}

/// Der Wert einer Kotlin-Konstante, etwa `const val ACTION_STOP = "…"`.
String kotlinConstant(String source, String name) {
  final value =
      RegExp('const val $name = "([^"]+)"').firstMatch(source)?.group(1);
  if (value == null) throw StateError('const val $name nicht gefunden');
  return value;
}

/// Die Schlüssel einer Kotlin-Map: `"name" to …`.
Set<String> kotlinMapKeys(String body) => RegExp(r'"([\w.]+)"\s+to\s')
    .allMatches(body)
    .map((m) => m.group(1)!)
    .toSet();

/// Die Schlüssel eines Dart-Map-Literals: `'name': …`.
Set<String> dartMapKeys(String body) =>
    RegExp(r"'(\w+)':").allMatches(body).map((m) => m.group(1)!).toSet();

/// Alle Klammerinhalte eines Aufrufs, überall im Quelltext.
///
/// [call] ist der Text unmittelbar vor der öffnenden Klammer, etwa
/// `scheduleExact` oder `mapOf`.
List<String> callBodies(String source, String call) {
  final out = <String>[];
  for (final m in RegExp('${RegExp.escape(call)}\\(').allMatches(source)) {
    out.add(balanced(source, m.end - 1, '(', ')'));
  }
  return out;
}

void main() {
  final mainActivity = withoutComments(kotlinFile('MainActivity'));
  final bridge = withoutComments(read('lib/platform/android_bridge.dart'));
  final handler = withoutComments(read('lib/platform/intent_handler.dart'));

  /// Der Block, in dem die Systemseite auf Aufrufe antwortet.
  final callHandler =
      mainActivity.substring(mainActivity.indexOf('setMethodCallHandler'),
          mainActivity.indexOf('else -> result.notImplemented()'));

  /// Methodenname → Argumentschlüssel, so wie Kotlin sie liest.
  final kotlinMethods = () {
    final branches = RegExp(r'^\s*"(\w+)" ->', multiLine: true)
        .allMatches(callHandler)
        .toList();
    return <String, Set<String>>{
      for (var i = 0; i < branches.length; i++)
        branches[i].group(1)!: RegExp(r'call\.argument<[^(]*>\("(\w+)"\)')
            .allMatches(callHandler.substring(
              branches[i].end,
              i + 1 < branches.length ? branches[i + 1].start : callHandler.length,
            ))
            .map((m) => m.group(1)!)
            .toSet(),
    };
  }();

  /// Methodenname → Argumentschlüssel, so wie Dart sie schickt.
  ///
  /// Erfasst beide Formen: den direkten `invoke…Method('name', {…})` und die
  /// Hüllen `_invoke`, `_outcome`, `_count` und `_invokeString`. Die
  /// generischen Fassungen dieser Hüllen fallen von selbst heraus — dort
  /// steht eine Variable statt eines Literals.
  final dartMethods = () {
    final out = <String, Set<String>>{};
    for (final source in [bridge, handler]) {
      final pattern = RegExp(
        r"(?:invoke(?:Method|MapMethod|ListMethod)<[^(]*>|"
        r"_(?:invokeString|invoke|outcome|count))\(\s*'(\w+)'",
      );
      for (final m in pattern.allMatches(source)) {
        final name = m.group(1)!;
        // Der Argumentblock steht im selben Aufruf: von dessen öffnender
        // Klammer bis zu ihrer Gegenstelle, und ein `{` unterwegs ist er.
        final open = source.indexOf('(', m.start);
        final body = balanced(source, open, '(', ')');
        final brace = body.indexOf('{');
        out[name] = brace < 0
            ? const <String>{}
            : dartMapKeys(balanced(body, brace, '{', '}'));
      }
    }
    return out;
  }();

  group('Der Kanal heißt überall gleich', () {
    test('Dart und Kotlin sprechen über denselben Namen', () {
      // Ein abweichender Kanalname ist der stillste aller Ausfälle: Jeder
      // Aufruf endet in `MissingPluginException`, jede Hülle fängt sie, und
      // auf dem Gerät funktioniert die App — nur ohne Systemfunktionen.
      final declared = RegExp(r'const val CHANNEL = "([^"]+)"')
          .firstMatch(mainActivity)!
          .group(1)!;
      expect(declared, 'de.atomfritte.axiom/system');
      for (final source in {'android_bridge': bridge, 'intent_handler': handler}
          .entries) {
        expect(
          RegExp(r"MethodChannel\('([^']+)'\)")
              .firstMatch(source.value)
              ?.group(1),
          declared,
          reason: source.key,
        );
      }
    });
  });

  group('Jeder Aufruf hat eine Gegenstelle', () {
    test('die Ausbeute beider Seiten ist nicht leer', () {
      // Sonst vergleicht der Rest dieser Gruppe zwei leere Mengen und meldet
      // grün, während das Muster längst ins Leere greift.
      expect(kotlinMethods.length, greaterThan(30));
      expect(dartMethods.length, greaterThan(30));
    });

    test('jede aufgerufene Methode wird auf der Systemseite beantwortet', () {
      // Ohne Zweig antwortet Kotlin mit `notImplemented`. Auf der Dart-Seite
      // wird daraus `false` oder eine leere Liste — also genau das, was auch
      // ein Gerät ohne die Funktion liefert. Der Unterschied zwischen „geht
      // hier nicht" und „heißt seit gestern anders" verschwindet damit.
      expect(
        dartMethods.keys.toSet().difference(kotlinMethods.keys.toSet()),
        isEmpty,
      );
    });

    test('keine Methode wartet auf einen Aufruf, den es nicht gibt', () {
      // Die andere Richtung. Ein Zweig ohne Aufrufer ist toter Code an der
      // heikelsten Stelle des Projekts — und meistens der Rest einer
      // Umbenennung, deren zweite Hälfte fehlt.
      //
      // `openDefaultApps` ist die einzige Ausnahme und bewusst: Es führt in
      // die Systemeinstellung „Standard-Apps". Solange die Notiz-Rolle auf
      // diesem Gerät gar nicht angeboten wird, wäre der Weg dorthin eine
      // Sackgasse (siehe `reason.notes.unavailable`), deshalb ruft ihn
      // niemand. Wächst diese Liste, ist das eine Entscheidung — und sie
      // soll sichtbar sein.
      expect(
        kotlinMethods.keys.toSet().difference(dartMethods.keys.toSet()),
        {'openDefaultApps'},
      );
    });

    test('jeder Parameter kommt unter dem Namen an, unter dem er losgeschickt '
        'wurde', () {
      // Ein umbenannter Schlüssel ist kein Fehler, sondern ein Standardwert:
      // `call.argument<String>("route")` gibt `null`, der Alarm landet auf
      // der Übersicht, und der Weg zur Handlung beginnt von vorn [D2].
      final mismatched = <String>[];
      dartMethods.forEach((method, sent) {
        final expected = kotlinMethods[method];
        if (expected == null) return;
        if (sent.difference(expected).isNotEmpty) {
          mismatched.add('$method: Dart schickt ${sent.difference(expected)}, '
              'Kotlin liest sie nicht');
        }
        if (expected.difference(sent).isNotEmpty) {
          mismatched.add('$method: Kotlin liest ${expected.difference(sent)}, '
              'Dart schickt sie nicht');
        }
      });
      expect(mismatched, isEmpty, reason: mismatched.join('\n'));
    });

    test('jede Antwort hat die Art, die der Aufrufer auspackt', () {
      // `invokeMethod<bool>` packt die Antwort mit `as bool?` aus. Schickt
      // Kotlin dort ein `Int`, wirft der Kanal einen TypeError — und `_invoke`
      // fängt jede Ausnahme und gibt `false` zurück. Die Funktion auf der
      // Systemseite ist dann gelaufen, die Dart-Seite meldet trotzdem
      // dauerhaft „hat nicht geklappt". Von außen ist das ein Fehlschlag, der
      // keiner ist.
      //
      // Aufgelöst wird, was auflösbar ist: ein Literal, oder eine Funktion,
      // die in diesen Quellen deklariert ist. Alles andere (`try`-Blöcke,
      // Aufrufe in Android-Klassen, Antworten aus einer Koroutine) bleibt
      // ungeprüft — mit einer Untergrenze darunter, damit die Prüfung nicht
      // unbemerkt auf null Zweige zusammenschrumpft.
      String? kindOfKotlinType(String type) {
        final t = type.trim();
        if (t == 'Boolean') return 'bool';
        if (t == 'Int' || t == 'Long') return 'int';
        if (t == 'String' || t == 'String?') return 'string';
        if (t.startsWith('Map')) return 'map';
        if (t.startsWith('List')) return 'list';
        return null;
      }

      /// Die Art, die eine Kotlin-Funktion dieses Namens zurückgibt — nur
      /// wenn alle gefundenen Deklarationen sich einig sind.
      String? kindOfFunction(String? receiver, String name) {
        final sources = <String>[];
        final own = File(
            'android/app/src/main/kotlin/de/atomfritte/axiom/$receiver.kt');
        if (receiver != null && own.existsSync()) {
          sources.add(own.readAsStringSync());
        } else {
          sources.addAll(kotlinFiles().map((f) => f.readAsStringSync()));
        }
        final kinds = <String?>{};
        for (final source in sources) {
          for (final m in RegExp('fun\\s+$name\\s*\\([^)]*\\)\\s*:\\s*([\\w<>?,. ]+)')
              .allMatches(source)) {
            kinds.add(kindOfKotlinType(m.group(1)!));
          }
        }
        return kinds.length == 1 ? kinds.single : null;
      }

      /// Was Kotlin in diesem Zweig beantwortet.
      String? kotlinKind(String body) {
        final call =
            RegExp(r'result\.success\(\s*(?:(\w+)\.)?(\w+)\s*\(').firstMatch(body);
        if (call != null) return kindOfFunction(call.group(1), call.group(2)!);
        if (RegExp(r'result\.success\(\s*(?:true|false)\s*\)').hasMatch(body)) {
          return 'bool';
        }
        return null;
      }

      /// Was die Dart-Seite auspackt.
      final dartKinds = <String, String>{};
      for (final source in [bridge, handler]) {
        for (final m in RegExp(
                r"(?:invokeMethod<(\w+)\??>|invoke(Map|List)Method<[^(]*>|"
                r"_(invokeString|invoke|outcome|count))\(\s*'(\w+)'")
            .allMatches(source)) {
          dartKinds[m.group(4)!] = switch ((m.group(1), m.group(2), m.group(3))) {
            (final type?, _, _) => {'int': 'int', 'String': 'string'}[type] ?? 'bool',
            (_, 'Map', _) => 'map',
            (_, 'List', _) => 'list',
            (_, _, 'invokeString') => 'string',
            (_, _, 'outcome') => 'map',
            (_, _, 'count') => 'int',
            _ => 'bool',
          };
        }
      }

      final branches = RegExp(r'^\s*"(\w+)" ->', multiLine: true)
          .allMatches(callHandler)
          .toList();
      final mismatched = <String>[];
      var checked = 0;
      for (var i = 0; i < branches.length; i++) {
        final name = branches[i].group(1)!;
        final expected = dartKinds[name];
        if (expected == null) continue;
        final actual = kotlinKind(callHandler.substring(
          branches[i].end,
          i + 1 < branches.length ? branches[i + 1].start : callHandler.length,
        ));
        if (actual == null) continue;
        checked++;
        if (actual != expected) {
          mismatched.add('$name: Kotlin antwortet $actual, '
              'Dart packt $expected aus');
        }
      }
      expect(checked, greaterThan(20), reason: 'zu wenige Zweige aufgelöst');
      expect(mismatched, isEmpty, reason: mismatched.join('\n'));
    });

    test('die Argumente sind wirklich gelesen worden, nicht nur gezählt', () {
      // Der Wächter über dem Wächter: Wäre der Argument-Ausdruck kaputt,
      // verglichen oben lauter leere Mengen miteinander.
      expect(dartMethods['scheduleExact'],
          {'id', 'atMillis', 'title', 'body', 'channel', 'route'});
      expect(kotlinMethods['scheduleExact'], dartMethods['scheduleExact']);
      expect(dartMethods['liveSlotStart'],
          {'kind', 'title', 'detail', 'startedAtMillis', 'plannedMinutes'});
      expect(dartMethods['ping'], isEmpty);
    });
  });

  group('Jede Antwort wird so gelesen, wie sie gemeint ist', () {
    /// Was die Systemseite liefert, gegen das, was die Oberfläche davon
    /// liest. Ein Schlüssel, den nur der Leser kennt, ist `null` — und `null`
    /// sieht im Systemcheck aus wie eine fehlende Freigabe.
    void contract({
      required String name,
      required Set<String> produced,
      required Set<String> consumed,
    }) {
      expect(produced, isNotEmpty, reason: '$name: nichts geliefert gefunden');
      expect(consumed, isNotEmpty, reason: '$name: nichts gelesen gefunden');
      expect(consumed.difference(produced), isEmpty,
          reason: '$name: gelesen, aber nie geliefert');
    }

    test('der Systemcheck liest nur Werte, die es gibt', () {
      final screen = withoutComments(read('lib/screens/check_screen.dart'));
      contract(
        name: 'diagnostics',
        produced: kotlinMapKeys(kotlinFunction(mainActivity, 'diagnostics')),
        consumed: {
          for (final m in RegExp(r"_values\['(\w+)'\]").allMatches(screen))
            m.group(1)!,
          for (final m in RegExp(r"_flag\('(\w+)'\)").allMatches(screen))
            m.group(1)!,
        },
      );
    });

    test('die Fehlersuche zur dauerhaften Anzeige liest nur Werte, die es gibt',
        () {
      final screen = withoutComments(read('lib/screens/channels_screen.dart'));
      contract(
        name: 'presenceDiagnosis',
        produced: kotlinMapKeys(
            kotlinFunction(withoutComments(kotlinFile('PresenceService')),
                'diagnosis')),
        consumed: {
          for (final m in RegExp(r"report\['(\w+)'\]").allMatches(screen))
            m.group(1)!,
          for (final m in RegExp(r"_yes\('(\w+)'\)").allMatches(screen))
            m.group(1)!,
          // `reason` kommt nicht aus der Diagnose, sondern aus dem
          // Startergebnis daneben — die Oberfläche legt es selbst dazu.
        }..remove('reason'),
      );
    });

    test('die Berechtigungsabfrage liest nur Werte, die es gibt', () {
      final screen = withoutComments(read('lib/screens/channels_screen.dart'));
      contract(
        name: 'permissionStatus',
        produced: kotlinMapKeys(kotlinFunction(mainActivity, 'permissionStatus')),
        consumed: {
          for (final m in RegExp(r"permissions\['(\w+)'\]").allMatches(screen))
            m.group(1)!,
        },
      );
    });

    test('Health Connect meldet die Zustände, die die App unterscheidet', () {
      // Drei Zustände: nicht vorhanden, veraltet, nicht freigegeben. Fehlt
      // `needsUpdate`, wird aus „aktualisieren" ein „gibt es hier nicht" —
      // und der Nutzer sucht eine Funktion, die eine Aktualisierung entfernt.
      final health = withoutComments(read('lib/platform/health_sync.dart'));
      contract(
        name: 'healthStatus',
        produced: kotlinMapKeys(
            kotlinFunction(withoutComments(kotlinFile('HealthBridge')), 'status')),
        consumed: {
          for (final m in RegExp(r"status\['(\w+)'\]").allMatches(health))
            m.group(1)!,
        },
      );
    });

    test('ein Health-Datensatz trägt die Felder, die der Import erwartet', () {
      // Die einzige Datenquelle, die AXIOM nicht selbst erzeugt. Ein
      // umbenanntes Feld heißt hier: keine Schlafdaten mehr, ohne Meldung —
      // `plan` überspringt jeden Datensatz ohne `sourceId` stillschweigend.
      final health = withoutComments(read('lib/platform/health_sync.dart'));
      contract(
        name: 'healthRead',
        produced: kotlinMapKeys(
            kotlinFunction(withoutComments(kotlinFile('HealthBridge')), 'read')),
        consumed: {
          for (final m in RegExp(r"record\['(\w+)'\]").allMatches(health))
            m.group(1)!,
        },
      );
    });

    test('ein empfangener Ort trägt die Felder, die der Einsammler liest', () {
      contract(
        name: 'peekPendingPlaces',
        produced: kotlinMapKeys(
            kotlinFunction(withoutComments(kotlinFile('PlaceReceiver')), 'peek')),
        consumed: {
          for (final m in RegExp(r"entry\['(\w+)'\]").allMatches(handler))
            m.group(1)!,
        },
      );
    });

    test('die Antwort auf den Datenbankschlüssel hat die erwartete Form', () {
      // Der teuerste Vertrag im Projekt: Wird `state` nicht gelesen, gilt
      // jede Antwort als „unklar" — und die App startet nie wieder. Wird er
      // falsch gelesen, gilt sie als „hier gibt es keine Verschlüsselung",
      // und die verschlüsselte Datei wird für kaputt gehalten.
      final key = withoutComments(kotlinFile('DatabaseKey'));
      contract(
        name: 'databaseKey',
        produced: {
          for (final body in callBodies(key, 'mapOf')) ...kotlinMapKeys(body),
        },
        consumed: {
          for (final m in RegExp(r"message\?\['(\w+)'\]").allMatches(bridge))
            m.group(1)!,
        },
      );

      // Und die beiden Werte, an denen die Entscheidung hängt. Was die
      // Dart-Seite daraus macht, prüft `database_key_test` an der Wahrheits-
      // tabelle; hier steht nur, dass die Systemseite dieselben zwei Wörter
      // schickt. Ein umbenannter Zustand fiele dort in den Zweig „unklar" —
      // und der öffnet die Datenbank absichtlich nicht mehr.
      expect(kotlinConstant(key, 'STATE_READY'), 'ready');
      expect(kotlinConstant(key, 'STATE_NONE'), 'none');
    });

    test('ein Fehlschlag meldet nur Felder, die auch ausgewertet werden', () {
      // Jede Kotlin-Map mit `"ok"` ist die Antwort auf einen Aufruf, den
      // `_outcome` auswertet. Ein viertes Feld darin wäre eine Aussage der
      // Systemseite, die niemand liest — und der Knopf bliebe wieder stumm.
      final produced = <String>{};
      for (final file in kotlinFiles()) {
        for (final body
            in callBodies(withoutComments(file.readAsStringSync()), 'mapOf')) {
          if (!body.contains('"ok" to')) continue;
          produced.addAll(kotlinMapKeys(body));
        }
      }
      expect(produced, isNotEmpty);
      final consumed = {
        for (final m in RegExp(r"result\['(\w+)'\]").allMatches(bridge))
          m.group(1)!,
      };
      expect(consumed, {'ok', 'reason', 'reasonArgs'});
      expect(produced.difference(consumed), isEmpty);
    });
  });

  group('Jede Benachrichtigung führt an ihr Ziel', () {
    /// Die Aktionen, die `AxiomRoute` benennt.
    final routes = () {
      final block = bridge.substring(bridge.indexOf('class AxiomRoute'));
      return {
        for (final m in RegExp(r"static const \w+ = '([^']+)';")
            .allMatches(block.substring(0, block.indexOf('\n}'))))
          m.group(1)!,
      };
    }();

    /// Was `consumeLaunchAction` durchlässt.
    final whitelist = () {
      final body = kotlinFunction(mainActivity, 'consumeLaunchAction');
      final out = {
        for (final m in RegExp(r'"(de\.atomfritte\.axiom\.[A-Z_]+)"')
            .allMatches(body))
          m.group(1)!,
      };
      // Konstanten aus anderen Klassen auflösen, sonst fehlt hier genau der
      // Eintrag, der nicht als Literal dasteht. `Intent.ACTION_MAIN` gehört
      // Android und hat hier keine Datei — das ist der Rückfall, wenn kein
      // Ziel mitkam, und kein eigenes Ziel.
      for (final m in RegExp(r'(\w+)\.(ACTION_\w+)').allMatches(body)) {
        final file = File(
            'android/app/src/main/kotlin/de/atomfritte/axiom/${m.group(1)}.kt');
        if (!file.existsSync()) continue;
        out.add(kotlinConstant(file.readAsStringSync(), m.group(2)!));
      }
      return out;
    }();

    /// Was die Dart-Seite mit einer Startaktion anfängt.
    final handled = () {
      final block = handler.substring(handler.indexOf("switch (action)"));
      final out = {
        for (final m in RegExp(r"case '([^']+)':").allMatches(block))
          m.group(1)!,
      };
      for (final m in RegExp(r'case AxiomRoute\.(\w+):').allMatches(block)) {
        final value = RegExp("static const ${m.group(1)} = '([^']+)';")
            .firstMatch(bridge)
            ?.group(1);
        if (value == null) throw StateError('AxiomRoute.${m.group(1)}');
        out.add(value);
      }
      return out;
    }();

    test('die Ausbeute ist nicht leer', () {
      expect(routes.length, greaterThan(5));
      expect(whitelist.length, greaterThan(5));
      expect(handled.length, greaterThan(5));
    });

    test('jedes Ziel, das die App kennt, wird auch angenommen', () {
      // Eine Route, die die Startliste nicht kennt, landet stumm auf der
      // Übersicht — funktionierend genug, um nicht aufzufallen.
      expect(routes.difference(whitelist), isEmpty);
    });

    test('jedes Ziel, das die App kennt, führt auch irgendwohin', () {
      // Ein Anstoß, der auf der Übersicht endet, ist kein Anstoß [D2].
      expect(routes.difference(handled), isEmpty);
    });

    test('jede angenommene Aktion wird auch behandelt', () {
      // Die Startliste ist die Tür. Was sie durchlässt und danach niemand
      // aufgreift, ist eine Benachrichtigung, die kommentarlos ins Leere
      // führt.
      expect(whitelist.difference(handled), isEmpty);
    });

    test('jede Aktion, die die Systemseite an die App schickt, ist zugelassen',
        () {
      // Die dritte Richtung, und die einzige, die bisher niemand geprüft hat:
      // Nicht die App schickt hier, sondern Kotlin selbst — die Präsenz, der
      // laufende Slot, die Schnelleinstellung, das Widget, das Teilen-Ziel.
      // Steht deren Aktion nicht in der Startliste, öffnet der Knopf die App
      // und sonst nichts.
      final sent = <String>{};
      for (final file in kotlinFiles()) {
        final source = withoutComments(file.readAsStringSync());
        for (final m in RegExp(r'\.setAction\(').allMatches(source)) {
          // Die zuletzt genannte Klasse entscheidet, wohin der Intent geht.
          final owner = RegExp(r'(\w+)::class\.java')
              .allMatches(source.substring(0, m.start))
              .lastOrNull
              ?.group(1);
          if (owner != 'MainActivity') continue;
          final argument = balanced(source, m.end - 1, '(', ')');
          sent.addAll(RegExp(r'"(de\.atomfritte\.axiom\.[A-Z_]+)"')
              .allMatches(argument)
              .map((a) => a.group(1)!));
          for (final name in RegExp(r'\b(ACTION_\w+)\b').allMatches(argument)) {
            final value = RegExp('const val ${name.group(1)} = "([^"]+)"')
                .firstMatch(source)
                ?.group(1);
            // `Intent.ACTION_MAIN` hat hier keine Entsprechung — das ist der
            // Rückfall, wenn kein Ziel mitkam, und kein eigenes Ziel.
            if (value != null) sent.add(value);
          }
        }
      }
      expect(sent.length, greaterThan(3));
      expect(sent.difference(whitelist), isEmpty);
    });

    test('jeder Benachrichtigungskanal, in den geplant wird, existiert', () {
      // Android verwirft eine Benachrichtigung mit unbekannter Kanal-ID
      // kommentarlos. Der Alarm feuert, die Erinnerung erscheint nie.
      final created = {
        for (final m in RegExp(r'ChannelSpec\("(\w+)"').allMatches(mainActivity))
          m.group(1)!,
        for (final file in kotlinFiles())
          ...RegExp(r'const val CHANNEL = "(axiom_\w+)"')
              .allMatches(file.readAsStringSync())
              .map((m) => m.group(1)!),
      };
      final used = <String>{};
      for (final file in dartFiles()) {
        final source = withoutComments(file.readAsStringSync());
        for (final body in callBodies(source, 'scheduleExact')) {
          used.addAll(RegExp(r"'(axiom_\w+)'")
              .allMatches(body)
              .map((m) => m.group(1)!));
        }
        used.addAll(RegExp(r"String channel = '(axiom_\w+)'")
            .allMatches(source)
            .map((m) => m.group(1)!));
      }
      expect(created.length, greaterThanOrEqualTo(7));
      expect(used.length, greaterThan(1));
      expect(used.difference(created), isEmpty);
    });
  });

  group('Das Manifest und die Klassen dahinter', () {
    final manifest = androidFile('AndroidManifest.xml');

    /// Klassen, die Android nur über ihren Namen im Manifest findet.
    final declared = RegExp(r'android:name="\.(\w+)"')
        .allMatches(manifest)
        .map((m) => m.group(1)!)
        .toSet();

    test('jede deklarierte Komponente gibt es auch', () {
      // Das Manifest wird nicht kompiliert. Ein Tippfehler hier fällt beim
      // Bauen nicht auf, sondern auf dem Gerät — als `ClassNotFoundException`
      // in einem Prozess, den niemand beobachtet.
      expect(declared.length, greaterThan(8));
      for (final name in declared) {
        expect(File('android/app/src/main/kotlin/de/atomfritte/axiom/$name.kt')
            .existsSync(), isTrue,
            reason: '$name steht im Manifest, aber es gibt keine Klasse dazu');
      }
    });

    test('jede Systemkomponente steht auch im Manifest', () {
      // Die andere Richtung. Eine Activity, ein Dienst oder ein Empfänger
      // ohne Eintrag wird vom System nie aufgerufen — kein Fehler, keine
      // Meldung, die Funktion fehlt einfach.
      const bases = {
        'FlutterActivity',
        'Activity',
        'Service',
        'BroadcastReceiver',
        'AppWidgetProvider',
        'TileService',
      };
      final components = <String>{};
      for (final file in kotlinFiles()) {
        for (final m in RegExp(r'^class (\w+)\s*:\s*(\w+)\(',
                multiLine: true)
            .allMatches(file.readAsStringSync())) {
          if (bases.contains(m.group(2))) components.add(m.group(1)!);
        }
      }
      expect(components.length, greaterThan(8));
      expect(components.difference(declared), isEmpty);
    });

    test('der Ortsempfänger hört auf genau die Aktion, die er kennt', () {
      // Die Konstante steht in Kotlin, der Filter im Manifest. Weichen sie
      // voneinander ab, kommt der Broadcast einer Geräteroutine nie an —
      // und aus der Ferne sieht das aus wie eine kaputte Routine.
      final action = RegExp(r'const val ACTION = "([^"]+)"')
          .firstMatch(kotlinFile('PlaceReceiver'))!
          .group(1)!;
      final block = manifest.substring(manifest.indexOf('.PlaceReceiver'));
      expect(block.substring(0, block.indexOf('</receiver>')),
          contains('<action android:name="$action" />'));
    });
  });
}
