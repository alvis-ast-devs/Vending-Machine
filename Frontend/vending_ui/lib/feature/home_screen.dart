import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/media_asset.dart';
import 'package:vending_ui/core/portrait_page.dart';
import 'package:vending_ui/feature/network_video.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final MediaAsset? media;

  const HomeScreen({super.key, required this.onContinue, this.media});

  @override
  Widget build(BuildContext context) {
    final customMedia = media;
    if (customMedia != null) {
      return _CustomHomeScreen(media: customMedia, onContinue: onContinue);
    }

    return _DefaultHomeScreen(onContinue: onContinue);
  }
}

class _DefaultHomeScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const _DefaultHomeScreen({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return PortraitPage(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [VendingColors.surface, VendingColors.background],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(46, 90, 46, 70),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SMART VENDING',
                  style: TextStyle(
                    color: VendingColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 150,
                        color: VendingColors.accent,
                      ),
                      const SizedBox(height: 42),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Selamat Datang',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 390),
                        child: Text(
                          'Pilih camilan dan kebutuhan favoritmu dengan cepat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: VendingColors.muted,
                            fontSize: 22,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 76,
                child: ElevatedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.shopping_bag_rounded, size: 28),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Lanjut Belanja',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomHomeScreen extends StatefulWidget {
  final MediaAsset media;
  final VoidCallback onContinue;

  const _CustomHomeScreen({required this.media, required this.onContinue});

  @override
  State<_CustomHomeScreen> createState() => _CustomHomeScreenState();
}

class _CustomHomeScreenState extends State<_CustomHomeScreen> {
  bool _videoFailed = false;

  @override
  void didUpdateWidget(covariant _CustomHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id) {
      _videoFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_videoFailed) {
      return _DefaultHomeScreen(onContinue: widget.onContinue);
    }

    return PortraitPage(
      backgroundColor: Colors.black,
      child: Semantics(
        button: true,
        label: 'Sentuh layar untuk mulai belanja',
        child: GestureDetector(
          key: const ValueKey('homescreen-touch-target'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onContinue,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.media.type == MediaAssetType.image)
                Image.network(
                  widget.media.url,
                  key: ValueKey('homescreen-image-${widget.media.id}'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _HomeMediaError(),
                )
              else
                NetworkVideo(
                  key: ValueKey('homescreen-video-${widget.media.id}'),
                  url: widget.media.url,
                  loop: true,
                  onFinished: () {
                    if (mounted) setState(() => _videoFailed = true);
                  },
                ),
              Positioned(
                left: 34,
                right: 34,
                bottom: 34,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        color: VendingColors.accent,
                        size: 23,
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'SENTUH LAYAR UNTUK MULAI',
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
        ),
      ),
    );
  }
}

class _HomeMediaError extends StatelessWidget {
  const _HomeMediaError();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VendingColors.background,
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
