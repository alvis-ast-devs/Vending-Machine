import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vending_ui/core/api_service.dart';
import 'package:vending_ui/core/app_theme.dart';
import 'package:vending_ui/core/app_utils.dart';
import 'package:vending_ui/core/event_bus.dart';
import 'package:vending_ui/core/portrait_page.dart';
import 'package:vending_ui/core/product_model.dart';

typedef CheckoutCallback =
    void Function(List<String> slotCodes, int itemCount, int totalPrice);

class MenuScreen extends StatefulWidget {
  final ApiService apiService;
  final Stream<MachineEvent> keypadEvents;
  final Duration idleDuration;
  final CheckoutCallback onCheckout;
  final VoidCallback onCancel;

  const MenuScreen({
    super.key,
    required this.apiService,
    required this.keypadEvents,
    required this.idleDuration,
    required this.onCheckout,
    required this.onCancel,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  static const List<IconData> _snackIcons = [
    Icons.cookie_rounded,
    Icons.breakfast_dining_rounded,
    Icons.fastfood_rounded,
    Icons.bakery_dining_rounded,
  ];

  static const List<IconData> _largeItemIcons = [
    Icons.local_drink_rounded,
    Icons.lunch_dining_rounded,
    Icons.inventory_2_rounded,
    Icons.shopping_basket_rounded,
    Icons.local_mall_rounded,
  ];

  late Future<List<Product>> _productsFuture;
  late final StreamSubscription<MachineEvent> _keypadSubscription;
  Timer? _idleTimer;
  final Map<String, int> _selectedPerSlot = {};
  String _keypadBuffer = '';
  int _itemCount = 0;
  int _totalPrice = 0;

  @override
  void initState() {
    super.initState();
    _productsFuture = widget.apiService.fetchProducts();
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
      if (mounted) widget.onCancel();
    });
  }

  void _reloadProducts() {
    _resetIdleTimer();
    setState(() {
      _selectedPerSlot.clear();
      _keypadBuffer = '';
      _itemCount = 0;
      _totalPrice = 0;
      _productsFuture = widget.apiService.fetchProducts();
    });
  }

  void _addToCart(Product product) {
    final selected = _selectedPerSlot[product.slotCode] ?? 0;
    if (!product.isAvailable || selected >= product.stock) {
      return;
    }

    setState(() {
      _selectedPerSlot[product.slotCode] = selected + 1;
      _itemCount++;
      _totalPrice += product.price;
    });
  }

  void _removeFromCart(Product product) {
    final selected = _selectedPerSlot[product.slotCode] ?? 0;
    if (selected <= 0) return;

    setState(() {
      if (selected == 1) {
        _selectedPerSlot.remove(product.slotCode);
      } else {
        _selectedPerSlot[product.slotCode] = selected - 1;
      }
      _itemCount--;
      _totalPrice -= product.price;
    });
  }

  void _checkout() {
    final slotCodes = [
      for (final entry in _selectedPerSlot.entries)
        for (var index = 0; index < entry.value; index++) entry.key,
    ];
    widget.onCheckout(slotCodes, _itemCount, _totalPrice);
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
      if (_keypadBuffer.isEmpty) {
        if (_itemCount > 0) _checkout();
        return;
      }
      unawaited(_applyKeypadCode(addProduct: true));
      return;
    }

