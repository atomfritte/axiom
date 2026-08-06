/// Meldet den Expertenmodus im lokalen Netz als `axiom.local` an.
///
/// **Wozu.** Ohne das steht auf dem Telefon eine IP, die man abtippt — und
/// die sich ändert, sobald der Router eine neue vergibt. Dann stimmt auch
/// das Zertifikat nicht mehr, und die Warnung im Browser kommt erneut. Ein
/// Name, der bleibt, ist kein Komfort, sondern die Bedingung dafür, dass
/// der Fingerabdruck-Vergleich zur Gewohnheit wird statt zum Wegklicken.
///
/// **Wie.** Multicast DNS (RFC 6762): Fragt ein Rechner im Netz nach
/// `axiom.local`, liegt diese Frage als UDP-Paket auf 224.0.0.251:5353. Wer
/// den Namen trägt, antwortet mit seiner Adresse. Genau das tut diese
/// Klasse — und zusätzlich meldet sie sich beim Start unaufgefordert an,
/// damit der Name sofort bekannt ist.
///
/// **Und die Zusage aus ADR-0005?** „AXIOM ruft nichts von sich aus auf"
/// meinte: kein Client, keine Verbindung nach außen, nichts, das Daten
/// hinausträgt. mDNS ist etwas anderes und bleibt damit vereinbar:
///
/// - Es geht an eine **link-lokale Multicast-Adresse**. Router leiten
///   224.0.0.251 nicht weiter; das Paket verlässt das eigene Netzsegment
///   nicht. Es gibt keinen Empfänger außerhalb.
/// - Der Inhalt ist der Name und die IP-Adresse **dieses** Geräts. Keine
///   Nutzdaten, keine Kennung, nichts aus der Datenbank.
/// - Es läuft nur, solange der Expertenmodus läuft — mit ihm an, mit ihm
///   aus. Beim Beenden geht ein Abschied (TTL 0) hinaus, damit der Name
///   nicht in fremden Zwischenspeichern stehen bleibt.
///
/// Die Zusage ist damit enger geworden und nicht schwächer: AXIOM ruft
/// nichts auf. Es sagt, wie es heißt, und nur im eigenen Netz.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../platform/android_bridge.dart';

/// Die feste Gruppe und der feste Port aus RFC 6762.
const String kMdnsGroup = '224.0.0.251';
const int kMdnsPort = 5353;

/// Der Name, unter dem AXIOM erreichbar ist.
///
/// Ohne `.local` wäre es kein mDNS-Name, sondern eine Anfrage an den
/// Router — und die ginge ins Internet.
const String kAxiomHostname = 'axiom.local';

/// Wie lange andere Rechner die Antwort behalten dürfen.
///
/// Zwei Minuten: kurz genug, dass ein Adresswechsel nach einem
/// Netzwerkwechsel nicht lange nachhallt, lang genug, dass nicht bei jedem
/// Seitenaufruf neu gefragt wird.
const int kMdnsTtl = 120;

/// Wie der Socket entsteht.
///
/// Nur der Test setzt das. Ein Netz ohne Multicast laesst sich auf dem
/// Rechner nicht herstellen, und genau dieser Fehlerfall — `bind` oder
/// `joinMulticast` wirft — war der, in dem Sperre und Socket haengenblieben.
typedef MdnsSocketBinder = Future<RawDatagramSocket> Function();

final class MdnsResponder {
  MdnsResponder({MdnsSocketBinder? bind}) : _bind = bind ?? _bindMdnsPort;

  final MdnsSocketBinder _bind;

  RawDatagramSocket? _socket;
  String? _ip;
  bool _holdsMulticastLock = false;

  bool get isRunning => _socket != null;

