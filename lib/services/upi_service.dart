import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches a UPI payment intent with the given parameters.
///
/// [context] — BuildContext for showing error snackbar
/// [upiId]  — receiver's UPI ID (e.g., "yourname@oksbi")
/// [name]   — receiver's display name
/// [amount] — amount to pay in INR
Future<void> launchUPI({
  required BuildContext context,
  required String upiId,
  required String name,
  required double amount,
}) async {
  final uri = Uri.parse(
    "upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR&tn=${Uri.encodeComponent("Spendy Settlement")}",
  );

  print("🚀 Launching UPI: $uri");

  try {
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    print("❌ Launch failed: $e");

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No UPI app found. Please install Google Pay or PhonePe.",
          ),
        ),
      );
    }
  }
}