    if (event.type == 'KEYPAD_CANCEL') {
      if (_keypadBuffer.isEmpty) {
        widget.onCancel();
      } else {
        unawaited(_applyKeypadCode(addProduct: false));
      }
    }
  }

  Future<void> _applyKeypadCode({required bool addProduct}) async {
    final slotCode = _keypadBuffer;
    setState(() => _keypadBuffer = '');
    if (slotCode.length != 2) return;

    try {
      final products = await _productsFuture;
      if (!mounted) return;
      Product? product;
      for (final item in products) {
        if (item.slotCode == slotCode) {
          product = item;
          break;
        }
      }
      if (product == null) return;
      if (addProduct) {
        _addToCart(product);
      } else {
        _removeFromCart(product);
      }
    } on Object {
      // FutureBuilder tetap menampilkan kegagalan pengambilan katalog.
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
            _MenuHeader(onCancel: widget.onCancel, onRefresh: _reloadProducts),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _CatalogLoading();
                  }
                  if (snapshot.hasError) {
                    return _CatalogError(
                      message: snapshot.error.toString(),
                      onRetry: _reloadProducts,
                    );
                  }

                  final productsBySlot = {
                    for (final product in snapshot.data ?? const <Product>[])
                      product.slotCode: product,
                  };
                  return _buildCatalog(productsBySlot);
                },
              ),
            ),
            _CartPanel(inputCode: _keypadBuffer, totalPrice: _totalPrice),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalog(Map<String, Product> productsBySlot) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        children: List.generate(physicalSlotRows.length, (rowIndex) {
          final slotCodes = physicalSlotRows[rowIndex];
          return Expanded(
            child: Row(
              children: slotCodes.map((slotCode) {
                final product = productsBySlot[slotCode];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: _ProductTile(
                      key: ValueKey('slot-$slotCode'),
                      slotCode: slotCode,
                      product: product,
                      isLargeRow: rowIndex >= 4,
                      icon: _iconForSlot(slotCode, rowIndex >= 4),
                      selectedQuantity: _selectedPerSlot[slotCode] ?? 0,
                      onTap: product == null ? null : () => _addToCart(product),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ),
    );
  }

  IconData _iconForSlot(String slotCode, bool isLargeRow) {
    final index = int.parse(slotCode);
    final icons = isLargeRow ? _largeItemIcons : _snackIcons;
    return icons[index % icons.length];
  }
}

class _MenuHeader extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onRefresh;

  const _MenuHeader({required this.onCancel, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'PILIH PRODUK',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Muat ulang produk',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 31),
            ),
            IconButton(
              tooltip: 'Batalkan belanja',
              onPressed: onCancel,
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

class _ProductTile extends StatelessWidget {
  final String slotCode;
  final Product? product;
  final bool isLargeRow;
  final IconData icon;
  final int selectedQuantity;
  final VoidCallback? onTap;

  const _ProductTile({
    super.key,
    required this.slotCode,
    required this.product,
    required this.isLargeRow,
    required this.icon,
    required this.selectedQuantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentProduct = product;
    if (currentProduct == null) {
      return _EmptySlotTile(slotCode: slotCode);
    }

    final isAvailable = currentProduct.isAvailable;
    return Semantics(
      button: isAvailable,
      label:
          'Tambah ${currentProduct.name}, slot $slotCode, '
          'dipilih $selectedQuantity',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: isLargeRow ? 48 : 34,
                    height: isLargeRow ? 48 : 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: _ProductVisual(
                            icon: icon,
                            imageUrl: currentProduct.imageUrl,
                            isAvailable: isAvailable,
                            isLargeRow: isLargeRow,
                          ),
                        ),
                        if (selectedQuantity > 0)
                          Positioned(
                            top: -5,
                            right: -7,
                            child: _QuantityBadge(
                              slotCode: slotCode,
                              quantity: selectedQuantity,
                              isLarge: isLargeRow,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      currentProduct.name,
                      maxLines: 1,
                      style: TextStyle(
                        color: isAvailable
                            ? VendingColors.white
                            : VendingColors.muted,
                        fontSize: isLargeRow ? 14 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatRupiah(currentProduct.price),
                      maxLines: 1,
                      style: TextStyle(
                        color: isAvailable
                            ? VendingColors.muted
                            : VendingColors.danger,
                        fontSize: isLargeRow ? 12 : 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      slotCode,
                      maxLines: 1,
                      style: TextStyle(
                        color: VendingColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityBadge extends StatelessWidget {
  final String slotCode;
  final int quantity;
  final bool isLarge;

  const _QuantityBadge({
    required this.slotCode,
    required this.quantity,
    required this.isLarge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('cart-quantity-$slotCode'),
      constraints: BoxConstraints(
        minWidth: isLarge ? 24 : 20,
        minHeight: isLarge ? 24 : 20,
      ),
      padding: EdgeInsets.symmetric(horizontal: isLarge ? 5 : 4),
      decoration: BoxDecoration(
        color: VendingColors.warning,
        border: Border.all(color: VendingColors.background, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        '×$quantity',
        style: TextStyle(
          color: VendingColors.background,
          fontSize: isLarge ? 11 : 9,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _ProductVisual extends StatelessWidget {
  final IconData icon;
  final String? imageUrl;
  final bool isAvailable;
  final bool isLargeRow;

  const _ProductVisual({
    required this.icon,
    required this.imageUrl,
    required this.isAvailable,
    required this.isLargeRow,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = FittedBox(
      fit: BoxFit.contain,
      child: Icon(
        icon,
        color: !isAvailable
            ? VendingColors.muted
            : isLargeRow
                ? VendingColors.warning
                : VendingColors.white,
      ),
    );
    final source = imageUrl;
    if (source == null || source.isEmpty) return fallback;

    // Check if this is a local file path.
    final file = File(source);
    if (file.existsSync()) {
      return Opacity(
        opacity: isAvailable ? 1 : 0.42,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      );
    }

    return Opacity(
      opacity: isAvailable ? 1 : 0.42,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          source,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}

class _EmptySlotTile extends StatelessWidget {
  final String slotCode;

  const _EmptySlotTile({required this.slotCode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.remove_shopping_cart_outlined,
            size: 25,
            color: VendingColors.surfaceSoft,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              slotCode,
              style: TextStyle(
                color: VendingColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Tidak aktif',
              style: TextStyle(color: VendingColors.muted, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: VendingColors.accent),
          ),
          SizedBox(height: 18),
          Text('Memuat produk...'),
        ],
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CatalogError({required this.message, required this.onRetry});

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
              size: 70,
              color: VendingColors.danger,
            ),
            const SizedBox(height: 18),
            const Text(
              'Produk gagal dimuat',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: VendingColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 20),
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

class _CartPanel extends StatelessWidget {
  final String inputCode;
  final int totalPrice;

  const _CartPanel({required this.inputCode, required this.totalPrice});

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
                  key: const ValueKey('keypad-code'),
                  style: TextStyle(
                    color: VendingColors.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const Spacer(),
                Text(
                  'TOTAL',
                  style: TextStyle(
                    color: VendingColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatRupiah(totalPrice),
                      key: const ValueKey('cart-total'),
                      style: TextStyle(
                        color: VendingColors.accent,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
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
              'ACCEPT: tambah/bayar  ·  DECLINED: kurangi',
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
