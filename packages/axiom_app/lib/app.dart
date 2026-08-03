/// App-Shell: Theme, Navigation, Onboarding-Weiche.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/theme.dart';
import 'design/tokens.dart';
import 'design/widgets/axiom_mark.dart';
import 'platform/intent_handler.dart';
import 'screens/now_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/state_screen.dart';
import 'screens/system_screen.dart';
import 'i18n/i18n.dart';
import 'state/providers.dart';

class AxiomApp extends ConsumerWidget {
  const AxiomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    final scheme = ref.watch(schemeProvider);
    final textSize = ref.watch(textSizeProvider);
    return MaterialApp(
      title: 'AXIOM',
      debugShowCheckedModeBanner: false,
      theme: buildAxiomTheme(brightness: Brightness.light, scheme_: scheme),
      darkTheme: buildAxiomTheme(brightness: Brightness.dark, scheme_: scheme),
      themeMode: switch (mode) {
        1 => ThemeMode.dark,
        2 => ThemeMode.light,
        _ => ThemeMode.system,
      },
      locale: language.locale,
      supportedLocales: AppLanguage.values.map((l) => l.locale),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Ueber der Navigation, damit jeder Screen dieselbe Sprache und
      // dieselbe Textgroesse sieht.
      builder: (context, child) => _Display(
        language: language,
        textSize: textSize,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AxiomGate(),
    );
  }
}

/// Setzt Sprache und Textgroesse fuer den gesamten Baum.
///
/// Die Systemeinstellung wird **multipliziert**, nicht ersetzt. Wer im
/// Betriebssystem bereits groesser gestellt hat, soll das hier nicht wieder
/// verlieren — und wer „Kompakt" waehlt, bekommt tatsaechlich kompakter,
/// nicht bloss „nicht kleiner als". Die Grenzen verhindern beides:
/// unlesbar klein und so gross, dass das Layout bricht.
class _Display extends StatelessWidget {
  final AppLanguage language;
  final TextSize textSize;
  final Widget child;

  const _Display({
    required this.language,
    required this.textSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Effektiver Systemfaktor, aus dem Scaler zurueckgerechnet — es gibt
    // keinen direkten Weg, zwei TextScaler zu verketten.
    final system = media.textScaler.scale(16) / 16;
    final combined = (system * textSize.scale).clamp(0.85, 2.4);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(combined)),
      child: AxiomLanguage(language: language, child: child),
    );
  }
}

/// Entscheidet zwischen Onboarding und Hauptansicht.
class AxiomGate extends ConsumerStatefulWidget {
  const AxiomGate({super.key});

  @override
  ConsumerState<AxiomGate> createState() => _GateState();
}

class _GateState extends ConsumerState<AxiomGate> {
  bool? _onboarded;

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(runtimeProvider);

    return runtime.when(
      loading: () => const _Splash(),
      error: (e, _) => _StartupError(error: e),
      data: (rt) {
        final done = _onboarded ?? rt.onboardingDone;
        if (!done) {
          return OnboardingScreen(
            onDone: () => setState(() => _onboarded = true),
          );
        }
        return const IntentHandler(child: HomeShell());
      },
    );
  }
}

/// Flache Navigation. Drei Ziele, nicht mehr — jeder weitere Reiter ist
/// eine Entscheidung, die der Nutzer treffen muss, bevor er irgendwo ist.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    NowScreen(),
    StateScreen(),
    SystemScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.adjust_outlined),
            selectedIcon: Icon(Icons.adjust),
            label: context.t('Jetzt'),
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: context.t('Zustand'),
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: context.t('System'),
          ),
        ],
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AxiomWordmark(markSize: 38),
            const SizedBox(height: Space.xl),
            SizedBox(
              width: 80,
              child: LinearProgressIndicator(
                minHeight: 1,
                backgroundColor: p.rule,
                color: p.signal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  final Object error;
  const _StartupError({required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('START FEHLGESCHLAGEN'),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: Space.md),
                Text(context.t('AXIOM konnte nicht starten.'),
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: Space.lg),
                Text('$error', style: monoStyle(context, size: 12)),
              ],
            ),
          ),
        ),
      );
}
