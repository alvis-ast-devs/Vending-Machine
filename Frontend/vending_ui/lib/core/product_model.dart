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

  factory Product.fromJson(
    Map<String, dynamic> json, {
    required String backendUrl,
  }) {
    final rawImageUrl = json['image_url'] as String?;
    final parsedImageUrl = rawImageUrl == null
        ? null
        : Uri.tryParse(rawImageUrl);
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
}