  /// Ob die Multicast-Sperre gerade gehalten wird.
  ///
  /// Sichtbar, weil sie auf der Systemseite **nicht** referenzgezaehlt ist
  /// (`setReferenceCounted(false)`): Wird sie einmal nicht freigegeben,
  /// bleibt sie bis zum Prozessende stehen und kostet die ganze Zeit Strom.
  /// Die Zusicherung lautet: gehalten genau dann, wenn der Responder laeuft.
  bool get holdsMulticastLock => _holdsMulticastLock;

  static Future<RawDatagramSocket> _bindMdnsPort() => RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kMdnsPort,
        reuseAddress: true,
        reusePort: true,
      );

  /// Beginnt zu antworten. [ip] ist die Adresse, die ausgeliefert wird.
  ///
  /// Schlägt es fehl, ist das kein Grund, den Server nicht zu starten: Die
  /// IP funktioniert weiterhin. In manchen Netzen ist Multicast schlicht
  /// gesperrt, und das ist eine Eigenschaft des Netzes, kein Fehler hier.
  Future<bool> start(String ip) async {
    if (isRunning) return true;
    // Zuerst die Sperre: Ohne sie kaeme die Frage nie an, und der Socket
    // laege nur herum.
    await _holdLock();
    RawDatagramSocket? socket;
    try {
      socket = await _bind();
      socket.multicastHops = 255;
      socket.joinMulticast(InternetAddress(kMdnsGroup));

      _socket = socket;
      _ip = ip;
      socket.listen(_onEvent);

      // Unaufgefordert ankündigen. Ohne das ist der Name erst bekannt,
      // wenn jemand danach fragt — und der Browser fragt erst, wenn man
      // ihn schon eingetippt hat.
      _announce();
      return true;
    } on Object {
      // Vorher stand hier `await stop()`. Das kehrte bei `_socket == null`
      // sofort zurueck — und `_socket` wird erst nach `joinMulticast`
      // gesetzt. Wirft eines der drei davor, blieb die Sperre fuer die
      // Prozesslebensdauer gehalten, und ein bereits gebundener Socket hielt
      // Port 5353 bis zum Prozessende, je Startversuch einer. Deshalb hier
      // beides ausdruecklich und ohne Umweg ueber stop().
      socket?.close();
      _socket = null;
      _ip = null;
      await _releaseLock();
      return false;
    }
  }

  /// Hört auf zu antworten und nimmt den Namen zurück.
  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      // Auch ohne Socket kann die Sperre stehen — etwa wenn zwischen
      // Greifen und Binden abgebrochen wurde.
      await _releaseLock();
      return;
    }
    try {
      // TTL 0 heisst: vergesst den Eintrag. Ohne das zeigt der Name noch
      // zwei Minuten auf ein Telefon, das nicht mehr lauscht — und der
      // Browser meldet einen Verbindungsfehler statt „ist aus".
      socket.send(
        _answerPacket(ttl: 0),
        InternetAddress(kMdnsGroup),
        kMdnsPort,
      );
    } on Object {
      // Netz schon weg. Der Eintrag laeuft dann von selbst ab.
    }
    socket.close();
    _ip = null;
    await _releaseLock();
  }

  // ── Multicast-Sperre ──────────────────────────────────────────────────
  //
  // Sie kostet Strom. Sie haengt am Expertenmodus, nicht am App-Start.
  // Der Merker davor ist kein Zwischenspeicher, sondern die einzige Stelle,
  // an der ueber Greifen und Loslassen entschieden wird — sonst kann er
  // von der Wirklichkeit abweichen.

  Future<void> _holdLock() async {
    if (_holdsMulticastLock) return;
    _holdsMulticastLock = true;
    await AndroidBridge.multicastLock(hold: true);
  }

  Future<void> _releaseLock() async {
    if (!_holdsMulticastLock) return;
    _holdsMulticastLock = false;
    await AndroidBridge.multicastLock(hold: false);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    if (!_asksForAxiom(datagram.data)) return;
    _announce();
  }

  void _announce() {
    final socket = _socket;
    if (socket == null || _ip == null) return;
    try {
      socket.send(
        _answerPacket(ttl: kMdnsTtl),
        InternetAddress(kMdnsGroup),
        kMdnsPort,
      );
    } on Object {
      // Ein verlorenes Paket ist bei mDNS vorgesehen — es wird ohnehin
      // erneut gefragt.
    }
  }

  // ── Paketbau ──────────────────────────────────────────────────────────

  /// Fragt dieses Paket nach `axiom.local`?
  ///
  /// Bewusst schlicht: Der Header wird gelesen, dann jede Frage im Paket
  /// mit dem eigenen Namen verglichen. Kein vollständiger DNS-Parser —
  /// beantwortet wird genau ein Name, alles andere wird verworfen.
  static bool _asksForAxiom(Uint8List data) {
    if (data.length < 12) return false;
    final flags = (data[2] << 8) | data[3];
    // Bit 15 gesetzt heisst Antwort. Antworten anderer interessieren nicht.
    if (flags & 0x8000 != 0) return false;

    final questions = (data[4] << 8) | data[5];
    var offset = 12;
    for (var i = 0; i < questions; i++) {
      final (name, next) = _readName(data, offset);
      if (name == null) return false;
      offset = next + 4; // Typ und Klasse ueberspringen
      if (offset > data.length) return false;
      if (name.toLowerCase() == kAxiomHostname) return true;
    }
    return false;
  }

  /// Liest einen DNS-Namen. Gibt den Namen und die Position dahinter
  /// zurück, oder `null`, wenn das Paket nicht lesbar ist.
  static (String?, int) _readName(Uint8List data, int start) {
    final parts = <String>[];
    var offset = start;
    // Zeiger werden nicht verfolgt: In einer Frage kommen sie nicht vor,
    // und ein Zeiger auf sich selbst waere eine Endlosschleife.
    while (offset < data.length) {
      final length = data[offset];
      if (length == 0) return (parts.join('.'), offset + 1);
      if (length & 0xC0 != 0) return (null, offset);
      offset++;
      if (offset + length > data.length) return (null, offset);
      parts.add(String.fromCharCodes(data, offset, offset + length));
      offset += length;
    }
    return (null, offset);
  }

  /// Eine mDNS-Antwort mit einem A-Eintrag für `axiom.local`.
  Uint8List _answerPacket({required int ttl}) {
    final octets = (_ip ?? '0.0.0.0').split('.').map(int.parse).toList();
    final name = _encodeName(kAxiomHostname);
    final packet = BytesBuilder();

    // Header: keine Kennung (mDNS-Antworten sind nicht zugeordnet),
    // Antwort-Bit und „autoritativ" gesetzt, eine Antwort.
    packet.add([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0]);

    packet.add(name);
    // Typ A (1), Klasse IN (1) mit gesetztem Cache-Flush-Bit (0x8000).
    packet.add([0, 1, 0x80, 1]);
    packet.add([
      (ttl >> 24) & 0xFF,
      (ttl >> 16) & 0xFF,
      (ttl >> 8) & 0xFF,
      ttl & 0xFF,
    ]);
    packet.add([0, 4]);
    packet.add(octets);

    return packet.toBytes();
  }

  // ── Fuer den Test ─────────────────────────────────────────────────────
  //
  // Paketbau faellt nicht auf, wenn er danebenliegt: Das Geraet antwortet
  // dann einfach nie. Ohne diese beiden Zugaenge waere der Bytecode nur
  // ueber ein echtes Netz pruefbar — und damit gar nicht.

  static bool debugAsksForAxiom(Uint8List data) => _asksForAxiom(data);

  static Uint8List debugAnswer(String ip, int ttl) {
    final responder = MdnsResponder().._ip = ip;
    return responder._answerPacket(ttl: ttl);
  }

  static Uint8List _encodeName(String name) {
    final out = BytesBuilder();
    for (final label in name.split('.')) {
      out.addByte(label.length);
      out.add(label.codeUnits);
    }
    out.addByte(0);
    return out.toBytes();
  }
}
