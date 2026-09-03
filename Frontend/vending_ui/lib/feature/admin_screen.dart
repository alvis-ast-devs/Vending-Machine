import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_config.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/app_utils.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/portrait_page.dart';
import 'package:vending_ui/core/product_model.dart';

/// Admin Dashboard: admin mengetik kode slot lalu menekan ACCEPT untuk
/// mengisi stok slot tersebut hingga penuh. CANCEL kembali ke menu biasa.
class AdminScreen extends StatefulWidget {
  final ApiService apiService;
  final Stream<MachineEvent> keypadEvents;
  final Duration idleDuration;
  final VoidCallback onExit;

  const AdminScreen({
    super.key,
    required this.apiService,
    required this.keypadEvents,
    required this.idleDuration,
    required this.onExit,
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<List<Product>> _productsFuture;
  late final StreamSubscription<MachineEvent> _keypadSubscription;
  Timer? _idleTimer;
  String _keypadBuffer = '';
  String _statusMessage = '';
  bool _statusIsSuccess = true;

  @override
  void initState() {
    super.initState();
    _productsFuture = widget.apiService.fetchAllProducts();
    _keypadSubscription = widget.keypadEvents.listen(_handleKeypadEvent);
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    unawaited(_keypadSubscription.cancel());
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleDuration, () {
      if (mounted) widget.onExit();
    });
  }

  void _reloadProducts() {
    _resetIdleTimer();
    setState(() {
      _productsFuture = widget.apiService.fetchAllProducts();
    });
  }

  void _handleKeypadEvent(MachineEvent event) {
    if (!mounted) return;
    _resetIdleTimer();

    if (event.type == 'KEYPAD_DIGIT') {
      final digit = event.data['digit']?.toString() ?? '';
      if (RegExp(r'^\d$').hasMatch(digit)) {
        setState(() {
          _keypadBuffer = _keypadBuffer.length >= 2
              ? digit
              : '$_keypadBuffer$digit';
        });
      }
      return;
    }

    if (event.type == 'KEYPAD_ACCEPT') {
      if (_keypadBuffer.isNotEmpty) {
        unawaited(_refillSlot(_keypadBuffer));
      }
      return;
    }

    if (event.type == 'KEYPAD_CANCEL') {
      if (_keypadBuffer.isEmpty) {
        widget.onExit();
      } else {
        setState(() => _keypadBuffer = '');
      }
    }
  }

  Future<void> _refillSlot(String slotCode) async {
    setState(() {
      _keypadBuffer = '';
      _statusMessage = '';
    });
    if (slotCode.length != 2) return;

    try {
      final updated = await widget.apiService.restockSlot(slotCode);
      if (!mounted) return;
      setState(() {
        if (updated != null) {
          _statusMessage = 'Slot $slotCode diisi penuh (${updated.stock}) ✓';
          _statusIsSuccess = true;
        } else {
          _statusMessage = 'Slot $slotCode tidak ditemukan';
          _statusIsSuccess = false;
        }
        _productsFuture = widget.apiService.fetchAllProducts();
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Gagal mengisi slot $slotCode';
        _statusIsSuccess = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _resetIdleTimer(),
      child: PortraitPage(
        child: Column(
          children: [
            _AdminHeader(onExit: widget.onExit),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _AdminLoading();
                  }
                  if (snapshot.hasError) {
                    return _AdminError(
                      message: snapshot.error.toString(),
                      onRetry: _reloadProducts,
                    );
                  }
                  return _buildSlotGrid(snapshot.data ?? const <Product>[]);
                },
              ),
            ),
            _AdminPanel(
              inputCode: _keypadBuffer,
              statusMessage: _statusMessage,
              statusIsSuccess: _statusIsSuccess,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotGrid(List<Product> products) {
    final productsBySlot = {
      for (final product in products) product.slotCode: product,
    };
    final allSlots = physicalSlotRows.expand((row) => row).toList();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.88,
      ),
      itemCount: allSlots.length,
      itemBuilder: (context, index) {
        final slotCode = allSlots[index];
        return _StockTile(
          key: ValueKey('admin-slot-$slotCode'),
          slotCode: slotCode,
          product: productsBySlot[slotCode],
          fullStock: AppConfig.defaultFullStock,
        );
      },
    );
  }
}

class _AdminHeader extends StatelessWidget {
  final VoidCallback onExit;

  const _AdminHeader({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.admin_panel_settings_rounded,
              size: 34,
              color: VendingColors.warning,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'ADMIN — ISI STOK',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Kembali ke menu',
              onPressed: onExit,
              icon: Icon(
                Icons.close_rounded,
                size: 34,
                color: VendingColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  final String slotCode;
  final Product? product;
  final int fullStock;

  const _StockTile({
    super.key,
    required this.slotCode,
    required this.product,
    required this.fullStock,
  });

  @override
  Widget build(BuildContext context) {
    final currentProduct = product;
    if (currentProduct == null) {
      return _emptyTile();
    }

    final stock = currentProduct.stock;
    final isActive = currentProduct.isActive;
    final ratio = (stock / fullStock).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isActive ? VendingColors.surface : VendingColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: isActive ? 1 : 0.45,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                slotCode,
                style: TextStyle(
                  color: VendingColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                currentProduct.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VendingColors.muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$stock/$fullStock',
                style: TextStyle(
                  color: stock == 0
                      ? VendingColors.danger
                      : VendingColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: VendingColors.surfaceSoft,
                color: stock == 0
                    ? VendingColors.danger
                    : VendingColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTile() {
    return Container(
      decoration: BoxDecoration(
        color: VendingColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          slotCode,
          style: TextStyle(
            color: VendingColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AdminLoading extends StatelessWidget {
  const _AdminLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(color: VendingColors.accent),
    );
  }
}

class _AdminError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: VendingColors.danger,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: VendingColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('COBA LAGI'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPanel extends StatelessWidget {
  final String inputCode;
  final String statusMessage;
  final bool statusIsSuccess;

  const _AdminPanel({
    required this.inputCode,
    required this.statusMessage,
    required this.statusIsSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final displayedCode = inputCode.padRight(2, '_');
    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      color: VendingColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  'KODE:',
                  style: TextStyle(
                    color: VendingColors.muted,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  displayedCode,
                  key: const ValueKey('admin-keypad-code'),
                  style: TextStyle(
                    color: VendingColors.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      statusMessage,
                      key: const ValueKey('admin-status'),
                      style: TextStyle(
                        color: statusIsSuccess
                            ? VendingColors.warning
                            : VendingColors.danger,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: VendingColors.surfaceSoft),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'ACCEPT: isi stok penuh  ·  CANCEL: kembali',
              style: TextStyle(
                color: VendingColors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}