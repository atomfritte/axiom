/// Die Freigabe des Expertenmodus als Benachrichtigung (ADR-0005 §3a).
///
/// **Was hier geprüft wird und was nicht.** Dies ist ein Quelltexttest, wie
/// `platform_integration_test.dart` — die Kotlin-Seite ist die einzige
/// Ebene, durch die kein Dart-Werkzeug greift, und ein Widget-Test fällt
/// durch sie hindurch. Er kann nicht zeigen, dass Android die Meldung
/// wirklich anzeigt. Er kann zeigen, dass die beiden Eigenschaften, an denen
/// hier die Anmeldung für Gesundheitsdaten hängt, im Quelltext stehen — und
/// dass sie nicht unbemerkt verschwinden.
///
/// **Die beiden Eigenschaften.** Ein „Freigeben"-Knopf in der Leiste wäre
/// der naheliegende Entwurf und aus zwei unabhängigen Gründen ein Loch:
///
/// 1. `Notification.Action.actionIntent` ist ein öffentliches Feld. Jede App
///    mit `BIND_NOTIFICATION_LISTENER_SERVICE` — und jede gekoppelte Uhr,
///    denn genau so funktionieren Aktionsknöpfe dort — bekommt die
///    Benachrichtigung samt Aktionen und kann `actionIntent.send()` rufen,
///    mit der Identität von AXIOM. `setAuthenticationRequired` hilft nicht:
///    diese Prüfung sitzt in SystemUIs Klickbehandlung, nicht in der Kapsel.
/// 2. Ein `PendingIntent.getBroadcast` feuert auf einem gesperrten Gerät
///    sofort. Genau deshalb funktioniert die Schnellerfassung ohne
///    Entsperren — und genau deshalb darf die Freigabe kein Broadcast sein.
///
/// Beides zusammen ergibt die Regel, die dieser Test festhält: **Die Meldung
/// entscheidet nichts, sie navigiert.**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nur der Code, ohne Kommentare.
///
/// Nötig, weil `ApprovalNotice.kt` die verworfenen Bauformen ausdrücklich
/// **benennt** — der Kopfkommentar erklärt, warum dort kein Broadcast und
/// kein klingender Kanal steht. Ein Test, der den Rohtext durchsucht, fiele
/// genau über diese Begründung. Und sie wegzulassen wäre der falsche Ausweg:
/// Ohne sie baut die nächste Runde den naheliegenden Entwurf wieder ein.
String codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) return '';
      final slashes = line.indexOf('//');
      return slashes < 0 ? line : line.substring(0, slashes);
    })
    .join('\n');

