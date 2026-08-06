/// Das Zertifikat für den Expertenmodus.
///
/// **Warum selbst signiert und nicht gar nichts.** Ohne TLS liegen PIN,
/// Sitzungscookie und sämtliche Gesundheitsdaten im Klartext im Netz —
/// passives Mitlesen ist trivial und hinterlässt keine Spur. Mit einem selbst
/// signierten Zertifikat muss ein Angreifer die Verbindung aktiv übernehmen,
/// und das ist ein anderer Aufwand. Der Einwand „man klickt die Warnung
/// sowieso weg" stimmt nur, solange die Warnung nichts Überprüfbares zeigt.
///
/// **Deshalb ist der Fingerabdruck der eigentliche Punkt.** Er steht in der
/// App. Der Browser zeigt beim ersten Zugriff denselben Wert. Stimmen beide
/// überein, weiß man, dass man mit dem eigenen Telefon spricht und nicht mit
/// jemandem dazwischen — das ist echte Authentifizierung, kein Wegklicken.
///
/// **Deshalb bleibt es auch dasselbe Zertifikat.** Schlüssel und Zertifikat
/// liegen in der Einstellungstabelle und überleben Neustarts. Ein neues
/// Zertifikat bei jedem Start würde bei jedem Start eine neue Warnung
/// erzeugen — und genau das erzeugt die Gewöhnung, die gefährlich ist.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import '../state/runtime.dart';
import 'mdns_responder.dart' show kAxiomHostname;

final class ExpertCertificate {
  final String certificatePem;
  final String privateKeyPem;

  /// Die Adresse, für die es ausgestellt wurde. Ändert sie sich, passt das
  /// Zertifikat nicht mehr und wird neu erzeugt.
  final String issuedFor;

  const ExpertCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.issuedFor,
  });

  /// SHA-256 über das DER-Zertifikat — derselbe Wert, den der Browser unter
  /// „Zertifikat anzeigen" nennt.
  String get fingerprint {
    final der = base64.decode(certificatePem
        .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
        .replaceAll(RegExp(r'\s'), ''));
    final digest = sha256.convert(der).bytes;
    return [
      for (final byte in digest) byte.toRadixString(16).padLeft(2, '0'),
    ].join().toUpperCase();
  }

  /// In Vierergruppen, damit man ihn vorlesen und vergleichen kann, ohne
  /// sich zu verzählen.
  String get readableFingerprint {
    final buffer = StringBuffer();
    final hex = fingerprint;
    for (var i = 0; i < hex.length; i += 4) {
      if (i > 0) buffer.write(i % 16 == 0 ? '\n' : ' ');
      buffer.write(hex.substring(i, i + 4));
    }
    return buffer.toString();
  }

  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
}

abstract final class ExpertCertificates {
  /// Zaehlt hoch, wenn sich der Inhalt des Zertifikats aendert.
  ///
  /// Ein gespeichertes Zertifikat wird an der Adresse wiedererkannt. Aendert
  /// sich aber, *was* drinsteht — etwa weil `axiom.local` als Subject
  /// Alternative Name dazukommt —, passt das alte trotzdem zur Adresse und
  /// wuerde weiterverwendet. Der Browser lehnte den neuen Weg dann ab, und
  /// von aussen sahe es aus, als ginge mDNS nicht.
  ///
  /// 3: IP-Adressen stehen jetzt als `iPAddress` statt als `dNSName` drin.
  /// Ein Zertifikat aus Form 2 traegt die alte Kodierung und funktioniert
  /// ueber die IP dauerhaft nicht — es muss ersetzt werden, nicht geerbt.
  static const _shape = 3;

  static const _certKey = 'expert_cert_pem';
  static const _keyKey = 'expert_key_pem';
  static const _forKey = 'expert_cert_for';

  /// Gültig zehn Jahre. Ein ablaufendes Zertifikat für ein Gerät, das man
  /// selbst besitzt, erzeugt nur irgendwann eine Warnung ohne Aussage.
  static const int _days = 3650;

  /// Holt das gespeicherte Zertifikat oder erzeugt eines.
  ///
  /// [address] ist die IP, unter der der Server erreichbar sein wird. Sie
  /// wandert als Subject Alternative Name hinein — ohne SAN lehnen aktuelle
  /// Browser ein Zertifikat rundheraus ab, statt eine Ausnahme anzubieten.
  static Future<ExpertCertificate> forAddress(
    AxiomRuntime runtime,
    String address,
  ) async {
    final stored = runtime.store.setting(_certKey);
    final key = runtime.store.setting(_keyKey);
    final issuedFor = runtime.store.setting(_forKey);

    if (stored != null && key != null && issuedFor == '$_shape:$address') {
      return ExpertCertificate(
        certificatePem: stored,
        privateKeyPem: key,
        issuedFor: address,
      );
    }

    final generated = await _generate(address);
    runtime.store
      ..setSetting(_certKey, generated.certificatePem)
      ..setSetting(_keyKey, generated.privateKeyPem)
      ..setSetting(_forKey, '$_shape:$address');
    return generated;
  }

