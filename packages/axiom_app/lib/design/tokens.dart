/// Design-Tokens.
///
/// Gestaltungsleitbild: **Instrumententafel**, nicht Produktivitaets-App.
/// Die Welt eines Systemizers sind Messgeraete, Frontplatten, Skalen und
/// Telemetrie — keine bunten Karten mit Konfetti.
///
/// Zwei Entscheidungen, die aus dem Nutzerprofil folgen und nicht verhandelbar
/// sind:
///
///  1. **Kein Rot.** Rot heisst Fehler heisst Schuld. Bei Rejection
///     Sensitivity (D10) ist das die teuerste Farbe im Spektrum. Warnungen
///     sind Kupfer, Grenzwerte sind Bernstein. Selbst der Erhaltungsmodus
///     (L3) ist kein Alarm — er ist ein Erfolg des Systems.
///
///  2. **Warmes Anthrazit statt Reinschwarz, Bernstein statt Neon.**
///     Die Palette ist einem Phosphor-Instrument nachempfunden: gedaempft,
///     augenschonend, abends nicht wachhaltend (D8). Ein grelles Interface
///     um 23 Uhr arbeitet gegen das Sleep Gate.
library;

import 'package:flutter/material.dart';

/// Semantische Farbrollen. Jede Rolle hat eine dunkle und eine helle Fassung.
@immutable
final class AxiomPalette {
  /// Seitenhintergrund.
  final Color base;

  /// Flaeche einer Karte — die "Frontplatte".
  final Color panel;

  /// Erhoehte Flaeche (Dialog, aktive Karte).
  final Color panelRaised;

  /// Hairlines, Skalenstriche, Rahmen.
  final Color rule;

  /// Primaertext.
  final Color ink;

  /// Sekundaertext, Beschriftungen.
  final Color inkDim;

  /// Tertiaer — Skalenzahlen, Fussnoten.
  final Color inkFaint;

  /// Signalfarbe. Das Jetzt, das Primaere, die Kapazitaetslinie.
  final Color signal;

  /// Gedrueckter/aktiver Zustand der Signalfarbe.
  final Color signalDeep;

  /// Im Normalbereich, ruhig, erledigt.
  final Color calm;

  /// Aufmerksamkeit — nie Alarm, nie Schuld.
  final Color caution;

  /// Struktur, Metadaten, Information.
  final Color info;

  const AxiomPalette({
    required this.base,
    required this.panel,
    required this.panelRaised,
    required this.rule,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.signal,
    required this.signalDeep,
    required this.calm,
    required this.caution,
    required this.info,
  });

  /// Dunkel — der Standard. Nachts nutzbar, ohne wachzuhalten.
  static const dark = AxiomPalette(
    base: Color(0xFF0E1113),
    panel: Color(0xFF171B1E),
    panelRaised: Color(0xFF1F2529),
    rule: Color(0xFF2A3237),
    ink: Color(0xFFE6E4DE),
    inkDim: Color(0xFF8A9299),
    inkFaint: Color(0xFF5A646B),
    signal: Color(0xFFE8A33D),
    signalDeep: Color(0xFFB8761F),
    calm: Color(0xFF7FA88A),
    caution: Color(0xFFC4653A),
    info: Color(0xFF6E90A4),
  );

  /// Hell — fuer Tageslicht draussen. Dieselbe Instrumenten-Logik,
  /// Bernstein wird abgedunkelt, damit er auf Weiss noch traegt.
  static const light = AxiomPalette(
    base: Color(0xFFF2F1ED),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFFAF9F6),
    rule: Color(0xFFDCDAD3),
    ink: Color(0xFF1A1E21),
    inkDim: Color(0xFF5C666D),
    inkFaint: Color(0xFF8F979D),
    signal: Color(0xFF9A6510),
    signalDeep: Color(0xFF7A4E08),
    calm: Color(0xFF3F6B4F),
    caution: Color(0xFF9C4522),
    info: Color(0xFF3E6072),
  );

  /// Farbe fuer eine Load-Stufe. Bewusst ohne Rot — siehe Kopfkommentar.
  Color forLoadLevel(int level) => switch (level) {
        0 => calm,
        1 => info,
        2 => signal,
        _ => caution,
      };
}

/// Abstaende. Vierer-Raster — genug Struktur fuer ein Instrument,
/// nicht so fein, dass es beliebig wird.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

abstract final class Radii {
  /// Frontplatten haben kleine Radien — sie sind gefraest, nicht geblasen.
  static const double panel = 6;
  static const double control = 4;
  static const double pill = 999;
}

/// Schriftfamilien. Gebuendelt als Assets, nie zur Laufzeit geladen —
/// die App deklariert bewusst keine INTERNET-Berechtigung (ADR-0002).
abstract final class Fonts {
  /// IBM Plex Sans. Entworfen als Hausschrift fuer Ingenieure — humanistisch
  /// genug fuer Fliesstext, technisch genug fuer eine Instrumententafel.
  static const String sans = 'PlexSans';

  /// IBM Plex Mono. Alles, was ein Messwert ist: Zahlen, Regel-IDs,
  /// Skalen, Zeitanker. Mono signalisiert "abgelesen", nicht "gemeint".
  static const String mono = 'PlexMono';
}

/// Dauer von Bewegungen.
///
/// Sparsam dosiert: Die Zielgruppe ist leicht ablenkbar. Bewegung darf
/// Zustandsaenderungen erklaeren, nie unterhalten. Alles respektiert
/// `MediaQuery.disableAnimations`.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration settle = Duration(milliseconds: 320);

  /// Fuer Werte, die sich einpendeln — wie ein Zeiger, der einschwingt.
  static const Curve instrument = Curves.easeOutCubic;
}
