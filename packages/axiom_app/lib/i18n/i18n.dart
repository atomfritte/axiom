/// Zweisprachigkeit — Deutsch als Quelle, Englisch als Übersetzung.
///
/// **Warum der deutsche Text der Schlüssel ist.** Die naheliegende Lösung
/// wären abstrakte Bezeichner (`nowScreen.emptyTitle`). Dagegen spricht die
/// wichtigste Eigenschaft dieser Oberfläche: Der Ton entscheidet über die
/// Wirkung. Ein Satz wie „Nichts in Reichweite" ist eine bewusste Wahl gegen
/// „Du hast 14 offene Aufgaben" — und diese Wahl muss im Quelltext lesbar
/// bleiben, dort wo sie getroffen wird, nicht drei Dateien weiter hinter
/// einem Bezeichner. `language_test` prüft den Ton am Quelltext; mit
/// Bezeichnern hätte es nichts mehr zu prüfen.
///
/// Fehlt eine Übersetzung, erscheint der deutsche Satz. Das ist sichtbar
/// unfertig statt still falsch — und `i18n_test` lässt es gar nicht so weit
/// kommen: Jeder übersetzbare Text im Quelltext braucht einen Eintrag.
///
/// Platzhalter sind `{0}`, `{1}`, … und werden in der Reihenfolge der
/// übergebenen Argumente ersetzt. Absicht: Im Englischen darf die Wortfolge
/// eine andere sein.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/widgets.dart';

import 'en.dart';

enum AppLanguage {
  de('de', 'Deutsch'),
  en('en', 'English');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  Locale get locale => Locale(code);

  static AppLanguage parse(String? code) => AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.de,
      );

  /// Die Sprache des Geräts — für den allerersten Start.
  ///
  /// Deutsch bleibt der Rückfall, weil es die Quellsprache ist: Fehlt eine
  /// Übersetzung, erscheint ohnehin der deutsche Satz. Eine unbekannte
  /// Systemsprache landet also nicht bei einer halb leeren Oberfläche.
  static AppLanguage fromLocale(Locale locale) => AppLanguage.values.firstWhere(
        (l) => l.code == locale.languageCode,
        orElse: () => AppLanguage.en,
      );
}

/// Übersetzt einen deutschen Quelltext. Für Code ohne `BuildContext` —
/// Widget-Text, Benachrichtigungen, alles was ans Betriebssystem geht.
String translate(
  AppLanguage language,
  String source, [
  List<Object?> args = const [],
]) {
  final text = language == AppLanguage.de ? source : (kEnglish[source] ?? source);
  if (args.isEmpty) return text;
  var result = text;
  for (var i = 0; i < args.length; i++) {
    result = result.replaceAll('{$i}', '${args[i]}');
  }
  return result;
}

/// Trägt die Sprache durch den Baum.
///
/// Bewusst ein InheritedWidget und kein Zugriff auf den Riverpod-Container:
/// So gilt in Tests genau die Sprache, die der Test setzt, ohne dass ein
/// Provider überschrieben werden muss.
class AxiomLanguage extends InheritedWidget {
  final AppLanguage language;

  const AxiomLanguage({
    super.key,
    required this.language,
    required super.child,
  });

  static AppLanguage of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AxiomLanguage>()
          ?.language ??
      AppLanguage.de;

  @override
  bool updateShouldNotify(AxiomLanguage oldWidget) =>
      oldWidget.language != language;
}

extension I18nContext on BuildContext {
  /// Übersetzt, passend zur eingestellten Sprache.
  ///
  /// Geschrieben wie `context.axiom` für die Farben — dasselbe Muster für
  /// dieselbe Art von Zugriff.
  String t(String source, [List<Object?> args = const []]) =>
      translate(AxiomLanguage.of(this), source, args);

  /// Übersetzt einen Satz aus dem Kern.
  ///
  /// Der Kern liefert Quelltext und Werte getrennt ([Phrase]) — genau
  /// deshalb lässt sich ein Satz wie „37 min über der geplanten Zeit"
  /// übersetzen, ohne die Zahl aus dem fertigen Satz zurückzurechnen.
  String p(Phrase phrase) => t(phrase.source, phrase.args);

  /// Regeltext in der eingestellten Sprache.
  ///
  /// Regeln sind Daten, keine Oberfläche: Ihre Übersetzung steht im YAML
  /// (`title_en`, `rationale_en`), nicht in der Wörterliste. Fehlt sie,
  /// erscheint der deutsche Text.
  String ruleTitle(Rule rule) => rule.titleFor(AxiomLanguage.of(this).code);

  String ruleRationale(Rule rule) =>
      rule.rationaleFor(AxiomLanguage.of(this).code);

  AppLanguage get language => AxiomLanguage.of(this);
}