void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/de/atomfritte/axiom/ApprovalNotice.kt',
  ).readAsStringSync();
  final kotlinCode = codeOnly(kotlin);
  final activity = File(
    'android/app/src/main/kotlin/de/atomfritte/axiom/MainActivity.kt',
  ).readAsStringSync();
  final server = File('lib/server/expert_server.dart').readAsStringSync();
  final handler = File('lib/platform/intent_handler.dart').readAsStringSync();
  final bridge = File('lib/platform/android_bridge.dart').readAsStringSync();

  group('Die Meldung entscheidet nichts, sie navigiert', () {
    test('sie trägt keinen einzigen Aktionsknopf', () {
      // Der Kern der Sache. Ein Knopf hier wäre eine Fähigkeit, die AXIOM an
      // jeden Benachrichtigungsleser auf dem Gerät verteilt — und der
      // vergleicht nichts, der feuert nur.
      expect(kotlinCode, isNot(contains('addAction')),
          reason: 'Ein Freigabeknopf in der Leiste ist über '
              'Notification.Action.actionIntent von außen auslösbar');
      expect(kotlinCode, isNot(contains('RemoteInput')));
    });

    test('sie öffnet eine Activity, sie feuert keinen Broadcast', () {
      // `getActivity` erzwingt ab API 26 immer den Sperrbildschirm, ohne
      // Versionsabfrage. `getBroadcast` feuert ohne Entsperren.
      expect(kotlin, contains('PendingIntent.getActivity'));
      expect(kotlinCode, isNot(contains('PendingIntent.getBroadcast')),
          reason: 'Ein Broadcast gäbe vom gesperrten Telefon aus frei');
      expect(kotlinCode, isNot(contains('PendingIntent.getService')));
    });

    test('die Kapsel ist unveränderlich und unterscheidet zwei Anfragen', () {
      // `Intent.filterEquals` vergleicht Extras NICHT. Zwei Anfragen, die
      // sich nur in einem Extra unterscheiden, ergäben dieselbe Kapsel mit
      // der alten Zahl — ein Knopf, der stumm nichts tut.
      expect(kotlin, contains('FLAG_IMMUTABLE'));
      expect(kotlin, contains('setIdentifier(number)'),
          reason: 'Die Zahl muss in einem Feld stehen, das filterEquals '
              'vergleicht — nicht in den Extras');
      expect(kotlin, contains('FLAG_CANCEL_CURRENT'),
          reason: 'UPDATE_CURRENT schriebe auch Kopien um, die anderswo '
              'schon liegen');
    });

    test('sichtbar und still, nicht klingend', () {
      // `/api/auth/request` braucht keine Anmeldung: Jeder im selben Netz
      // kann alle 90 Sekunden eine neue Anfrage stellen. Auf einem
      // klingenden Kanal wäre das ein Ton im Minutentakt aus dem Netz,
      // ohne Cooldown (R2).
      expect(kotlin, contains('"axiom_nudge"'));
      expect(kotlinCode, isNot(contains('axiom_intervene')));
      expect(kotlinCode, isNot(contains('axiom_enforce')));
      expect(kotlin, contains('setSilent(true)'));
    });

    test('sie verrät die Zahl nicht auf einem gesicherten Sperrbildschirm', () {
      expect(kotlin, contains('VISIBILITY_PRIVATE'));
      expect(kotlinCode, isNot(contains('VISIBILITY_PUBLIC')));
    });
  });

  group('Der Weg von der Leiste auf den Bildschirm ist durchgehend', () {
    test('die Aktion steht in der Whitelist der Startaktionen', () {
      // Fehlt sie dort, gibt `consumeLaunchAction` null zurück und die App
      // öffnet auf der Übersicht — der Nutzer stünde wieder vor den fünf
      // Schritten, ohne dass irgendwo ein Fehler steht.
      expect(activity, contains('ApprovalNotice.ACTION_APPROVE'));
    });

    test('die Dart-Seite fängt sie ab und öffnet den Expertenmodus', () {
      expect(handler, contains("case 'de.atomfritte.axiom.EXPERT_APPROVE':"));
      expect(handler, contains('ExpertScreen'));
    });

    test('die Brücke kann anzeigen und zurücknehmen', () {
      expect(bridge, contains("_invoke('approvalShow'"));
      expect(bridge, contains("_invoke('approvalHide')"));
      expect(activity, contains('"approvalShow"'));
      expect(activity, contains('"approvalHide"'));
    });
  });

  group('Die Frist steht an zwei Stellen — und sie stimmen überein', () {
    test('Android zieht die Meldung genau dann zurück, wenn sie tot ist', () {
      // Die Doppelung ist die billigere von zwei Varianten: `setTimeoutAfter`
      // lässt Android die Meldung selbst zurückziehen, ohne dass auf der
      // Dart-Seite ein Timer laufen muss (der liefe auf der echten Uhr und
      // wäre nicht prüfbar). Laufen die Werte auseinander, bleibt eine tote
      // Zahl in der Leiste stehen — und genau die ist die, bei der ein
      // später Tipp auf eine fremde neue Anfrage träfe.
      final kotlinMs = RegExp(r'TIMEOUT_MS = ([\d_]+)L').firstMatch(kotlin);
      final dartSeconds =
          RegExp(r'lifetime = Duration\(seconds: (\d+)\)').firstMatch(server);

      expect(kotlinMs, isNotNull, reason: 'ApprovalNotice.TIMEOUT_MS fehlt');
      expect(dartSeconds, isNotNull, reason: '_AuthRequest.lifetime fehlt');
      expect(
        int.parse(kotlinMs!.group(1)!.replaceAll('_', '')),
        int.parse(dartSeconds!.group(1)!) * 1000,
        reason: 'ApprovalNotice.TIMEOUT_MS und _AuthRequest.lifetime sind '
            'auseinandergelaufen',
      );
    });
  });
}
