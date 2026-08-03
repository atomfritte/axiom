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
