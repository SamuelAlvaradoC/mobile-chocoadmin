import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../core/constants/app_colors.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo / nombre
            Text(
              'ChocoFreseo',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'ChocAdmin',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 48),
            const SpinKitThreeBounce(
              color: Colors.white,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
