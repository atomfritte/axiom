/// Prueft das echte Regelwerk auf Zwillinge.
///
/// **Warum es diesen Test gibt.** R-080 („Wind-Down-Grenze") und R-110
/// („Abendgrenze") waren dieselbe Regel: gleiche Aktion, gleiche Parameter,
/// gleiche Severity, gleiches Defizit, ueberlappendes Zeitfenster — nur
/// verschiedene IDs und verschiedene Prioritaeten. Der Verlierer eines
/// Konflikts wird mit `suppressed` gespeichert und bekommt deshalb kein
/// `lastFired`; sobald der Gewinner im Cooldown steht, gibt der Zwilling
/// dieselbe Aufforderung ein zweites Mal aus — unter anderem Titel und mit
/// anderer `rule_id`. Das ist nicht nur Rauschen (R2), es widerspricht G2:
/// dieselbe Handlung mit zwei verschiedenen Begruendungen.
///
/// **Warum so eng geschnitten.** Zwei Regeln duerfen dieselbe Aktion tragen —
/// R-070 und R-100 bitten beide um Wasser und Bewegung, aber aus
/// verschiedenen Anlaessen (Hyperfokus / Vormittag ohne Koerpersignal). Der
/// Test schlaegt erst an, wenn auch der *Anlass* derselbe ist: Nach Abzug der
/// Uhrzeiten bleibt derselbe Bedingungsbaum. Dann sind es zwei Namen fuer
/// eine Regel.
library;

import 'dart:convert';
import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

/// Laedt das echte Regelwerk aus rules/ — kein Mock.
Map<String, String> realRules() {
  final root = Directory('../../rules');
  final map = <String, String>{};
  if (!root.existsSync()) return map;
  for (final file in root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))) {
    map[file.path.split('/').sublist(2).join('/')] = file.readAsStringSync();
  }
  return map;
}

/// Alle Zeitfenster eines Bedingungsbaums, in Minuten seit Mitternacht.
List<(int, int)> timeWindows(Condition c) => switch (c) {
      TimeBetween() => [(c.fromMinutes, c.toMinutes)],
      AllOf() => c.children.expand(timeWindows).toList(),
      AnyOf() => c.children.expand(timeWindows).toList(),
      NotCond() => timeWindows(c.child),
      _ => const [],
    };

/// Der Bedingungsbaum ohne seine Uhrzeiten.
///
/// Zwei Regeln mit demselben Rest und ueberlappenden Fenstern beschreiben
/// denselben Anlass; die Fensterbreite ist dann nur noch ein Detail.
Object? withoutTimes(Condition c) => switch (c) {
      TimeBetween() => null,
      AllOf() => {
          'all': c.children.map(withoutTimes).where((e) => e != null).toList()
        },
      AnyOf() => {
          'any': c.children.map(withoutTimes).where((e) => e != null).toList()
        },
      NotCond() => switch (withoutTimes(c.child)) {
          final inner? => {'not': inner},
          _ => null,
        },
      _ => c.toMap(),
    };

/// Ueberlappen zwei Fenster? Ein Fenster ueber Mitternacht wird geteilt.
bool overlaps((int, int) a, (int, int) b) {
  List<(int, int)> split((int, int) w) =>
      w.$1 <= w.$2 ? [w] : [(w.$1, 1440), (0, w.$2)];
  for (final x in split(a)) {
    for (final y in split(b)) {
      if (x.$1 < y.$2 && y.$1 < x.$2) return true;
    }
  }
  return false;
}

String canonical(Object? value) => jsonEncode(value, toEncodable: (v) => '$v');

