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
import 'package:flutter_test/flutter_test.dart';

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
  });
}
