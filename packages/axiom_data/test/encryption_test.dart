/// Was auf der Platte liegt, wenn niemand hinsieht.
///
/// Die Zusage lautet nicht „wir benutzen eine Verschluesselungsbibliothek",
/// sondern „ohne Schluessel ist die Datei nicht lesbar". Genau das wird hier
/// geprueft, und zwar an der Datei — nicht an einer Einstellung der
/// Verbindung, die etwas anderes behaupten koennte.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late FakeClock clock;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('axiom_crypt');
    clock = FakeClock(DateTime.utc(2026, 8, 5, 12));
    path = '${dir.path}/axiom.db';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Legt einen erkennbaren Inhalt ab und schliesst wieder.
  Future<void> write(String? key, String marker) async {
    final store =
        SqliteEventStore.open(path, clock: clock, encryptionKey: key);
    await store.append(Event(
      id: 'e1',
      at: clock.nowUtc(),
      type: EventType.capture,
      source: EventSource.user,
      payload: {'text': marker},
    ));
    store.close();
  }

  group('Verschluesselte Datenbank', () {
    test('der Inhalt steht nicht im Klartext in der Datei', () async {
      await write('schluessel-fuer-den-test', 'GEHEIMER_GEDANKE');

      final bytes = File(path).readAsBytesSync();
      expect(
        String.fromCharCodes(bytes).contains('GEHEIMER_GEDANKE'),
        isFalse,
        reason: 'Der erfasste Text liegt lesbar in der Datei',
      );
    });

    test('ohne Schluessel laesst sie sich nicht oeffnen', () async {
      await write('schluessel-fuer-den-test', 'egal');

      expect(
        () => SqliteEventStore.open(path, clock: clock),
        throwsA(isA<DatabaseUnreadable>()),
      );
    });

    test('mit dem falschen Schluessel auch nicht', () async {
      await write('richtig', 'egal');

      expect(
        () => SqliteEventStore.open(path, clock: clock, encryptionKey: 'falsch'),
        throwsA(isA<DatabaseUnreadable>()),
      );
    });

    test('mit dem richtigen Schluessel steht alles wieder da', () async {
      await write('richtig', 'GEHEIMER_GEDANKE');

      final store =
          SqliteEventStore.open(path, clock: clock, encryptionKey: 'richtig');
      addTearDown(store.close);
      final events = await store.query();
      expect(events, hasLength(1));
      expect(events.single.payload['text'], 'GEHEIMER_GEDANKE');
    });

    test('ein Anfuehrungszeichen im Schluessel bricht nichts', () async {
      // Der Schluessel geht als Zeichenkette in ein PRAGMA. Kaeme er
      // ungeschuetzt dort an, waere ein Apostroph ein Syntaxfehler — und im
      // schlimmeren Fall eine Stelle, an der sich Anweisungen anhaengen
      // lassen. Der Keystore liefert Base64, aber diese Zusage soll nicht
      // davon abhaengen, was der Keystore gerade liefert.
      const awkward = "hat'ein'Zeichen";
      await write(awkward, 'GEHEIMER_GEDANKE');

      final store =
          SqliteEventStore.open(path, clock: clock, encryptionKey: awkward);
      addTearDown(store.close);
      expect((await store.query()).single.payload['text'], 'GEHEIMER_GEDANKE');
    });
  });

  group('isEncrypted meldet den Zustand der Datei', () {
    test('verschluesselt angelegt: true', () async {
      await write('richtig', 'egal');
      final store =
          SqliteEventStore.open(path, clock: clock, encryptionKey: 'richtig');
      addTearDown(store.close);
      expect(store.isEncrypted, isTrue);
    });

    test('ohne Schluessel angelegt: false', () async {
      // Der Normalfall auf dem Linux-Rechner. Er soll sich melden, nicht
      // stillschweigend als geschuetzt durchgehen.
      await write(null, 'egal');
      final store = SqliteEventStore.open(path, clock: clock);
      addTearDown(store.close);
      expect(store.isEncrypted, isFalse);
    });

    test('im Arbeitsspeicher: false, weil nichts liegt', () {
      final store = SqliteEventStore.inMemory(clock: clock);
      addTearDown(store.close);
      expect(store.isEncrypted, isFalse);
    });

    test('gemeldet wird die Datei, nicht die eingestellte Chiffre', () async {
      // Zwei frühere Fassungen fragten die Verbindung: `PRAGMA cipher_version`
      // (kennt nur SQLCipher, antwortet hier nie) und `PRAGMA cipher` (nennt
      // immer die Voreinstellung `chacha20`, auch bei offener Datei). Beide
      // haetten hier `true` gemeldet — bei einer Datei, die im Klartext
      // dasteht. Der Test faengt genau diesen Rueckschritt.
      await write(null, 'LESBAR_IM_KLARTEXT');
      final store = SqliteEventStore.open(path, clock: clock);
      addTearDown(store.close);

      expect(store.isEncrypted, isFalse);
      expect(
        String.fromCharCodes(File(path).readAsBytesSync())
            .contains('LESBAR_IM_KLARTEXT'),
        isTrue,
        reason: 'Ohne Schluessel muss der Inhalt lesbar sein — sonst prueft '
            'dieser Test etwas anderes als er soll',
      );
    });
  });

  group('Altbestand', () {
    test('eine unverschluesselte Datei wird als unlesbar gemeldet', () async {
      // Der Weg, den ein Geraet nimmt, auf dem die vorherige Fassung lief.
      // Der Aufrufer entscheidet, was dann passiert; diese Schicht loescht
      // nichts von sich aus.
      await write(null, 'ALTBESTAND');
      expect(File(path).existsSync(), isTrue);

      expect(
        () => SqliteEventStore.open(path, clock: clock, encryptionKey: 'neu'),
        throwsA(isA<DatabaseUnreadable>()),
      );
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Die Speicherschicht darf nichts wegwerfen',
      );
    });
  });
}
