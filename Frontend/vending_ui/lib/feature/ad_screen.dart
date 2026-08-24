import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/core/portrait_page.dart';
import 'package:vending_ui/feature/network_video.dart';

class AdScreen extends StatefulWidget {
  final List<MediaAsset> ads;
  final MachineSocketStatus socketStatus;

  const AdScreen({super.key, required this.ads, required this.socketStatus});

  @override
  State<AdScreen> createState() => _AdScreenState();
}

class _AdScreenState extends State<AdScreen> {
  Timer? _imageTimer;
  int _currentIndex = 0;
  int _playbackCycle = 0;

  MediaAsset get _currentAd => widget.ads[_currentIndex % widget.ads.length];

  @override
  void initState() {
    super.initState();
    _scheduleCurrentMedia();
  }

  @override
  void didUpdateWidget(covariant AdScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ads != widget.ads) {
      _currentIndex = 0;
      _scheduleCurrentMedia();
    }
  }

  void _scheduleCurrentMedia() {
    _imageTimer?.cancel();
    if (widget.ads.isEmpty || _currentAd.type != MediaAssetType.image) return;
    _imageTimer = Timer(AppConfig.adImageDuration, _showNext);
  }

  void _showNext() {
    if (!mounted || widget.ads.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.ads.length;
      _playbackCycle += 1;
    });
    _scheduleCurrentMedia();
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentAd = _currentAd;
    return PortraitPage(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: currentAd.type == MediaAssetType.image
                ? Image.network(
                    currentAd.url,
                    key: ValueKey('ad-image-${currentAd.id}'),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _MediaError(),
                  )
                : NetworkVideo(
                    key: ValueKey('ad-video-${currentAd.id}-$_playbackCycle'),
                    url: currentAd.url,
                    onFinished: _showNext,
                  ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.socketStatus == MachineSocketStatus.connected
                        ? Icons.sensors_rounded
                        : Icons.sync_rounded,
                    color: VendingColors.accent,
                    size: 22,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'DEKATI MESIN UNTUK MULAI',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: VendingColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 80,
          color: VendingColors.muted,
        ),
      ),
    );
  }
}
