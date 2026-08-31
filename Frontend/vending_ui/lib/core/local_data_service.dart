import 'dart:convert';
import 'dart:io';

import 'package:vending_ui/core/product_model.dart';

/// Manages all local data: products JSON file and media folder scanning.
class LocalDataService {
  static LocalDataService? _instance;
  late Directory _appDir;
  late Directory _assetsDir;
  late File _productsFile;
  bool _initialized = false;

  LocalDataService._();

  static LocalDataService get instance {
    _instance ??= LocalDataService._();
    return _instance!;
  }

  /// Initialize with a custom directory (useful for testing).
  Future<void> init({String? customBasePath}) async {
    if (_initialized) return;

    if (customBasePath != null) {
      _appDir = Directory(customBasePath);
    } else {
      // Use the directory next to the executable for portable deployment.
    _appDir = File(Platform.resolvedExecutable).parent;
    }

    _assetsDir = Directory('${_appDir.path}${Platform.pathSeparator}assets');
    _productsFile = File(
      '${_appDir.path}${Platform.pathSeparator}products.json',
    );

    // Create directories if they don't exist.
    await _assetsDir.create(recursive: true);
    await Directory('${_assetsDir.path}${Platform.pathSeparator}product_images')
        .create(recursive: true);
    await Directory('${_assetsDir.path}${Platform.pathSeparator}ads')
        .create(recursive: true);
    await Directory('${_assetsDir.path}${Platform.pathSeparator}tutorial')
        .create(recursive: true);
    await Directory('${_assetsDir.path}${Platform.pathSeparator}homescreen')
        .create(recursive: true);

    // Seed products if file doesn't exist.
    if (!await _productsFile.exists()) {
      await _seedDefaultProducts();
    }

    _initialized = true;
  }

  String get basePath => _appDir.path;
  String get assetsPath => _assetsDir.path;

  // ─── Products ─────────────────────────────────────────────────────────────

  Future<List<Product>> loadProducts() async {
    try {
      final content = await _productsFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      final products = jsonList
          .map(
            (item) => Product.fromJsonLocal(
              Map<String, dynamic>.from(item as Map),
              basePath: _appDir.path,
            ),
          )
          .toList()
        ..sort((a, b) => a.slotCode.compareTo(b.slotCode));
      return products;
    } catch (_) {
      await _seedDefaultProducts();
      return loadProducts();
    }
  }

  Future<void> saveProducts(List<Product> products) async {
    final jsonList = products
        .map(
          (p) => {
                'slot_code': p.slotCode,
                'name': p.name,
                'price': p.price,
                'stock': p.stock,
                'is_active': p.isActive,
              },
        )
        .toList();
    final encoder = JsonEncoder.withIndent('  ');
    await _productsFile.writeAsString(encoder.convert(jsonList));
  }

  Future<Product?> reduceStock(String slotCode) async {
    final products = await loadProducts();
    for (var i = 0; i < products.length; i++) {
      if (products[i].slotCode == slotCode && products[i].stock > 0) {
        final updated = Product(
          id: products[i].id,
          name: products[i].name,
          price: products[i].price,
          slotCode: products[i].slotCode,
          stock: products[i].stock - 1,
          isActive: products[i].isActive,
          imageUrl: products[i].imageUrl,
        );
        products[i] = updated;
        await saveProducts(products);
        return updated;
      }
    }
    return null;
  }

  Future<Product?> restockProduct(String slotCode, {int quantity = 10}) async {
    final products = await loadProducts();
    for (var i = 0; i < products.length; i++) {
      if (products[i].slotCode == slotCode) {
        final updated = Product(
          id: products[i].id,
          name: products[i].name,
          price: products[i].price,
          slotCode: products[i].slotCode,
          stock: quantity,
          isActive: products[i].isActive,
          imageUrl: products[i].imageUrl,
        );
        products[i] = updated;
        await saveProducts(products);
        return updated;
      }
    }
    return null;
  }

