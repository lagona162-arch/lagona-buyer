import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';

/// Shows a user-friendly error dialog based on the error type
Future<void> showErrorDialog(
  BuildContext context,
  dynamic error, {
  String? title,
  String? customMessage,
}) async {
  if (!context.mounted) return;

  final errorInfo = _parseError(error);
  
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            errorInfo.icon,
            color: AppColors.error,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title ?? errorInfo.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        customMessage ?? errorInfo.message,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text(
            'OK',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Parses different error types and returns user-friendly messages
_ErrorInfo _parseError(dynamic error) {
  final errorString = error.toString().toLowerCase();
  
  // Supabase Auth Errors
  if (error is AuthException || errorString.contains('authapiexception')) {
    if (errorString.contains('invalid_credentials') || 
        errorString.contains('invalid login credentials')) {
      return _ErrorInfo(
        title: 'Login Failed',
        message: 'The email or password you entered is incorrect. Please check your credentials and try again.',
        icon: Icons.lock_outline,
      );
    }
    
    if (errorString.contains('email_not_confirmed') || 
        errorString.contains('email not confirmed')) {
      return _ErrorInfo(
        title: 'Email Not Verified',
        message: 'Please verify your email address before signing in. Check your inbox for a verification link.',
        icon: Icons.email_outlined,
      );
    }
    
    if (errorString.contains('user_not_found') || 
        errorString.contains('user not found')) {
      return _ErrorInfo(
        title: 'Account Not Found',
        message: 'No account found with this email address. Please sign up to create a new account.',
        icon: Icons.person_outline,
      );
    }
    
    if (errorString.contains('too_many_requests') || 
        errorString.contains('too many requests')) {
      return _ErrorInfo(
        title: 'Too Many Attempts',
        message: 'You have made too many login attempts. Please wait a few minutes before trying again.',
        icon: Icons.timer_outlined,
      );
    }
    
    if (errorString.contains('weak_password') || 
        errorString.contains('password')) {
      return _ErrorInfo(
        title: 'Password Error',
        message: 'The password does not meet the requirements. Please use a stronger password.',
        icon: Icons.lock_outline,
      );
    }
    
    if (errorString.contains('email_already_registered') || 
        errorString.contains('user already registered')) {
      return _ErrorInfo(
        title: 'Email Already Exists',
        message: 'An account with this email already exists. Please sign in instead or use a different email.',
        icon: Icons.email_outlined,
      );
    }
  }
  
  // Network Errors
  if (errorString.contains('network') || 
      errorString.contains('connection') ||
      errorString.contains('timeout') ||
      errorString.contains('socket')) {
    return _ErrorInfo(
      title: 'Connection Error',
      message: 'Unable to connect to the server. Please check your internet connection and try again.',
      icon: Icons.wifi_off,
    );
  }
  
  // Server Errors
  if (errorString.contains('500') || 
      errorString.contains('internal server error')) {
    return _ErrorInfo(
      title: 'Server Error',
      message: 'The server encountered an error. Please try again in a few moments.',
      icon: Icons.error_outline,
    );
  }
  
  // Permission Errors
  if (errorString.contains('permission') || 
      errorString.contains('unauthorized') ||
      errorString.contains('forbidden')) {
    return _ErrorInfo(
      title: 'Access Denied',
      message: 'You don\'t have permission to perform this action. Please contact support if you believe this is an error.',
      icon: Icons.block,
    );
  }
  
  // Not Found Errors
  if (errorString.contains('not found') || 
      errorString.contains('404')) {
    return _ErrorInfo(
      title: 'Not Found',
      message: 'The requested resource could not be found. It may have been removed or moved.',
      icon: Icons.search_off,
    );
  }
  
  // Validation Errors
  if (errorString.contains('validation') || 
      errorString.contains('invalid') ||
      errorString.contains('required')) {
    return _ErrorInfo(
      title: 'Invalid Input',
      message: 'Please check your input and make sure all required fields are filled correctly.',
      icon: Icons.info_outline,
    );
  }
  
  // Generic Error
  return _ErrorInfo(
    title: 'Error',
    message: _extractErrorMessage(error),
    icon: Icons.error_outline,
  );
}

/// Extracts a clean error message from various error types
String _extractErrorMessage(dynamic error) {
  if (error is AuthException) {
    return error.message;
  }
  
  if (error is Exception) {
    final errorStr = error.toString();
    // Remove common prefixes
    return errorStr
        .replaceAll('Exception: ', '')
        .replaceAll('Error: ', '')
        .replaceAll(RegExp(r'^[A-Za-z]+Exception: '), '')
        .trim();
  }
  
  return error.toString();
}

class _ErrorInfo {
  final String title;
  final String message;
  final IconData icon;

  _ErrorInfo({
    required this.title,
    required this.message,
    required this.icon,
  });
}

