import 'package:flutter/material.dart';

class BeakTheme {
  static const Color backgroundBlack = Color(0xFF000000);
  
  static const Color primaryText = Colors.white;
  static final Color secondaryText = Colors.white.withValues(alpha: 0.6);
  
  static const Color goldLight = Color(0xFFF5E6C8);
  static const Color goldDark = Color(0xFFD4A574);
  
  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldLight, goldDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Widget applyGradient(Widget child) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => goldGradient.createShader(bounds),
      child: child,
    );
  }
}