void main() {
  group('Echtes Regelwerk', () {
    test('keine zwei Regeln geben dieselbe Aufforderung aus demselben Anlass',
        () {
      final sources = realRules();
      if (sources.isEmpty) {
        markTestSkipped('rules/ nicht gefunden');
        return;
      }
      final rules = YamlRuleSource(sources)
          .parse()
          .rules
          .where((r) => r.enabled && !r.isShadow)
          .toList();

      final twins = <String>[];
      for (var i = 0; i < rules.length; i++) {
        for (var j = i + 1; j < rules.length; j++) {
          final a = rules[i];
          final b = rules[j];
          if (a.then.type != b.then.type) continue;
          if (canonical(a.then.params) != canonical(b.then.params)) continue;
          if (a.severity != b.severity) continue;
          if (canonical(withoutTimes(a.when)) !=
              canonical(withoutTimes(b.when))) {
            continue;
          }
          final wa = timeWindows(a.when);
          final wb = timeWindows(b.when);
          // Ohne Zeitbedingung gilt die Regel den ganzen Tag.
          final full = [(0, 1440)];
          final overlapping = (wa.isEmpty ? full : wa).any(
            (x) => (wb.isEmpty ? full : wb).any((y) => overlaps(x, y)),
          );
          if (overlapping) {
            twins.add('${a.id} "${a.title}"  ==  ${b.id} "${b.title}"');
          }
        }
      }

      expect(
        twins,
        isEmpty,
        reason: 'Zwei Regeln mit derselben Aktion, denselben Parametern und '
            'demselben Anlass geben dieselbe Aufforderung zweimal aus — die '
            'zweite, sobald die erste im Cooldown steht. Eine davon '
            'streichen; die ID bleibt verbrannt (CLAUDE.md).\n'
            '${twins.join("\n")}',
      );
    });

    test('der Waechter erkennt einen Zwilling, wenn es einen gibt', () {
      // Ein Test, der nie anschlaegt, ist von einem kaputten nicht zu
      // unterscheiden. Hier stehen die beiden Faelle nebeneinander, die der
      // Schnitt trennen muss: derselbe Anlass (Zwilling) und derselbe
      // Wortlaut aus verschiedenen Anlaessen (erlaubt).
      final twin = YamlRuleSource({
        'a.yaml': '''
- id: R-901
  title: "Abendgrenze"
  rationale: "Begruendung lang genug fuer den Validator, damit er laedt."
  when: { all: [ { time_between: ["22:30", "23:30"] } ] }
  then: { action: notify, params: { ritual: winddown } }
  priority: 70
  severity: nudge
  cooldown: { minutes: 720, max_per_day: 1 }
- id: R-902
  title: "Wind-Down"
  rationale: "Begruendung lang genug fuer den Validator, damit er laedt."
  when: { all: [ { time_between: ["22:30", "23:15"] } ] }
  then: { action: notify, params: { ritual: winddown } }
  priority: 60
  severity: nudge
  cooldown: { minutes: 720, max_per_day: 1 }
''',
      }).parse().rules;

      expect(canonical(withoutTimes(twin[0].when)),
          canonical(withoutTimes(twin[1].when)));
      expect(overlaps(timeWindows(twin[0].when).single,
          timeWindows(twin[1].when).single), isTrue);

      // Und die Gegenprobe: gleiche Aktion, anderer Anlass — kein Zwilling.
      final siblings = YamlRuleSource({
        'b.yaml': '''
- id: R-903
  title: "Trinken im Hyperfokus"
  rationale: "Begruendung lang genug fuer den Validator, damit er laedt."
  when:
    all:
      - active_slot: { eq: focus }
      - time_between: ["07:00", "22:00"]
  then: { action: notify, params: { kind: water_move } }
  priority: 55
  severity: nudge
  cooldown: { minutes: 120, max_per_day: 3 }
- id: R-904
  title: "Trinken am Vormittag"
  rationale: "Begruendung lang genug fuer den Validator, damit er laedt."
  when:
    all:
      - count_today: { event: body_prompt, lt: 2 }
      - time_between: ["10:30", "11:15"]
  then: { action: notify, params: { kind: water_move } }
  priority: 40
  severity: nudge
  cooldown: { minutes: 120, max_per_day: 1 }
''',
      }).parse().rules;

      expect(canonical(withoutTimes(siblings[0].when)),
          isNot(canonical(withoutTimes(siblings[1].when))));
    });
  });
}
