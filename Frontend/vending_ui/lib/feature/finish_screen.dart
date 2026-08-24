import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/portrait_page.dart';

class FinishScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const FinishScreen({super.key, required this.onFinished});

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

class _FinishScreenState extends State<FinishScreen> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = AppConfig.finishDuration.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        widget.onFinished();
        return;
      }

      if (mounted) {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortraitPage(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 80),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        color: VendingColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.all(35),
                          child: Icon(
                            Icons.check_rounded,
                            size: 140,
                            color: VendingColors.background,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Terima Kasih!',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pembayaran berhasil.\nSilakan ambil produk Anda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: VendingColors.muted,
                        fontSize: 23,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'Kembali ke beranda dalam $_secondsLeft detik',
              key: const ValueKey('finish-timer'),
              textAlign: TextAlign.center,
              style: TextStyle(color: VendingColors.muted, fontSize: 17),
            ),
          ],
        ),
      ),
    );
  }
}
