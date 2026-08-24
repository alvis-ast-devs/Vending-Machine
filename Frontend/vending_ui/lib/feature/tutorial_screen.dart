import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/core/portrait_page.dart';
import 'package:vending_ui/feature/network_video.dart';

class TutorialScreen extends StatelessWidget {
  final MediaAsset tutorial;
  final VoidCallback onFinished;

  const TutorialScreen({
    super.key,
    required this.tutorial,
    required this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    return PortraitPage(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkVideo(
            key: ValueKey('tutorial-${tutorial.id}'),
            url: tutorial.url,
            onFinished: onFinished,
          ),
          Positioned(
            top: 34,
            left: 28,
            right: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'CARA MENGGUNAKAN MESIN',
                    style: TextStyle(
                      color: VendingColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onFinished,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.62),
                    foregroundColor: VendingColors.white,
                  ),
                  child: const Text('Lewati'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
