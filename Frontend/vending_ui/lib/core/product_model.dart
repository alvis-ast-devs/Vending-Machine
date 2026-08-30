import 'dart:io';

class Product {
  final int id;
  final String name;
  final int price;
  final String slotCode;
  final int stock;
  final bool isActive;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.slotCode,
    required this.stock,
    required this.isActive,
    required this.imageUrl,
  });

  bool get isAvailable => isActive && stock > 0;

  /// Factory for the old backend JSON format (kept for reference).
  factory Product.fromJson(
    Map<String, dynamic> json, {
    String backendUrl = '',
  }) {
    final rawImageUrl = json['image_url'] as String?;
    final parsedImageUrl =
        rawImageUrl != null ? Uri.tryParse(rawImageUrl) : null;
    final resolvedImageUrl = rawImageUrl == null
        ? null
        : parsedImageUrl?.hasScheme == true
            ? rawImageUrl
            : '$backendUrl${rawImageUrl.startsWith('/') ? '' : '/'}$rawImageUrl';

    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      price: json['price'] as int,
      slotCode: json['slot_code'] as String,
      stock: json['stock'] as int,
      isActive: json['is_active'] as bool,
      imageUrl: resolvedImageUrl,
    );
  }

  /// Factory for the local JSON format (products.json).
  /// [basePath] is the application support directory path.
  factory Product.fromJsonLocal(
    Map<String, dynamic> json, {
    required String basePath,
  }) {
    final slotCode = json['slot_code'] as String;

    // Look for product image in assets/product_images/{slotCode}.*
    String? imageUrl;
    final imagesDir = '$basePath${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}product_images';
    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']) {
      final file = '$imagesDir${Platform.pathSeparator}$slotCode.$ext';
      if (File(file).existsSync()) {
        imageUrl = file;
        break;
      }
    }

    return Product(
      id: json['id'] as int? ?? _slotCodeToId(slotCode),
      name: json['name'] as String,
      price: json['price'] as int,
      slotCode: slotCode,
      stock: json['stock'] as int,
      isActive: json['is_active'] as bool? ?? true,
      imageUrl: imageUrl,
    );
  }

  /// Generate a stable integer ID from a slot code (e.g. "01" → 1, "55" → 55).
  static int _slotCodeToId(String slotCode) => int.parse(slotCode);

  /// Convert to JSON for saving to products.json.
  Map<String, dynamic> toJsonLocal() {
    return {
      'slot_code': slotCode,
      'name': name,
      'price': price,
      'stock': stock,
      'is_active': isActive,
    };
  }

  Product copyWith({
    String? name,
    int? price,
    int? stock,
    bool? isActive,
    String? imageUrl,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      slotCode: slotCode,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
