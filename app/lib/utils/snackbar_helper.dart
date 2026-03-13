import 'package:flutter/material.dart';

/// Shows a SnackBar at the top of the screen instead of the bottom
/// This prevents the snackbar from obscuring important UI buttons
void showTopSnackBar(BuildContext context, String message, {
  Duration duration = const Duration(seconds: 4),
  Color? backgroundColor,
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 150,
        left: 16,
        right: 16,
      ),
      backgroundColor: backgroundColor,
      action: action,
    ),
  );
}

/// Shows an error SnackBar at the top of the screen
void showTopErrorSnackBar(BuildContext context, String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  showTopSnackBar(
    context,
    message,
    duration: duration,
    backgroundColor: Colors.red[700],
  );
}

/// Shows a success SnackBar at the top of the screen
void showTopSuccessSnackBar(BuildContext context, String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  showTopSnackBar(
    context,
    message,
    duration: duration,
    backgroundColor: Colors.green[700],
  );
}
