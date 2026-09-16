import 'package:flutter/material.dart';

class GoldBlobsBackground extends StatelessWidget {
  final Widget child;
  final bool useSafeArea;

  const GoldBlobsBackground({
    super.key,
    required this.child,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    const Color lightGold = Color(0xFFFBDB83);

    return Stack(
      children: [
        // Background Blobs
        Positioned(
          top: -50,
          left: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: lightGold.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          top: 250,
          right: -80,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              color: lightGold.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: 150,
          left: 50,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: lightGold.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: -50,
          right: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: lightGold.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
          ),
        ),
        
        // Main Content
        useSafeArea ? SafeArea(child: child) : child,
      ],
    );
  }
}
