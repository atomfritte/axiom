/// Das Zertifikat des Expertenmodus — gelesen, nicht geglaubt.
///
/// Der bisherige Wächter suchte im Quelltext nach `kAxiomHostname`. Damit
/// blieb er grün, während jede IP-Adresse als `dNSName` im Zertifikat stand:
/// `basic_utils` kennt keinen `iPAddress`-Typ und kodiert alles mit Tag
/// `0x82`. Ein Browser gleicht bei einer IP in der Adresszeile aber
/// ausschließlich gegen `iPAddress`-Einträge ab und ignoriert den CN — der
/// Rückfallweg über die IP und der Weg über `adb forward` scheiterten
/// dauerhaft, auch nach angenommener Ausnahme.
///
/// Deshalb wird hier geparst und einmal wirklich verbunden. Ein Test, der
/// den Quelltext liest, hätte das nicht gefunden — er hat es nicht.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:axiom_app/server/expert_certificate.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// ── Ein unabhängiger DER-Leser ──────────────────────────────────────────
//
// Bewusst nicht der aus dem Quellcode: Ein Test, der mit demselben Leser
// prüft, mit dem geschrieben wurde, bestätigt nur sich selbst.

final class Tlv {
  final int tag;
  final int contentStart;
  final int length;
  const Tlv(this.tag, this.contentStart, this.length);
  int get end => contentStart + length;
}

Tlv readTlv(Uint8List der, int start) {
  final tag = der[start];
  var offset = start + 1;
  var length = der[offset++];
  if (length & 0x80 != 0) {
    final count = length & 0x7F;
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | der[offset++];
    }
  }
  return Tlv(tag, offset, length);
}

Iterable<Tlv> childrenOf(Uint8List der, Tlv parent) sync* {
  var offset = parent.contentStart;
  while (offset < parent.end) {
    final child = readTlv(der, offset);
    yield child;
    offset = child.end;
  }
}

Uint8List derOf(String pem) => base64.decode(pem
    .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
    .replaceAll(RegExp(r'\s'), ''));

/// Die Subject Alternative Names in derselben Schreibweise, die
/// `openssl x509 -text` zeigt — `IP:…` für `iPAddress`, `DNS:…` für
/// `dNSName`. Ein unbekanntes Tag bleibt sichtbar statt zu verschwinden.
List<String> subjectAltNames(String pem) {
  final der = derOf(pem);
  final certificate = readTlv(der, 0);
  final tbs = readTlv(der, certificate.contentStart);
  // Der Erweiterungsblock von tbsCertificate ist mit [3] markiert.
  final block = childrenOf(der, tbs).firstWhere((child) => child.tag == 0xA3);
  final list = readTlv(der, block.contentStart);

  for (final extension in childrenOf(der, list)) {
    final oid = readTlv(der, extension.contentStart);
    // 2.5.29.17 — subjectAltName.
    if (der.sublist(oid.contentStart, oid.end).join('.') != '85.29.17') continue;
    // Das letzte Kind ist der OCTET STRING; davor kann ein „critical"
    // stehen.
    final octets = childrenOf(der, extension).last;
    final names = readTlv(der, octets.contentStart);
    return [
      for (final name in childrenOf(der, names))
        switch (name.tag) {
          0x87 => 'IP:${der.sublist(name.contentStart, name.end).join('.')}',
          0x82 =>
            'DNS:${utf8.decode(der.sublist(name.contentStart, name.end))}',
          _ => 'TAG-0x${name.tag.toRadixString(16)}',
        },
    ];
  }
  return const [];
}

/// Stellt den Server mit genau diesem Zertifikat auf und verbindet sich als
/// Browser, der ihm vertraut. Gibt `'ok'` zurück oder den Fehler.
///
/// Das ist der Punkt: Dart, Chrome und Android prüfen alle mit BoringSSL.
/// Was hier durchgeht, geht auch dort durch — und was hier scheitert, ist
/// im Browser die Namenswarnung, die man wegklickt. Der Aufbau prüft die
/// Kette mit und damit auch, dass nach dem Einsetzen des SAN-Blocks neu
/// signiert wurde.
Future<String> handshake(
  String certificatePem,
  String privateKeyPem,
  String host,
) async {
  final serverContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
  final clientContext = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(certificatePem));

  final listener = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4, 0, serverContext);
  listener.listen((socket) => socket.destroy());
  try {
    final socket =
        await SecureSocket.connect(host, listener.port, context: clientContext);
    socket.destroy();
    return 'ok';
  } on Object catch (error) {
    return '$error';
  } finally {
    await listener.close();
  }
}

