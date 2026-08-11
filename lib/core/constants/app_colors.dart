import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primarios
  static const Color primary = Color(0xFFCA0B0B);
  static const Color primaryDark = Color(0xFF9E0808);
  static const Color primaryLight = Color(0xFFE84040);

  // Fondo
  static const Color background = Color(0xFFF7F8FD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEEEFF5);

  // Texto
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textHint = Color(0xFFB0B3C1);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Estados
  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Bordes y divisores
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);

  // Sombras
  static const Color shadow = Color(0x1A000000);
  static const Color shadowMedium = Color(0x33000000);

  // Categorías de productos (chips)
  static const Color chipSelected = primary;
  static const Color chipUnselected = surfaceVariant;

  // Roles
  static const Color clienteColor = Color(0xFF7C3AED);
  static const Color domiciliarioColor = Color(0xFF0891B2);
  static const Color adminColor = primary;

  // Carrito / badge
  static const Color badge = primary;
  static const Color badgeText = Color(0xFFFFFFFF);

  // Overlay
  static const Color overlay = Color(0x80000000);
}