  Future<void> _seedDefaultProducts() async {
    final products = <Product>[];
    int id = 1;

    // Slots 01–40: regular snacks
    for (var i = 1; i <= 40; i++) {
      final slotCode = i.toString().padLeft(2, '0');
      final imageFile = _findProductImage(slotCode);
      products.add(
        Product(
          id: id++,
          name: 'Snack ${i.toString().padLeft(2, '0')}',
          price: 8000 + (i % 4) * 2000,
          slotCode: slotCode,
          stock: 10,
          isActive: true,
          imageUrl: imageFile,
        ),
      );
    }

    // Slots 41–45: larger items
    for (var i = 41; i <= 45; i++) {
      final slotCode = i.toString().padLeft(2, '0');
      final imageFile = _findProductImage(slotCode);
      products.add(
        Product(
          id: id++,
          name: 'Produk Besar ${(i - 40).toString().padLeft(2, '0')}',
          price: 20_000 + ((i - 41) % 5) * 5000,
          slotCode: slotCode,
          stock: 10,
          isActive: true,
          imageUrl: imageFile,
        ),
      );
    }

    // Slots 51–55: premium items
    for (var i = 51; i <= 55; i++) {
      final slotCode = i.toString().padLeft(2, '0');
      final imageFile = _findProductImage(slotCode);
      products.add(
        Product(
          id: id++,
          name: 'Premium ${(i - 50).toString().padLeft(2, '0')}',
          price: 25_000 + ((i - 51) % 5) * 5000,
          slotCode: slotCode,
          stock: 10,
          isActive: true,
          imageUrl: imageFile,
        ),
      );
    }

    await saveProducts(products);
  }

  // ─── Media ────────────────────────────────────────────────────────────────

  /// Scan the ads folder and return all media files.
  List<MediaFile> scanAds() {
    final adsDir = Directory('${_assetsDir.path}${Platform.pathSeparator}ads');
    if (!adsDir.existsSync()) return [];
    final files = adsDir
        .listSync()
        .whereType<File>()
        .where((f) => _isSupportedMedia(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files
        .map((f) => MediaFile(
              file: f,
              name: f.uri.pathSegments.last,
              isVideo: _isSupportedVideo(f.path),
              isImage: _isSupportedImage(f.path),
            ))
        .toList();
  }

  /// Find the tutorial video in the tutorial folder.
  File? findTutorial() {
    final tutorialDir = Directory(
      '${_assetsDir.path}${Platform.pathSeparator}tutorial',
    );
    if (!tutorialDir.existsSync()) return null;
    final files = tutorialDir
        .listSync()
        .whereType<File>()
        .where((f) => _isSupportedVideo(f.path))
        .toList();
    return files.isNotEmpty ? files.first : null;
  }

  /// Find the homescreen media in the homescreen folder.
  File? findHomescreen() {
    final homescreenDir = Directory(
      '${_assetsDir.path}${Platform.pathSeparator}homescreen',
    );
    if (!homescreenDir.existsSync()) return null;
    final files = homescreenDir
        .listSync()
        .whereType<File>()
        .where((f) => _isSupportedMedia(f.path))
        .toList();
    return files.isNotEmpty ? files.first : null;
  }

  /// Find a product image by slot code.
  String? findProductImage(String slotCode) {
    return _findProductImage(slotCode);
  }

  String? _findProductImage(String slotCode) {
    final imagesDir = Directory(
      '${_assetsDir.path}${Platform.pathSeparator}product_images',
    );
    if (!imagesDir.existsSync()) return null;

    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']) {
      final file = File(
        '${imagesDir.path}${Platform.pathSeparator}$slotCode.$ext',
      );
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  static const _imageExtensions = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp',
  };
  static const _videoExtensions = {
    '.mp4', '.webm', '.mov', '.mkv',
  };

  bool _isSupportedMedia(String path) {
    final ext = _extension(path);
    return _imageExtensions.contains(ext) || _videoExtensions.contains(ext);
  }

  bool _isSupportedVideo(String path) {
    return _videoExtensions.contains(_extension(path));
  }

  bool _isSupportedImage(String path) {
    return _imageExtensions.contains(_extension(path));
  }

  String _extension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }
}

/// Represents a media file found in the assets folder.
class MediaFile {
  final File file;
  final String name;
  final bool isVideo;
  final bool isImage;

  const MediaFile({
    required this.file,
    required this.name,
    required this.isVideo,
    required this.isImage,
  });

  String get path => file.path;
  String get uri => file.uri.toString();
}