  /// Wirft das Zertifikat weg. Der nächste Start erzeugt ein neues — für den
  /// Fall, dass jemand anders den Fingerabdruck gesehen haben könnte.
  static void forget(AxiomRuntime runtime) {
    runtime.store
      ..setSetting(_certKey, '')
      ..setSetting(_keyKey, '')
      ..setSetting(_forKey, '');
  }

  /// Erzeugt Schlüssel und Zertifikat — in einem eigenen Isolate.
  ///
  /// RSA-2048 zu erzeugen dauert auf dem Gerät ein bis zwei Sekunden. Auf dem
  /// UI-Thread wäre das ein sichtbarer Hänger beim Einschalten, und ein
  /// Knopf, der eine Sekunde nichts tut, wirkt kaputt.
  static Future<ExpertCertificate> _generate(String address) async {
    final (cert, key) = await Isolate.run(() => _makePair(address));
    return ExpertCertificate(
      certificatePem: cert,
      privateKeyPem: key,
      issuedFor: address,
    );
  }

  /// Alle Wege hinein: über die LAN-Adresse, über den mDNS-Namen und über
  /// eine Portweiterleitung per adb. Fehlt einer, lehnt der Browser genau
  /// auf diesem Weg ab — mit einer Warnung, die keine Ausnahme anbietet.
  ///
  /// Als Menge, damit `127.0.0.1` nicht zweimal dasteht, wenn keine
  /// LAN-Adresse gefunden wurde und der Server auf die Rückfalladresse
  /// ausgestellt wird.
  static List<String> _namesFor(String address) =>
      {address, kAxiomHostname, 'localhost', '127.0.0.1'}.toList();

  static (String, String) _makePair(String address) {
    // RSA statt EC: `SecurityContext` nimmt beides, aber RSA-PEM ist der Weg,
    // den basic_utils vollstaendig unterstuetzt.
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    final csr = X509Utils.generateRsaCsrPem(
      {'CN': address, 'O': 'AXIOM', 'OU': 'Expertenmodus'},
      privateKey,
      publicKey,
    );

    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      _days,
      // **Kein `sans` hier.** Vorher stand hier die vollstaendige Liste, und
      // basic_utils kodierte *jeden* Eintrag als dNSName (Tag 0x82) — einen
      // iPAddress-Typ kennt es nicht. Im Zertifikat stand dann
      // „DNS:192.168.1.42, …, DNS:127.0.0.1". Steht in der Adresszeile eine
      // IP, gleicht der Browser aber ausschliesslich gegen iPAddress-Eintraege
      // ab und ignoriert den CN. Folge: Der Rueckfallweg ueber die IP und der
      // dokumentierte Weg ueber `adb forward` scheiterten dauerhaft — auch
      // nach angenommener Ausnahme —, und aus dem Fingerabdruck-Vergleich
      // wurde eine Namensfehler-Warnung, also genau das Wegklicken, das
      // dieses Zertifikat verhindern soll. Der Block kommt deshalb unten
      // selbst hinein.
      //
      // **Kein `keyUsage`.** basic_utils kodiert die BIT STRING dort mit
      // einem gesetzten Bit in den als ungenutzt deklarierten Stellen. OpenSSL
      // toleriert das, BoringSSL — und damit Dart, Chrome und Android — lehnt
      // das ganze Zertifikat mit CANNOT_PARSE_LEAF_CERT ab. Der Handshake
      // scheitert dann, ohne dass irgendwo steht, warum.
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
    );

    return (
      _withSubjectAltNames(certificate, privateKey, _namesFor(address)),
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }

  // ── Subject Alternative Names ─────────────────────────────────────────
  //
  // Nur so viel DER, wie fuer diesen einen Erweiterungsblock noetig ist.
  // Eine ASN.1-Bibliothek dafuer aufzunehmen waere mehr Abhaengigkeit als
  // Nutzen: Gebraucht werden zwei Tags, ein Laengenfeld und eine Naht.

  /// Objektkennung 2.5.29.17 — `subjectAltName`.
  static const List<int> _sanOid = [0x06, 0x03, 0x55, 0x1D, 0x11];

