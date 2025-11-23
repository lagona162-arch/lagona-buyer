import 'package:flutter/material.dart';

/// App color constants for easy theme management
class AppColors {
  // Primary Colors - Light Orange/Gold (from brand palette)
  static const Color primary = Color(0xFFFBBE61); // #fbbe61 RGB(251, 190, 97)
  static const Color primaryDark = Color(0xFFE8A84D);
  static const Color primaryLight = Color(0xFFFFD280);

  // Secondary Colors - Dark Grey/Black (from brand palette)
  static const Color secondary = Color(0xFF191B1E); // #191b1e RGB(25, 27, 30)
  static const Color secondaryDark = Color(0xFF0F1114); // Near Black
  static const Color secondaryLight = Color(0xFF2D2F33); // Medium Grey

  // Accent Colors - Same as primary (for consistency)
  static const Color accent = primary;

  // Status Colors (only for notifications/alerts)
  static const Color success = Color(0xFF4CAF50); // Green for success messages
  static const Color error = Color(0xFFEF4444); // Red for error messages

  // Background Colors
  static const Color background = Color(0xFFF5F5F5); // Light grey background (main app background)
  static const Color surface = Color(0xFFFFFFFF); // White surface (card backgrounds)

  // Text Colors
  static const Color textPrimary = Color(0xFF191B1E); // Dark grey (secondary) for main text
  static const Color textSecondary = Color(0xFF6B7280); // Medium grey for subtitles
  static const Color textWhite = Color(0xFFFFFFFF); // White text on colored backgrounds

  // Border Colors
  static const Color border = Color(0xFFE5E7EB); // Light grey border
  static const Color divider = border; // Same as border

  // Button Colors
  static const Color buttonPrimary = primary;
  static const Color buttonDisabled = Color(0xFFD1D5DB);

  // Order Status Colors (using primary/secondary variations)
  static const Color statusPending = Color(0xFFFF9800); // Orange
  static const Color statusAccepted = primary; // Use primary
  static const Color statusPrepared = primaryDark; // Darker primary
  static const Color statusReady = Color(0xFF4CAF50); // Green (for "ready")
  static const Color statusCompleted = secondary; // Dark grey
  static const Color statusCancelled = error; // Red for cancelled

  // Card Colors
  static const Color cardBackground = surface; // White card background
  static const Color cardShadow = Color(0x1A000000); // Subtle shadow

  // Input Colors
  static const Color inputBorder = border;
  static const Color inputBorderFocused = primary;
  static const Color inputBackground = surface; // White input background

  // Navigation Colors
  static const Color navSelected = primary;
  static const Color navUnselected = textSecondary;
}


