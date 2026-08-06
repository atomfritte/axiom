import 'dart:convert';
import 'dart:typed_data';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;
  late Vault vault;

  setUp(() {
    clock = FakeClock(DateTime(2026, 8, 3, 10));
    store = SqliteEventStore.inMemory(clock: clock);
    // Wenige Runden: Die Suite soll nicht an der absichtlichen
    // Langsamkeit haengen. Ein eigener Test prueft den Produktivwert.
    vault = Vault(store: store, clock: clock, kdfRounds: 200);
  });
  tearDown(() => store.close());

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

  const pass = 'ein-langes-kennwort';

  group('Klartextform bleibt lesbar', () {
    test('erste Zeile ist das Manifest, dann ein Event je Zeile', () async {
      await seed(3);
      final lines = (await vault.buildPlaintext()).trim().split('\n');

      expect(lines, hasLength(4));
      final manifest =
          VaultManifest.fromJson(jsonDecode(lines.first) as Map<String, Object?>);
      expect(manifest.eventCount, 3);

      // Ein Export, den man nur mit AXIOM lesen kann, waere keine
      // Datenhoheit — mit dem Schluessel muss er mit Bordmitteln lesbar sein.
      final first = jsonDecode(lines[1]) as Map<String, Object?>;
      expect(first['type'], 'capture');
      expect((first['payload']! as Map)['text'], 'Notiz 0');
    });

    test('respektiert das Zeitfenster', () async {
      await seed(5);
      final cutoff = DateTime(2026, 8, 3, 10, 20).toUtc();
      final text = await vault.buildPlaintext(from: cutoff);
      final manifest = VaultManifest.fromJson(
        jsonDecode(text.trim().split('\n').first) as Map<String, Object?>,
      );
      expect(manifest.eventCount, lessThan(5));
    });
  });

  group('Export und Import', () {
    test('vollstaendiger Umlauf erhaelt alle Ereignisse', () async {
      await seed(12);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      final result = await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: pass);

      expect(result.imported, 12);
      expect(result.skipped, 0);
      expect(await target.eventCount(), 12);

      final original = await store.query();
      final restored = await target.query();
      expect(restored.map((e) => e.id), original.map((e) => e.id));
      expect(restored.first.payload['text'], 'Notiz 0');
      target.close();
    });

    test('Datei traegt die Kennung', () async {
      await seed(1);
      final blob = await vault.export(passphrase: pass);
      expect(utf8.decode(blob.sublist(0, kVaultMagic.length)), kVaultMagic);
    });

    test('zweimaliger Export ergibt verschiedene Dateien', () async {
      await seed(3);
      final a = await vault.export(passphrase: pass);
      final b = await vault.export(passphrase: pass);
      // Salz und Nonce sind neu — gleiche Daten duerfen nicht gleich aussehen.
      expect(a, isNot(equals(b)));
    });
  });

  group('Import ist wiederholbar (append-only)', () {
    test('derselbe Export zweimal eingespielt verdoppelt nichts', () async {
      await seed(6);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      final targetVault = Vault(store: target, clock: clock, kdfRounds: 200);

      final first = await targetVault.import(data: blob, passphrase: pass);
      final second = await targetVault.import(data: blob, passphrase: pass);

      expect(first.imported, 6);
      expect(second.imported, 0);
      expect(second.skipped, 6);
      expect(await target.eventCount(), 6);
      target.close();
    });

    test('zwei Geraete konvergieren ohne Verlust', () async {
      // Geraet A
      await seed(4);
      final fromA = await vault.export(passphrase: pass);

      // Geraet B mit eigenen Ereignissen
      final b = SqliteEventStore.inMemory(clock: clock);
      final vaultB = Vault(store: b, clock: clock, kdfRounds: 200);
      for (var i = 0; i < 3; i++) {
        await b.append(Event(
          id: newUlid(clock.nowUtc()),
          at: clock.nowUtc(),
          type: EventType.checkin,
          source: EventSource.user,
          payload: {'energy': 3},
        ));
        clock.advance(const Duration(minutes: 5));
      }

      await vaultB.import(data: fromA, passphrase: pass);
      expect(await b.eventCount(), 7);

      // Rueckweg: A bekommt Bs Ereignisse, ohne die eigenen zu verlieren.
      final fromB = await vaultB.export(passphrase: pass);
      await vault.import(data: fromB, passphrase: pass);
      expect(await store.eventCount(), 7);

      b.close();
    });

    test('Probelauf schreibt nichts', () async {
      await seed(5);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      final result = await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: pass, dryRun: true);

      expect(result.imported, 5);
      expect(result.dryRun, isTrue);
      expect(await target.eventCount(), 0);
      target.close();
    });
  });

  group('Schutz', () {
    test('falsches Kennwort spielt nichts ein', () async {
      await seed(4);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      await expectLater(
        Vault(store: target, clock: clock, kdfRounds: 200)
            .import(data: blob, passphrase: 'anderes-kennwort'),
        throwsA(isA<VaultError>()),
      );
      expect(await target.eventCount(), 0);
      target.close();
    });

    test('veraenderte Datei wird erkannt', () async {
      await seed(4);
      final blob = await vault.export(passphrase: pass);
      final tampered = Uint8List.fromList(blob);
      // Ein einzelnes Bit im Chiffrat kippen.
      tampered[tampered.length - 40] ^= 0x01;

      final target = SqliteEventStore.inMemory(clock: clock);
      await expectLater(
        Vault(store: target, clock: clock, kdfRounds: 200)
            .import(data: tampered, passphrase: pass),
        throwsA(isA<VaultError>()),
      );
      // Wichtiger als die Meldung: Es darf nichts halb eingespielt sein.
      expect(await target.eventCount(), 0);
      target.close();
    });

    test('fremde Datei wird abgelehnt', () async {
      final fremd = Uint8List.fromList(utf8.encode('x' * 200));
      await expectLater(
        vault.import(data: fremd, passphrase: pass),
        throwsA(isA<VaultError>()),
      );
    });

    test('zu kurze Datei wird abgelehnt', () async {
      await expectLater(
        vault.import(data: Uint8List(10), passphrase: pass),
        throwsA(isA<VaultError>()),
      );
    });

    test('kurzes Kennwort wird abgelehnt', () async {
      await seed(1);
      await expectLater(
        vault.export(passphrase: 'kurz'),
        throwsA(isA<VaultError>()),
      );
    });

    test('der Klartext steht nicht in der Exportdatei', () async {
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'Sehr vertraulicher Inhalt'},
      ));
      final blob = await vault.export(passphrase: pass);
      // Latin-1 statt UTF-8: Zufallsbytes sind kein gueltiges UTF-8.
      final raw = latin1.decode(blob, allowInvalid: true);
      expect(raw, isNot(contains('Sehr vertraulicher Inhalt')));
      expect(raw, isNot(contains('capture')));
    });
  });

  group('Produktivkonfiguration', () {
    test('die Ableitung ist absichtlich teuer', () {
      // Der einzige Schutz gegen Durchprobieren eines menschlichen
      // Kennworts sind die Ableitungskosten.
      expect(kKdfRounds, greaterThanOrEqualTo(100000));
    });

    test('ohne Angabe gilt der Produktivwert', () {
      // Die Testkonfiguration darf nicht versehentlich zur Voreinstellung
      // werden — ein Export mit 200 Runden waere praktisch ungeschuetzt.
      expect(Vault(store: store, clock: clock).kdfRounds, kKdfRounds);
    });
  });

  group('Ein Umzug nimmt alles mit', () {
    // Der Export war jahrelang die einzige dokumentierte Sicherung — und
    // enthielt ausschliesslich `events`. Anker, Reizkanaele, Trigger,
    // Nachbetrachtungen, Wirkfenster, Einstellungen und bearbeitete Regeln
    // waren nach einem Umzug weg, waehrend der Bildschirm zusagt: „Beide
    // Seiten importieren die Datei der anderen, und beide haben danach
    // alles."

    Future<void> fillEverything(SqliteEventStore s) async {
      await s.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 10, 14),
        travel: const Duration(minutes: 25),
        location: 'Praxis Mitte',
      ));
      await s.upsertChannel(
        const SensationChannel(
          id: 'sport',
          label: 'Sport, hart',
          intensity: 5,
          typical: Duration(minutes: 45),
        ),
        order: 3,
      );
      await s.upsertTrigger(const InterceptTrigger(
        id: 'bestellen',
        label: 'Etwas bestellen',
        cooldown: Duration(minutes: 30),
        checklist: ['Brauche ich das morgen noch?', 'Habe ich etwas davon?'],
        authorized: true,
      ));
      await s.saveRun(InterceptRun(
        id: 'run1',
        triggerId: 'bestellen',
        triggerLabel: 'Etwas bestellen',
        startedAt: DateTime(2026, 8, 2, 22),
        releasesAt: DateTime(2026, 8, 2, 22, 30),
        answers: const [true, false],
        outcome: InterceptOutcome.aborted,
      ));
      await s.startFocus(FocusSession(
        id: 'f1',
        startedAt: DateTime(2026, 8, 3, 9),
        anchorTitle: 'Steuer',
      ));
      s.setLoadState(LoadLevel.l2, DateTime(2026, 8, 1, 8));
      await s.savePostMortem(PostMortem(
        incidentId: 'i1',
        at: DateTime(2026, 8, 1, 20),
        rootCause: 'Zu wenig Schlaf',
        countermeasure: 'Vorher Wasser trinken',
        intensityInHindsight: 2,
      ));
      await s.saveMedEntry(MedEntry(
        id: 'm1',
        label: 'Präparat',
        dose: '1 Stück',
        takenAt: DateTime(2026, 8, 3, 8),
        onset: const Duration(minutes: 45),
        duration: const Duration(hours: 4),
      ));
      s.setSetting('language', 'en');
      // Overlay per SQL: Die Fassung der Regel gehoert nicht in diesen Test.
      s.rawDatabase.execute(
        'INSERT INTO rule_overrides (id, yaml, updated_at, shadow_until, '
        'overrides) VALUES (?,?,?,?,?)',
        ['R-900', 'id: R-900\ntitle: Eigene Regel', 1, 2, 1],
      );
    }

    test('Anker, Kanal, Trigger, Wirkfenster und Einstellung kommen an',
        () async {
      await seed(2);
      await fillEverything(store);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      final result = await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: pass);

      expect(result.rowsImported, greaterThan(0));
      expect(result.rejected, 0);

      expect((await target.anchors()).single.title, 'Zahnarzt');
      expect((await target.anchors()).single.travel,
          const Duration(minutes: 25));
      expect((await target.channels()).single.label, 'Sport, hart');
      final trigger = (await target.triggers()).single;
      expect(trigger.checklist, hasLength(2));
      expect(trigger.authorized, isTrue);
      expect((await target.runsSince(DateTime(2026))).single.outcome,
          InterceptOutcome.aborted);
      expect((await target.activeFocus())!.anchorTitle, 'Steuer');
      expect(target.loadState()!.level, LoadLevel.l2);
      expect((await target.postMortems()).single.rootCause, 'Zu wenig Schlaf');
      expect((await target.medEntriesSince(DateTime(2026))).single.label,
          'Präparat');
      expect(target.setting('language'), 'en');
      expect(
        target.rawDatabase
            .select('SELECT yaml FROM rule_overrides WHERE id = ?', ['R-900'])
            .single['yaml'],
        contains('Eigene Regel'),
      );
      target.close();
    });

    test('ein zweiter Import ergänzt nichts doppelt', () async {
      await fillEverything(store);
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      final v = Vault(store: target, clock: clock, kdfRounds: 200);
      final first = await v.import(data: blob, passphrase: pass);
      final second = await v.import(data: blob, passphrase: pass);

      expect(second.rowsImported, 0);
      expect(second.rowsSkipped, first.rowsImported);
      expect((await target.anchors()), hasLength(1));
      target.close();
    });

    test('was am Zielgerät steht, bleibt stehen', () async {
      // Ein Import darf nichts überschreiben. Sonst entscheidet die
      // Reihenfolge der Dateien darüber, welche Fassung gilt — und der
      // Nutzer hätte keine Möglichkeit, das zu bemerken.
      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Fassung vom Telefon',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));
      final blob = await vault.export(passphrase: pass);

      final target = SqliteEventStore.inMemory(clock: clock);
      await target.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Fassung vom Rechner',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));
      final result = await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: pass);

      expect((await target.anchors()).single.title, 'Fassung vom Rechner');
      expect(result.rowsSkipped, greaterThan(0));
      target.close();
    });

    test('der private Schlüssel des Expertenmodus bleibt am Gerät', () async {
      // Die Datei wandert über USB, Ordner und Fremdrechner. Ein privater
      // Schlüssel darin wäre eine zweite Kopie einer Geräteidentität — und
      // auf dem Zielgerät ein Zertifikat, das für eine fremde Adresse gilt.
      store.setSetting('expert_key_pem', '-----BEGIN PRIVATE KEY-----');
      store.setSetting('language', 'de');
      final text = await vault.buildPlaintext();
      expect(text, isNot(contains('BEGIN PRIVATE KEY')));
      expect(text, contains('language'));

      final blob = await vault.export(passphrase: pass);
      final target = SqliteEventStore.inMemory(clock: clock);
      await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: pass);
      expect(target.setting('expert_key_pem'), isNull);
      expect(target.setting('language'), 'de');
      target.close();
    });

    test('jede Tabelle ist entweder im Export oder ausdrücklich ausgenommen',
        () {
      // Der Wächter gegen genau den Fehler, der hier passiert ist: Neun
      // Tabellen sind über Jahre aus dem einzigen Sicherungsweg
      // herausgewachsen, ohne dass es jemandem auffallen konnte.
      final tables = store.rawDatabase
          .select("SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'")
          .map((r) => r['name'] as String)
          .toSet();
      final entschieden = {...kVaultTables, ...kVaultExcludedTables.keys};
      expect(tables.difference(entschieden), isEmpty,
          reason: 'Neue Tabelle: entweder nach kVaultTables (wandert mit) '
              'oder nach kVaultExcludedTables (bleibt, mit Begründung)');
      expect(entschieden.difference(tables), isEmpty,
          reason: 'Eine Tabelle in den Listen, die es nicht mehr gibt');
    });

    test('ein Ausschnitt bringt keine Tabellen mit', () async {
      // `from`/`to` schneiden den Ereignisstrom. Tabellenzeilen tragen
      // keinen Zeitbezug, den man mitschneiden könnte — ein halber
      // Reizkanal wäre schlimmer als keiner.
      await seed(3);
      await fillEverything(store);
      final text = await vault.buildPlaintext(from: DateTime(2026).toUtc());
      expect(text, isNot(contains('"table"')));
    });
  });

  group('Ältere Dateien', () {
    test('eine Datei im alten Format lässt sich weiterhin einspielen',
        () async {
      // Format 1: Manifest ohne `format`, danach nur Ereignisse.
      final event = Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'Aus einer älteren Fassung'},
      );
      final plaintext = '${jsonEncode({
            'schema': '9',
            'created_at': clock.nowUtc().toIso8601String(),
            'events': 1,
          })}\n${jsonEncode(event.toJson())}\n';

      final target = SqliteEventStore.inMemory(clock: clock);
      final v = Vault(store: target, clock: clock, kdfRounds: 200);
      final result = await v.import(
        data: v.seal(plaintext, pass),
        passphrase: pass,
      );

      expect(result.imported, 1);
      expect(result.rejected, 0);
      expect(result.manifest.format, 1);
      expect((await target.query()).single.payload['text'],
          'Aus einer älteren Fassung');
      target.close();
    });

    test('ein unbekannter Abschnitt wird gezählt, nicht verschluckt', () async {
      final plaintext = '${jsonEncode({
            'schema': '$kSchemaVersion',
            'format': 99,
            'created_at': clock.nowUtc().toIso8601String(),
            'events': 0,
          })}\n${jsonEncode({
            'table': 'was_auch_immer',
            'row': {'id': 'x'},
          })}\n';

      final target = SqliteEventStore.inMemory(clock: clock);
      final v = Vault(store: target, clock: clock, kdfRounds: 200);
      final result = await v.import(
        data: v.seal(plaintext, pass),
        passphrase: pass,
      );
      expect(result.rejected, 1);
      expect(result.rowsImported, 0);
      target.close();
    });
  });

  group('Zusammenfassung', () {
    test('nennt uebernommen, vorhanden und unlesbar', () async {
      await seed(3);
      final blob = await vault.export(passphrase: pass);
      final target = SqliteEventStore.inMemory(clock: clock);
      final v = Vault(store: target, clock: clock, kdfRounds: 200);

      await v.import(data: blob, passphrase: pass);
      final again = await v.import(data: blob, passphrase: pass);

      expect(again.summary, contains('bereits vorhanden'));
      target.close();
    });
  });
}
