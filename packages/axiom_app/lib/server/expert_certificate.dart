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

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import '../state/runtime.dart';

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

    if (stored != null && key != null && issuedFor == address) {
      return ExpertCertificate(
        certificatePem: stored,
        privateKeyPem: key,
        issuedFor: issuedFor!,
      );
    }

    final generated = await _generate(address);
    runtime.store
      ..setSetting(_certKey, generated.certificatePem)
      ..setSetting(_keyKey, generated.privateKeyPem)
      ..setSetting(_forKey, address);
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
      // Beide Wege hinein: über die LAN-Adresse und über eine
      // Portweiterleitung per adb.
      sans: [address, 'localhost', '127.0.0.1'],
      // **Kein `keyUsage`.** basic_utils kodiert die BIT STRING dort mit
      // einem gesetzten Bit in den als ungenutzt deklarierten Stellen. OpenSSL
      // toleriert das, BoringSSL — und damit Dart, Chrome und Android — lehnt
      // das ganze Zertifikat mit CANNOT_PARSE_LEAF_CERT ab. Der Handshake
      // scheitert dann, ohne dass irgendwo steht, warum.
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
    );

    return (certificate, CryptoUtils.encodeRSAPrivateKeyToPem(privateKey));
  }
}
