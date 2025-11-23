import 'package:flutter/material.dart';

class PadalaBookingPage extends StatelessWidget {
  static const String routeName = '/padala';
  const PadalaBookingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Padala Booking')),
      body: const Center(child: Text('Pickup/Drop-off booking flow')),
    );
  }
}


