import 'package:vending_ui/core/local_data_service.dart';
import 'dart:io';
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
  final bool isListening;
  final int paidAmount;
  final int remainingAmount;
  final String? voiceMessage;
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
    required this.isListening,
    required this.paidAmount,
    required this.remainingAmount,
    required this.voiceMessage,
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
    if (widget.isListening) {
      return 'Menunggu Pembayaran';
    }
    switch (widget.socketStatus) {
      case MachineSocketStatus.connecting:
        return 'Menghubungkan kanal pembayaran...';
      case MachineSocketStatus.connected:
        return 'Menunggu Pembayaran';
      case MachineSocketStatus.disconnected:
        return 'Koneksi terputus • mencoba kembali';
    }
  }

  Color get _connectionColor {
    if (widget.isListening) return VendingColors.accent;
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
                      'QRIS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildQrCodeImage(),
                    const SizedBox(height: 12),
                    Text(
                      'Scan QRIS untuk melakukan pembayaran',
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
                    if (widget.isListening || widget.voiceMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.voiceMessage ??
                            'Mikrofon sedang mendengarkan...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: VendingColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bayar: ${formatRupiah(widget.paidAmount)}'
                        ' • Sisa: ${formatRupiah(widget.remainingAmount)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.remainingAmount > 0
                              ? VendingColors.warning
                              : VendingColors.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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

  /// Build QR code image from assets folder, with fallback icon if not found.
  Widget _buildQrCodeImage() {
    final qrFile = File(
      '${LocalDataService.instance.assetsPath}${Platform.pathSeparator}qris.png',
    );
    return Container(
      width: 310,
      height: 310,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: qrFile.existsSync()
          ? Image.file(qrFile, fit: BoxFit.contain)
          : const Icon(
              Icons.qr_code_rounded,
              color: Colors.black,
              size: 176,
            ),
    );
  }
}