  /// Setzt den SAN-Block ein und signiert neu.
  ///
  /// Neu signieren ist keine Umstaendlichkeit, sondern die Bedingung: Die
  /// Signatur deckt den `tbsCertificate`-Teil, in dem der Block liegt. Ein
  /// nachtraeglich hineingeschriebenes Byte machte das Zertifikat ungueltig.
  static String _withSubjectAltNames(
    String certificatePem,
    RSAPrivateKey privateKey,
    List<String> names,
  ) {
    final der = _derFromPem(certificatePem);

    // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm,
    //                            signatureValue }
    final certificate = _readTlv(der, 0);
    final tbs = _readTlv(der, certificate.contentStart);
    final signatureAlgorithm = _readTlv(der, tbs.end);

    // Der Erweiterungsblock ist das mit `[3]` markierte Kind von
    // `tbsCertificate` und steht dort als einziges mit diesem Tag.
    _Tlv? extensions;
    var offset = tbs.contentStart;
    while (offset < tbs.end) {
      final child = _readTlv(der, offset);
      if (child.tag == _explicitTag3) {
        extensions = child;
        break;
      }
      offset = child.end;
    }
    if (extensions == null) {
      // Fail-Fast: Ein Zertifikat ohne Erweiterungen haette weder
      // extendedKeyUsage noch SAN und waere fuer jeden Browser wertlos.
      // Stumm eines ohne SAN auszuliefern waere der teurere Fehler.
      throw StateError('Zertifikat ohne Erweiterungsblock');
    }

    // Die vorhandenen Erweiterungen bleiben Byte fuer Byte stehen; nur der
    // SAN-Block kommt dazu.
    final existing = _readTlv(der, extensions.contentStart);
    final rebuiltExtensions = _encodeDer(
      _explicitTag3,
      _encodeDer(_sequence, [
        ...der.sublist(existing.contentStart, existing.end),
        ..._subjectAltNameExtension(names),
      ]),
    );
    final rebuiltTbs = _encodeDer(_sequence, [
      ...der.sublist(tbs.contentStart, extensions.start),
      ...rebuiltExtensions,
    ]);

    // Derselbe Algorithmus, den `generateRsaCsrPem` voreinstellt und den
    // der unveraendert uebernommene `signatureAlgorithm`-Block ausweist.
    final signature = CryptoUtils.rsaSign(privateKey, rebuiltTbs);
    return _pemFromDer(_encodeDer(_sequence, [
      ...rebuiltTbs,
      ...der.sublist(signatureAlgorithm.start, signatureAlgorithm.end),
      // BIT STRING: das fuehrende Null-Byte zaehlt die ungenutzten Bits.
      ..._encodeDer(_bitString, [0, ...signature]),
    ]));
  }

  /// `Extension ::= SEQUENCE { extnID, extnValue OCTET STRING }` mit
  /// `GeneralNames` darin.
  ///
  /// Was wie eine IP-Adresse aussieht, wird als `iPAddress` kodiert, alles
  /// andere als `dNSName`. [InternetAddress.tryParse] loest nichts auf — es
  /// liest nur ein Literal; `axiom.local` und `localhost` fallen damit
  /// richtigerweise auf die Namensseite.
  static Uint8List _subjectAltNameExtension(List<String> names) {
    final generalNames = BytesBuilder();
    for (final name in names) {
      final ip = InternetAddress.tryParse(name);
      generalNames.add(ip == null
          ? _encodeDer(_dnsName, utf8.encode(name))
          : _encodeDer(_ipAddress, ip.rawAddress));
    }
    return _encodeDer(_sequence, [
      ..._sanOid,
      ..._encodeDer(
          _octetString, _encodeDer(_sequence, generalNames.toBytes())),
    ]);
  }

  static const int _sequence = 0x30;
  static const int _bitString = 0x03;
  static const int _octetString = 0x04;
  static const int _explicitTag3 = 0xA3;

  /// `GeneralName ::= CHOICE { … dNSName [2], … iPAddress [7] … }`, jeweils
  /// implizit — deshalb `0x82` und `0x87` statt eines eigenen Typs.
  static const int _dnsName = 0x82;
  static const int _ipAddress = 0x87;

  static Uint8List _encodeDer(int tag, List<int> content) {
    final out = BytesBuilder();
    out.addByte(tag);
    final length = content.length;
    if (length < 0x80) {
      out.addByte(length);
    } else {
      // Lange Form: erst die Zahl der Laengenbytes, dann die Laenge selbst.
      final bytes = <int>[];
      var rest = length;
      while (rest > 0) {
        bytes.insert(0, rest & 0xFF);
        rest >>= 8;
      }
      out.addByte(0x80 | bytes.length);
      out.add(bytes);
    }
    out.add(content);
    return out.toBytes();
  }

  static _Tlv _readTlv(Uint8List der, int start) {
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
    return _Tlv(tag: tag, start: start, contentStart: offset, length: length);
  }

  static Uint8List _derFromPem(String pem) => base64.decode(pem
      .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
      .replaceAll(RegExp(r'\s'), ''));

  static String _pemFromDer(Uint8List der) {
    final body = base64.encode(der);
    final lines = <String>[
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, i + 64 < body.length ? i + 64 : body.length),
    ];
    return '-----BEGIN CERTIFICATE-----\n'
        '${lines.join('\n')}\n'
        '-----END CERTIFICATE-----\n';
  }

  // ── Fuer den Test ─────────────────────────────────────────────────────
  //
  // Eine falsche SAN-Kodierung faellt nicht auf: Der Browser meldet einen
  // Namensfehler, und das sieht aus wie ein Netzproblem. Ohne diesen Zugang
  // waere das Ergebnis nur mit einem echten Browser pruefbar — und damit
  // gar nicht.

  static (String, String) debugMakePair(String address) => _makePair(address);
}

/// Ein DER-Element: Tag, Anfang, Anfang des Inhalts, Länge des Inhalts.
final class _Tlv {
  final int tag;
  final int start;
  final int contentStart;
  final int length;

  const _Tlv({
    required this.tag,
    required this.start,
    required this.contentStart,
    required this.length,
  });

  int get end => contentStart + length;
}
