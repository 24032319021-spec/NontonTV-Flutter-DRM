import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/branding/brand_assets.dart';
import 'core/platform/tv_display.dart';
import 'features/channels/presentation/home_screen.dart';

class NontonTvApp extends StatelessWidget {
  const NontonTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: BrandAssets.name,
      theme: AppTheme.dark,
      home: const HomeScreen(),
      builder: (context, child) => TvDisplayScope(child: child ?? const SizedBox.shrink()),
    );
  }
}