/// Wie [handshake], aber mit einem Namen, den kein Namensdienst kennt.
///
/// `SecureSocket.connect` würde `axiom.local` erst auflösen wollen und an
/// der Namensauflösung scheitern — geprüft wäre dann das Netz des Rechners
/// und nicht das Zertifikat. Hier wird zur Schleife verbunden und die
/// Prüfung anschließend ausdrücklich gegen [host] geführt, so wie ein
/// Browser es täte, der `https://axiom.local:8787` in der Adresszeile hat.
Future<String> handshakeAgainstName(
  String certificatePem,
  String privateKeyPem,
  String host,
) async {
  final serverContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
  final clientContext = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(certificatePem));

  final listener = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4, 0, serverContext);
  listener.listen((socket) => socket.destroy());
  try {
    final raw =
        await Socket.connect(InternetAddress.loopbackIPv4, listener.port);
    final secure =
        await SecureSocket.secure(raw, host: host, context: clientContext);
    secure.destroy();
    return 'ok';
  } on Object catch (error) {
    return '$error';
  } finally {
    await listener.close();
  }
}

void main() {
  late String certificatePem;
  late String privateKeyPem;

  setUpAll(() {
    // Ein RSA-2048-Paar dauert eine gute Sekunde. Einmal für alle Tests.
    final (certificate, key) = ExpertCertificates.debugMakePair('192.168.1.42');
    certificatePem = certificate;
    privateKeyPem = key;
  });

  group('Was im Zertifikat steht', () {
    test('IP-Adressen als iPAddress, Namen als dNSName', () {
      // Steht in der Adresszeile eine IP, sieht der Browser den CN nicht an
      // und vergleicht nur mit den iPAddress-Einträgen. Stehen dort nur
      // dNSName-Einträge, scheitert der Aufruf dauerhaft.
      expect(subjectAltNames(certificatePem), [
        'IP:192.168.1.42',
        'DNS:axiom.local',
        'DNS:localhost',
        'IP:127.0.0.1',
      ]);
    });

    test('keine Adresse steht doppelt drin', () {
      // Wird keine LAN-Adresse gefunden, stellt der Server auf die
      // Rückfalladresse aus — dann wäre 127.0.0.1 sonst zweimal dabei.
      final (certificate, _) = ExpertCertificates.debugMakePair('127.0.0.1');
      expect(subjectAltNames(certificate), [
        'IP:127.0.0.1',
        'DNS:axiom.local',
        'DNS:localhost',
      ]);
    });
  });

  group('Ob es benutzbar ist', () {
    test('der Aufruf über die IP kommt zustande', () async {
      // Der dokumentierte Weg über `adb forward` ist genau dieser:
      // https://127.0.0.1:8787. Und er ist der Rückfallweg, wenn Multicast
      // gesperrt ist — also der Weg für den Fall, in dem der Name fehlt.
      expect(await handshake(certificatePem, privateKeyPem, '127.0.0.1'), 'ok');
    });

    test('der Aufruf über den Namen kommt zustande', () async {
      // Der Namensweg darf darüber nicht verlorengehen.
      expect(await handshake(certificatePem, privateKeyPem, 'localhost'), 'ok');
    });

    test('der Aufruf über axiom.local kommt zustande', () async {
      // Der eigentliche Weg. Er stand bisher in keinem Test: `axiom.local`
      // löst auf diesem Rechner nicht auf, und `SecureSocket.connect` wäre
      // schon an der Namensauflösung gescheitert. Damit war der einzige Name,
      // für den dieses Zertifikat überhaupt gebaut wird, ungeprüft.
      expect(
        await handshakeAgainstName(certificatePem, privateKeyPem,
            'axiom.local'),
        'ok',
      );
    });

    test('ein fremder Name wird abgelehnt', () async {
      // Die Gegenprobe. Ohne sie wäre nicht zu unterscheiden, ob die
      // Namensprüfung besteht oder ob sie gar nicht stattfindet — und ein
      // Zertifikat, das auf jeden Namen passt, wäre kein Ausweis mehr.
      final result = await handshakeAgainstName(
          certificatePem, privateKeyPem, 'fremd.local');
      expect(result, isNot('ok'));
      expect(result, contains('HandshakeException'));
    });
  });

  group('Der Fingerabdruck', () {
    late ExpertCertificate certificate;

    setUp(() => certificate = ExpertCertificate(
          certificatePem: certificatePem,
          privateKeyPem: privateKeyPem,
          issuedFor: '192.168.1.42',
        ));

    test('ist der Wert, den der Browser unter „Zertifikat anzeigen" nennt',
        () {
      // Der Fingerabdruck ist die ganze Sicherheitsaussage dieses Modus: Er
      // steht in der App, der Browser zeigt denselben Wert, und wer beide
      // vergleicht, weiß, dass niemand dazwischen ist. Berechnet werden muss
      // er über das **DER**. Über den PEM-Text gerechnet käme ebenfalls ein
      // plausibler 64-Zeichen-Wert heraus — er stimmte nur nie mit dem des
      // Browsers überein, und aus dem Vergleich würde ein Ritual.
      final der = derOf(certificatePem);
      final expected = sha256
          .convert(der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();

      expect(certificate.fingerprint, expected);
      expect(certificate.fingerprint, matches(RegExp(r'^[0-9A-F]{64}$')));
      expect(
        certificate.fingerprint,
        isNot(sha256.convert(utf8.encode(certificatePem)).toString().toUpperCase()),
        reason: 'über den PEM-Text gerechnet',
      );
    });

    test('lässt sich vorlesen, ohne sich zu verzählen', () {
      // Vierergruppen, vier je Zeile. Der Wert wird von Hand verglichen —
      // eine ununterbrochene Kette aus 64 Zeichen wird dabei zuverlässig
      // falsch gelesen.
      final lines = certificate.readableFingerprint.split('\n');
      expect(lines, hasLength(4));
      for (final line in lines) {
        final groups = line.split(' ');
        expect(groups, hasLength(4));
        for (final group in groups) {
          expect(group, matches(RegExp(r'^[0-9A-F]{4}$')));
        }
      }
      expect(
        certificate.readableFingerprint.replaceAll(RegExp(r'\s'), ''),
        certificate.fingerprint,
      );
    });
  });

  group('Was einen Neustart überlebt', () {
    // Ein neues Zertifikat bei jedem Start hieße eine neue Warnung bei jedem
    // Start — und genau daraus entsteht die Gewöhnung, gegen die der
    // Fingerabdruck gebaut ist.

    late TestHarness harness;

    setUp(() {
      harness = TestHarness.create();
      addTearDown(harness.dispose);
    });

    test('dieselbe Adresse bekommt dasselbe Zertifikat wieder', () async {
      final first =
          await ExpertCertificates.forAddress(harness.runtime, '10.0.0.5');
      final again =
          await ExpertCertificates.forAddress(harness.runtime, '10.0.0.5');

      expect(again.certificatePem, first.certificatePem);
      expect(again.privateKeyPem, first.privateKeyPem);
      expect(again.fingerprint, first.fingerprint);
      expect(again.issuedFor, '10.0.0.5');
    });

    test('eine ältere Form wird ersetzt, nicht geerbt', () async {
      // Der Merker trägt die Form mit, nicht nur die Adresse. Sonst passte
      // ein Zertifikat aus der Zeit, als IP-Adressen noch als `dNSName`
      // drinstanden, weiterhin zur Adresse — und der Aufruf über die IP
      // scheiterte dauerhaft, während von außen mDNS schuld schiene.
      final first =
          await ExpertCertificates.forAddress(harness.runtime, '10.0.0.5');
      final marker = harness.runtime.store.setting('expert_cert_for');
      expect(marker, endsWith(':10.0.0.5'));

      final shape = int.parse(marker!.split(':').first);
      harness.runtime.store
          .setSetting('expert_cert_for', '${shape - 1}:10.0.0.5');

      final fresh =
          await ExpertCertificates.forAddress(harness.runtime, '10.0.0.5');
      expect(fresh.certificatePem, isNot(first.certificatePem));
      expect(harness.runtime.store.setting('expert_cert_for'), marker);
    });

    test('wegwerfen lässt nichts liegen, was wiederverwendet würde', () async {
      // `forget` gibt es für den Fall, dass jemand anders den Fingerabdruck
      // gesehen haben könnte. Bliebe der Merker stehen, käme beim nächsten
      // Start dasselbe Zertifikat zurück — und das Wegwerfen wäre eine Geste.
      await ExpertCertificates.forAddress(harness.runtime, '10.0.0.5');
      ExpertCertificates.forget(harness.runtime);

      for (final key in [
        'expert_cert_pem',
        'expert_key_pem',
        'expert_cert_for',
      ]) {
        expect(harness.runtime.store.setting(key), '', reason: key);
      }
    });
  });
}
