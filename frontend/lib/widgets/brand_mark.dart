import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 56,
    this.radius,
  });

  static const String assetPath = 'assets/branding/app_logo.png';

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final cornerRadius = radius ?? size * 0.28;

    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
