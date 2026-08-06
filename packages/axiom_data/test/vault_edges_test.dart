/// Die Raender des Vault-Umlaufs.
///
/// `vault_test.dart` haelt den geraden Weg fest: exportieren, einspielen,
/// zweimal einspielen, falsches Kennwort. Diese Datei nimmt sich das, was
/// daneben liegt — die leere Datenbank, die sehr grosse Datei, die
/// abgeschnittene, die manipulierte, die fremde Tabelle und den Rueckweg in
/// dieselbe Datenbank.
///
/// Der Massstab ist ueberall derselbe und steht in `vault.dart`: Ein Import
/// darf nichts ueberschreiben, und wenn er scheitert, darf er **nichts**
/// hinterlassen haben. Eine halb eingespielte Datei waere schlimmer als eine
/// abgelehnte, weil man ihr nicht ansieht, dass sie halb ist.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;
  late Vault vault;

  const pass = 'ein-langes-kennwort';

  setUp(() {
    clock = FakeClock(DateTime(2026, 8, 3, 10));
    store = SqliteEventStore.inMemory(clock: clock);
    vault = Vault(store: store, clock: clock, kdfRounds: 200);
  });
  tearDown(() => store.close());

  SqliteEventStore target() {
    final s = SqliteEventStore.inMemory(clock: clock);
    addTearDown(s.close);
    return s;
  }

  Vault vaultFor(SqliteEventStore s) =>
      Vault(store: s, clock: clock, kdfRounds: 200);

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: {'text': 'Notiz $i'},
      ));
      clock.advance(const Duration(minutes: 7));
    }
  }

  /// Baut eine Datei aus fertigen Klartextzeilen — so lassen sich Inhalte
  /// pruefen, die kein Export je erzeugen wuerde.
  Uint8List file(List<Object> lines, {int format = kVaultFormat}) {
    final manifest = jsonEncode({
      'schema': '$kSchemaVersion',
      'format': format,
      'created_at': clock.nowUtc().toIso8601String(),
      'events': 0,
      'tables': kVaultTables,
    });
    return vault.seal(
      '$manifest\n${lines.map(jsonEncode).join('\n')}\n',
      pass,
    );
  }

  group('Eine leere Datenbank', () {
    test('ergibt eine Datei, die sich einspielen lässt', () async {
      final blob = await vault.export(passphrase: pass);
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(data: blob, passphrase: pass);

      expect(ergebnis.imported, 0);
      expect(ergebnis.rejected, 0);
      expect(ergebnis.rowsImported, 0);
      expect(await ziel.eventCount(), 0);
    });

    test('eine leere Tabelle erzeugt keine Zeile, steht aber im Manifest',
        () async {
      // Der Unterschied ist wichtig: „keine Anker" und „Anker wandern nicht
      // mit" sehen in der Datei sonst gleich aus.
      final text = await vault.buildPlaintext();
      expect(text, isNot(contains('"table":"anchors"')));

      final manifest = VaultManifest.fromJson(
        jsonDecode(text.trim().split('\n').first) as Map<String, Object?>,
      );
      expect(manifest.tables, contains('anchors'));
    });

    test('ein versiegelter Leertext wird als leere Datei gemeldet', () async {
      await expectLater(
        vault.import(data: vault.seal('', pass), passphrase: pass),
        throwsA(isA<VaultError>()),
      );
    });
  });

  group('Eine sehr große Datei', () {
    test('überlebt den Umlauf Zeichen für Zeichen', () async {
      // Der Stromchiffre arbeitet blockweise über einen Zähler. Ein Fehler
      // darin fällt erst jenseits des ersten Blocks auf — ein Megabyte sind
      // rund 32.000 Blöcke.
      final lang = 'A' * (1024 * 1024);
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: {'text': lang},
      ));
      await seed(200);

      final blob = await vault.export(passphrase: pass);
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(data: blob, passphrase: pass);

      expect(ergebnis.imported, 201);
      expect(ergebnis.rejected, 0);
      final wieder = await ziel.query(types: {EventType.capture});
      expect(wieder.first.payload['text'], lang);
    });
  });

  group('Eine beschädigte Datei', () {
    late Uint8List blob;

    setUp(() async {
      await seed(4);
      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));
      blob = await vault.export(passphrase: pass);
    });

    Future<void> abgelehnt(Uint8List kaputt) async {
      final ziel = target();
      await expectLater(
        vaultFor(ziel).import(data: kaputt, passphrase: pass),
        throwsA(isA<VaultError>()),
      );
      // Wichtiger als die Meldung: Es darf nichts halb dastehen.
      expect(await ziel.eventCount(), 0);
      expect(await ziel.anchors(), isEmpty);
    }

    test('hinten abgeschnitten', () => abgelehnt(blob.sublist(0, blob.length - 10)));

    test('in der Mitte herausgeschnitten', () {
      final kurz = Uint8List.fromList([
        ...blob.sublist(0, 100),
        ...blob.sublist(140),
      ]);
      return abgelehnt(kurz);
    });

    test('nur der Kopf, sonst nichts', () {
      // Genau die Mindestlänge: Kennung + Salz + Nonce + Prüfsumme. Die
      // Längenprüfung greift hier nicht mehr, die Prüfsumme muss es tun.
      return abgelehnt(blob.sublist(0, kVaultMagic.length + 16 + 16 + 32));
    });

    test('mit angehängten Bytes', () {
      return abgelehnt(Uint8List.fromList([...blob, 0, 1, 2, 3, 4]));
    });

    for (final (name, index) in [
      ('im Salz', kVaultMagic.length + 2),
      ('in der Nonce', kVaultMagic.length + 20),
      ('im Chiffrat', kVaultMagic.length + 40),
    ]) {
      test('ein gekipptes Bit $name', () {
        final kaputt = Uint8List.fromList(blob);
        kaputt[index] ^= 0x01;
        return abgelehnt(kaputt);
      });
    }

    test('eine gefälschte Prüfsumme', () {
      final kaputt = Uint8List.fromList(blob);
      kaputt[kaputt.length - 1] ^= 0x80;
      return abgelehnt(kaputt);
    });

    test('ein verändertes Dateikennzeichen gilt als fremde Datei', () async {
      final kaputt = Uint8List.fromList(blob);
      kaputt[0] ^= 0x01;
      final ziel = target();
      await expectLater(
        vaultFor(ziel).import(data: kaputt, passphrase: pass),
        throwsA(predicate<VaultError>(
            (e) => e.message.contains('Keine AXIOM-Exportdatei'))),
      );
    });

    test('ein falsches Kennwort ist von einer veränderten Datei nicht zu '
        'unterscheiden — und das ist richtig so', () async {
      final ziel = target();
      await expectLater(
        vaultFor(ziel).import(data: blob, passphrase: 'anderes-kennwort'),
        throwsA(predicate<VaultError>((e) =>
            e.message.contains('Kennwort falsch oder Datei verändert'))),
      );
      expect(await ziel.eventCount(), 0);
    });

    test('ein leeres Kennwort spielt nichts ein', () async {
      final ziel = target();
      await expectLater(
        vaultFor(ziel).import(data: blob, passphrase: ''),
        throwsA(isA<VaultError>()),
      );
      expect(await ziel.eventCount(), 0);
    });
  });

  group('Eine manipulierte Datei mit gültiger Prüfsumme', () {
    // Der Fall, den die Kryptografie nicht abdeckt: Wer das Kennwort kennt,
    // kann hineinschreiben, was er will. Ab hier trägt nur noch der Import
    // selbst.

    test('ein fremder Tabellenname geht nie in SQL', () async {
      final ziel = target();
      await ziel.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'bleibt'},
      ));

      final ergebnis = await vaultFor(ziel).import(
        data: file([
          {
            'table': "settings' ; DROP TABLE events; --",
            'row': {'key': 'x', 'value': 'y'},
          },
        ]),
        passphrase: pass,
      );

      expect(ergebnis.rejected, 1);
      expect(ergebnis.rowsImported, 0);
      expect(await ziel.eventCount(), 1);
    });

    test('ein erfundener Spaltenname wird weggelassen, die Zeile übernommen',
        () async {
      // Die Spalten kommen aus `PRAGMA table_info`, nicht aus der Datei.
      // Damit kann eine fremde Datei keinen Spaltennamen in die Abfrage
      // schreiben — und eine Datei aus einer neueren Fassung, die eine
      // Spalte mehr kennt, wird trotzdem gelesen.
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(
        data: file([
          {
            'table': 'settings',
            'row': {
              'key': 'language',
              'value': 'en',
              'spalte_aus_der_zukunft': 1,
            },
          },
        ]),
        passphrase: pass,
      );

      expect(ergebnis.rowsImported, 1);
      expect(ergebnis.rejected, 0);
      expect(ziel.setting('language'), 'en');
    });

    test('eine Zeile ohne Pflichtangabe wird gezählt, nicht eingefügt',
        () async {
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(
        data: file([
          {
            'table': 'anchors',
            'row': {'id': 'kaputt'},
          },
          {
            'table': 'settings',
            'row': {'key': 'language', 'value': 'de'},
          },
        ]),
        passphrase: pass,
      );

      expect(ergebnis.rejected, 1);
      // Die gute Zeile danach kommt trotzdem an — eine unlesbare Zeile
      // kippt nicht den ganzen Umzug.
      expect(ergebnis.rowsImported, 1);
      expect(await ziel.anchors(), isEmpty);
      expect(ziel.setting('language'), 'de');
    });

    test('eine Zeile, die zu keiner Spalte passt, wird gezählt', () async {
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(
        data: file([
          {
            'table': 'settings',
            'row': {'voellig': 'anders'},
          },
        ]),
        passphrase: pass,
      );
      expect(ergebnis.rejected, 1);
      expect(ergebnis.rowsImported, 0);
    });

    test('ein unbekannter Ereignistyp ist unlesbar, nicht stillschweigend '
        'übersprungen', () async {
      final gut = Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'kommt an'},
      );
      final ziel = target();
      final ergebnis = await vaultFor(ziel).import(
        data: file([
          {
            'id': 'x',
            'at': clock.nowUtc().toIso8601String(),
            'type': 'gibt_es_nicht',
            'source': 'user',
            'payload': const <String, Object?>{},
          },
          gut.toJson(),
        ]),
        passphrase: pass,
      );

      expect(ergebnis.rejected, 1);
      expect(ergebnis.imported, 1);
      expect((await ziel.query()).single.payload['text'], 'kommt an');
    });

    test('bricht der Wiederaufbau, ist am Ende nichts eingespielt', () async {
      // Der Wiederaufbau läuft nach der letzten Zeile und außerhalb der
      // Zeilen-Fehlerbehandlung. Wirft er, muss der ganze Import zurück —
      // sonst stünden die Ereignisse da, während die Projektion leer bleibt,
      // und der nächste Versuch meldete „bereits vorhanden".
      final ziel = target();
      await expectLater(
        vaultFor(ziel).import(
          data: file([
            {
              'id': 'e1',
              'at': clock.nowUtc().toIso8601String(),
              'type': EventType.taskCreated.name,
              'source': 'user',
              'payload': const {
                'task_id': 't1',
                'title': 'Kaputt',
                'decay_at': 'kein Datum',
              },
            },
          ]),
          passphrase: pass,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(await ziel.eventCount(), 0);
      expect(await ziel.tasks(), isEmpty);
    });
  });

  group('Eine Datei aus derselben Datenbank', () {
    test('der Rückweg ändert nichts', () async {
      await seed(5);
      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));
      store.setSetting('language', 'de');

      final blob = await vault.export(passphrase: pass);
      final ergebnis = await vault.import(data: blob, passphrase: pass);

      expect(ergebnis.imported, 0);
      expect(ergebnis.skipped, 5);
      expect(ergebnis.rowsImported, 0);
      expect(ergebnis.rowsSkipped, greaterThan(0));
      expect(await store.eventCount(), 5);
      expect((await store.anchors()).single.title, 'Zahnarzt');
      expect(store.setting('language'), 'de');
    });

    test('und er lässt die Aufgaben stehen', () async {
      // Der Wiederaufbau läuft nur bei `imported > 0`. Beim Rückweg in
      // dieselbe Datenbank wird also nichts neu gebaut — die Projektion
      // muss trotzdem unangetastet dastehen.
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.taskCreated,
        source: EventSource.user,
        payload: const {'task_id': 't1', 'title': 'Steuerunterlagen'},
      ));
      await store.rebuildProjections();

      final blob = await vault.export(passphrase: pass);
      await vault.import(data: blob, passphrase: pass);

      expect((await store.tasks()).single.title, 'Steuerunterlagen');
    });

    test('ein älterer Export bringt eine gelöschte Einnahme zurück',
        () async {
      // Der Import ergänzt nur; Grabsteine gibt es nicht. Wer eine Einnahme
      // löscht und danach eine ältere Datei einspielt, hat sie wieder.
      // Der Test hält das fest, weil es die einzige Löschung auf
      // Gesundheitsdaten betrifft und man es der Oberfläche nicht ansieht.
      await store.saveMedEntry(MedEntry(
        id: 'm1',
        label: 'Praeparat',
        takenAt: clock.nowLocal(),
      ));
      final blob = await vault.export(passphrase: pass);

      await store.deleteMedEntry('m1');
      expect(await store.medEntriesSince(DateTime(2026)), isEmpty);

      final ergebnis = await vault.import(data: blob, passphrase: pass);
      expect(ergebnis.rowsImported, 1);
      expect((await store.medEntriesSince(DateTime(2026))).single.id, 'm1');
    });
  });
}
