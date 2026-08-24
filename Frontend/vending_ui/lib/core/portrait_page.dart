import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';

/// Menjaga halaman pada kanvas potret 9:16 dan menskalakannya tanpa overflow.
class PortraitPage extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  const PortraitPage({super.key, required this.child, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: AppConfig.designSize.width,
              height: AppConfig.designSize.height,
              child: ColoredBox(
                color: backgroundColor ?? VendingColors.background,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
