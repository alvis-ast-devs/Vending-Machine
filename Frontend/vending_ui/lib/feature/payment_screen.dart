import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/app_utils.dart';
import 'package:vending_ui/core/portrait_page.dart';

class PaymentScreen extends StatefulWidget {
  final int itemCount;
  final int totalPrice;
  final MachineSocketStatus socketStatus;
  final bool isProcessing;
  final String? errorMessage;
  final bool showMockPaymentAction;
  final Future<void> Function() onMockPaymentSuccess;
  final VoidCallback onExpired;
  final VoidCallback onCancel;

  const PaymentScreen({
    super.key,
    required this.itemCount,
    required this.totalPrice,
    required this.socketStatus,
    required this.isProcessing,
    required this.errorMessage,
    required this.showMockPaymentAction,
    required this.onMockPaymentSuccess,
    required this.onExpired,
    required this.onCancel,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = AppConfig.paymentDuration.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (widget.isProcessing) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _secondsLeft = 0);
          Future.microtask(() {
            if (mounted) {
              widget.onExpired();
            }
          });
        }
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

  String get _formattedTime {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _connectionText {
    if (widget.isProcessing) return 'Memproses dan mengeluarkan pesanan...';
    switch (widget.socketStatus) {
      case MachineSocketStatus.connecting:
        return 'Menghubungkan kanal pembayaran...';
      case MachineSocketStatus.connected:
        return 'Menunggu konfirmasi PAYMENT_SUCCESS';
      case MachineSocketStatus.disconnected:
        return 'Koneksi terputus • mencoba kembali';
    }
  }

  Color get _connectionColor {
    switch (widget.socketStatus) {
      case MachineSocketStatus.connecting:
        return VendingColors.warning;
      case MachineSocketStatus.connected:
        return VendingColors.accent;
      case MachineSocketStatus.disconnected:
        return VendingColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortraitPage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 30, 34, 46),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PEMBAYARAN',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Batalkan pembayaran',
                  onPressed: widget.isProcessing ? null : widget.onCancel,
                  icon: Icon(
                    Icons.close_rounded,
                    color: VendingColors.danger,
                    size: 34,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan QRIS untuk membayar',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 310,
                      height: 310,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.contain,
                        child: Icon(
                          Icons.qr_code_2_rounded,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'QRIS DUMMY',
                      style: TextStyle(
                        color: VendingColors.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: VendingColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_outlined, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            _formattedTime,
                            key: const ValueKey('payment-timer'),
                            style: TextStyle(
                              color: _secondsLeft == 0
                                  ? VendingColors.danger
                                  : VendingColors.warning,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '${widget.itemCount} item  •  ${formatRupiah(widget.totalPrice)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: VendingColors.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VendingColors.danger,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (widget.showMockPaymentAction) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: widget.isProcessing
                      ? null
                      : widget.onMockPaymentSuccess,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    widget.isProcessing
                        ? 'MEMPROSES PESANAN...'
                        : 'SIMULASIKAN PEMBAYARAN BERHASIL',
                  ),
                ),
              ),
            ],
            if (widget.errorMessage != null || widget.showMockPaymentAction)
              const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: VendingColors.surfaceSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  if (widget.socketStatus == MachineSocketStatus.connected)
                    SizedBox(
                      width: 27,
                      height: 27,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: _connectionColor,
                      ),
                    )
                  else
                    Icon(
                      widget.socketStatus == MachineSocketStatus.disconnected
                          ? Icons.cloud_off_rounded
                          : Icons.sync_rounded,
                      color: _connectionColor,
                      size: 29,
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _connectionText,
                        style: TextStyle(
                          color: _connectionColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
