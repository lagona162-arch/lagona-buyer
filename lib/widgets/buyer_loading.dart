import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BuyerLoadingOverlay extends StatelessWidget {
  final bool show;
  final String message;
  const BuyerLoadingOverlay({super.key, required this.show, this.message = 'Preparing your order...'});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: false,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black.withOpacity(0.35),
          alignment: Alignment.center,
          child: _BuyerLoadingCard(message: message),
        ),
      ),
    );
  }
}

class _BuyerLoadingCard extends StatefulWidget {
  final String message;
  const _BuyerLoadingCard({required this.message});
  @override
  State<_BuyerLoadingCard> createState() => _BuyerLoadingCardState();
}

class _BuyerLoadingCardState extends State<_BuyerLoadingCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final double t = _controller.value;
              // Cart wheels rotate; cart bounces slightly
              final double bounce = math.sin(t * math.pi * 2) * 4;
              return Transform.translate(
                offset: Offset(0, bounce),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  size: 64,
                  color: AppColors.primary,
                  fill: 0.0,
                  opticalSize: 24,
                  grade: 0,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            widget.message,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.3,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: AppColors.border.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}



