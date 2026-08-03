/// AXIOM Kern — Domain, State Engine, Rule Engine.
///
/// Reines Dart. Keine Flutter-, Platform- oder I/O-Abhaengigkeit.
/// Dieser Kern ist ohne Geraet, ohne Emulator und ohne UI testbar — Regeln
/// werden getestet, nicht angeklickt.
library;

export 'src/domain/anchor.dart';
export 'src/domain/condition.dart';
export 'src/domain/decision.dart';
export 'src/domain/event.dart';
export 'src/domain/focus.dart';
export 'src/domain/intercept.dart';
export 'src/domain/rule.dart';
export 'src/domain/sensation.dart';
export 'src/domain/state_vector.dart';
export 'src/domain/task.dart';
export 'src/engine/atomizer.dart';
export 'src/engine/baseline.dart';
export 'src/engine/eval_context.dart';
export 'src/engine/load_monitor.dart';
export 'src/engine/review.dart';
export 'src/engine/rule_engine.dart';
export 'src/engine/state_deriver.dart';
export 'src/ports/ports.dart';
