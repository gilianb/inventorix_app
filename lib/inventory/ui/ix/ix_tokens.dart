import 'package:flutter/material.dart';

@immutable
class IxColors {
  static const violet = Color(0xFF6C5CE7);
  static const mint = Color(0xFF00D1B2);
  static const amber = Color(0xFFFFB545);
  static const green = Color(0xFF22C55E);

  /// Your “ink” color used in app bar icons etc.
  static const ink = Color.fromARGB(255, 2, 35, 61);
}

@immutable
class IxRadii {
  static const r8 = BorderRadius.all(Radius.circular(8));
  static const r12 = BorderRadius.all(Radius.circular(12));
  static const r14 = BorderRadius.all(Radius.circular(14));
  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r20 = BorderRadius.all(Radius.circular(20));
  static const r999 = BorderRadius.all(Radius.circular(999));
}

@immutable
class IxSpace {
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets card = EdgeInsets.all(12);

  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

@immutable
class IxMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
}
