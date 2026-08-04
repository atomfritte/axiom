import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'design/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Rand-zu-Rand: Der Zeitanker soll bis in die Systemleisten reichen.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  // Was Flutter im Release sonst zeigt, wenn ein Widget beim Bauen wirft:
  // eine graue Fläche ohne Text. Das ist von einem Absturz nicht zu
  // unterscheiden — und es ist genau der Moment, in dem man wissen will, ob
  // die Daten noch da sind.
  //
  // Kein Absenden, kein Bericht, keine Entschuldigung: Es gibt niemanden, an
  // den das ginge (ADR-0005). Nur die Aussage und der Weg zurück.
  ErrorWidget.builder = (details) => _Broken(details: details);

  runApp(const ProviderScope(child: AxiomApp()));
}

/// Ein Bauteil hat aufgegeben — der Rest der App läuft weiter.
///
/// Ohne Schuldsprache und ohne Ausrufezeichen: Ein Fehler in AXIOM ist ein
/// Fehler in AXIOM, keine Verfehlung des Nutzers [R7]. Und mit dem Satz über
/// die Daten, weil das hier die eigentliche Frage ist.
class _Broken extends StatelessWidget {
  final FlutterErrorDetails details;
  const _Broken({required this.details});

  @override
  Widget build(BuildContext context) {
    // Bewusst ohne `Theme.of(context)`: Liegt der Fehler oberhalb des
    // Themes, gäbe es hier den nächsten.
    const ink = Color(0xFFE8E8EA);
    const faint = Color(0xFF8A8A92);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0E0F11),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DIESER TEIL WIRD GERADE NICHT ANGEZEIGT',
                  style: TextStyle(
                    fontFamily: Fonts.mono,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    color: faint,
                  ),
                ),
                const SizedBox(height: Space.md),
                const Text(
                  'Deine Daten sind unberührt. Ereignisse werden nur '
                  'angehängt, nie überschrieben — es geht nichts verloren, '
                  'auch nicht durch diesen Fehler.',
                  style: TextStyle(fontSize: 15, height: 1.45, color: ink),
                ),
                const SizedBox(height: Space.lg),
                const Text(
                  'Zurück und noch einmal öffnen genügt meistens. Bleibt es, '
                  'hilft ein Neustart der App.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: faint),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: Space.xl),
                  Flexible(
                    child: Text(
                      details.exceptionAsString(),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: Fonts.mono,
                        fontSize: 11,
                        color: faint,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
