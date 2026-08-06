/// Der mDNS-Responder — geprüft an den Bytes.
///
/// Paketbau ist die Art Code, bei der Danebenliegen nicht auffällt: Ein
/// falsches Byte, und das Gerät antwortet einfach nie, während alles
/// funktionierend aussieht. Deshalb wird hier gegen RFC 6762 gemessen und
/// nicht gegen die eigene Erwartung.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:axiom_app/server/mdns_responder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ein Socket, der sich verhält wie einer in einem Netz ohne Multicast.
///
/// Den Fall gibt es auf dem Rechner nicht herzustellen: nur Mobilfunk, WLAN
/// aus, `adb forward`-Betrieb. Genau in diesem Fall blieben Sperre und
/// Socket hängen, und genau deshalb ist er hier nachgebaut.
final class FakeSocket extends Stream<RawSocketEvent>
    implements RawDatagramSocket {
  FakeSocket({this.refusesGroup = false});

  final bool refusesGroup;
  bool closed = false;
  final List<Uint8List> sent = [];

  /// Ein Feld, kein noSuchMethod-Weiterleiter: Der würde beim Setzen
  /// werfen, und dann prüfte der Test einen anderen Fehler als gemeint.
  @override
  int multicastHops = 0;

  @override
  void joinMulticast(InternetAddress group, [NetworkInterface? interface]) {
    if (refusesGroup) {
      throw const SocketException('kein Multicast auf dieser Schnittstelle');
    }
  }

  @override
  int send(List<int> buffer, InternetAddress address, int port) {
    sent.add(Uint8List.fromList(buffer));
    return buffer.length;
  }

  @override
  void close() => closed = true;

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      const Stream<RawSocketEvent>.empty().listen(onData);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Baut eine DNS-Frage, so wie ein Browser sie stellt.
Uint8List question(String name, {bool asResponse = false}) {
  final out = BytesBuilder();
  out.add([0x12, 0x34]);
  out.add(asResponse ? [0x84, 0] : [0, 0]);
  out.add([0, 1, 0, 0, 0, 0, 0, 0]);
  for (final label in name.split('.')) {
    out.addByte(label.length);
    out.add(label.codeUnits);
  }
  out.addByte(0);
  out.add([0, 1, 0, 1]); // Typ A, Klasse IN
  return out.toBytes();
}

void main() {
  group('Welche Fragen beantwortet werden', () {
    test('die nach axiom.local', () {
      expect(MdnsResponder.debugAsksForAxiom(question('axiom.local')), isTrue);
    });

    test('nicht die nach fremden Namen', () {
      // Ein Responder, der auf alles antwortet, kapert das Netz.
      for (final name in ['drucker.local', 'axiom.example.com', 'local']) {
        expect(MdnsResponder.debugAsksForAxiom(question(name)), isFalse,
            reason: name);
      }
    });

    test('Groß- und Kleinschreibung spielt keine Rolle', () {
      // DNS-Namen sind unabhaengig davon gleich. Manche Systeme fragen
      // in der Schreibweise, die der Nutzer getippt hat.
      expect(MdnsResponder.debugAsksForAxiom(question('AXIOM.local')), isTrue);
    });

    test('nicht die Antworten anderer', () {
      // Sonst antworten zwei Responder einander bis zum Ende der Zeit.
      expect(
        MdnsResponder.debugAsksForAxiom(
            question('axiom.local', asResponse: true)),
        isFalse,
      );
    });

    test('kein Absturz an abgeschnittenen Paketen', () {
      // Was auf 5353 ankommt, ist beliebiger Netzverkehr. Ein Absturz
      // hier nähme den Expertenmodus mit.
      final full = question('axiom.local');
      for (var i = 0; i <= full.length; i++) {
        expect(
          () => MdnsResponder.debugAsksForAxiom(
              Uint8List.sublistView(full, 0, i)),
          returnsNormally,
          reason: 'abgeschnitten nach $i Bytes',
        );
      }
    });
  });

  group('Was geantwortet wird', () {
    test('ein A-Eintrag mit der eigenen Adresse', () {
      final packet = MdnsResponder.debugAnswer('192.168.1.42', 120);

      // Header: Antwort, autoritativ, genau ein Answer Record.
      expect(packet[2] & 0x80, 0x80, reason: 'Antwort-Bit');
      expect(packet[2] & 0x04, 0x04, reason: 'autoritativ');
      expect((packet[6] << 8) | packet[7], 1, reason: 'ein Eintrag');

      // Die vier Adressbytes stehen am Ende, in dieser Reihenfolge.
      expect(packet.sublist(packet.length - 4), [192, 168, 1, 42]);
    });

    test('mit Cache-Flush, damit eine alte Adresse verdrängt wird', () {
      // Ohne das Bit steht nach einem Netzwerkwechsel die alte IP daneben,
      // und der Browser probiert beide.
      final packet = MdnsResponder.debugAnswer('10.0.0.5', 120);
      final classBytes = packet.sublist(packet.length - 12, packet.length - 10);
      expect(classBytes[0] & 0x80, 0x80);
    });

    test('der Abschied trägt TTL 0', () {
      final goodbye = MdnsResponder.debugAnswer('10.0.0.5', 0);
      final ttl = goodbye.sublist(goodbye.length - 10, goodbye.length - 6);
      expect(ttl, [0, 0, 0, 0]);
    });

    test('der Name ist axiom.local, in DNS-Schreibweise', () {
      final packet = MdnsResponder.debugAnswer('10.0.0.5', 120);
      // 5 axiom 5 local 0
      expect(packet.sublist(12, 25),
          [5, ...'axiom'.codeUnits, 5, ...'local'.codeUnits, 0]);
    });
  });

  group('Was ein fehlgeschlagener Start hinterlässt', () {
    // Die Multicast-Sperre ist auf der Systemseite nicht referenzgezählt
    // (`setReferenceCounted(false)`). Wird sie einmal nicht freigegeben,
    // bleibt sie bis zum Prozessende stehen und kostet die ganze Zeit
    // Strom — genau der Verbrauch, den der Kommentar an den Expertenmodus
    // binden will. Und ein Socket auf Port 5353 pro Startversuch dazu.

    test('nichts, wenn schon das Binden scheitert', () async {
      final responder = MdnsResponder(
        bind: () async => throw const SocketException('Port belegt'),
      );

      expect(await responder.start('10.0.0.5'), isFalse);
      expect(responder.holdsMulticastLock, isFalse,
          reason: 'die Sperre bliebe sonst bis zum Prozessende gehalten');
      expect(responder.isRunning, isFalse);
    });

    test('nichts, wenn der Beitritt zur Gruppe scheitert', () async {
      // Der teurere Fall: Das Binden hat geklappt, der Socket existiert
      // bereits, und erst `joinMulticast` wirft.
      final socket = FakeSocket(refusesGroup: true);
      final responder = MdnsResponder(bind: () async => socket);

      expect(await responder.start('10.0.0.5'), isFalse);
      expect(socket.closed, isTrue,
          reason: 'der Socket hielte sonst Port 5353 bis zum Prozessende');
      expect(responder.holdsMulticastLock, isFalse);
      expect(responder.isRunning, isFalse);
    });

    test('ein zweiter Versuch beginnt wieder bei null', () async {
      // Ohne Freigabe wäre der zweite Startversuch der, der die Sperre ein
      // zweites Mal greift — sichtbar wird das nie.
      final responder = MdnsResponder(
        bind: () async => throw const SocketException('Port belegt'),
      );
      await responder.start('10.0.0.5');
      await responder.start('10.0.0.5');
      expect(responder.holdsMulticastLock, isFalse);
    });
  });

  group('Die Sperre hängt am Lauf', () {
    test('gehalten, solange geantwortet wird — losgelassen beim Beenden',
        () async {
      final socket = FakeSocket();
      final responder = MdnsResponder(bind: () async => socket);

      expect(await responder.start('10.0.0.5'), isTrue);
      expect(responder.holdsMulticastLock, isTrue);
      // Die unaufgeforderte Ankündigung ist der Grund für den Start.
      expect(socket.sent, hasLength(1));

      await responder.stop();
      expect(responder.holdsMulticastLock, isFalse);
      expect(socket.closed, isTrue);
      // Zuletzt der Abschied mit TTL 0.
      final goodbye = socket.sent.last;
      expect(goodbye.sublist(goodbye.length - 10, goodbye.length - 6),
          [0, 0, 0, 0]);
    });
  });
}
