import 'dart:io';

enum MediaAssetType { image, video }

class MediaAsset {
  final int id;
  final String kind;
  final MediaAssetType type;
  final String originalName;
  final String mimeType;
  final String url;
  final String? localPath;

  const MediaAsset({
    required this.id,
    required this.kind,
    required this.type,
    required this.originalName,
    required this.mimeType,
    required this.url,
    this.localPath,
  });

  bool get isVideo => type == MediaAssetType.video;
  bool get isImage => type == MediaAssetType.image;

  /// Create from a local file path.
  factory MediaAsset.fromFile({
    required int id,
    required String kind,
    required File file,
  }) {
    final name = file.uri.pathSegments.last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isVideo = {'mp4', 'webm', 'mov', 'mkv'}.contains(ext);
    final mimeType = _guessMimeType(ext, isVideo);

    return MediaAsset(
      id: id,
      kind: kind,
      type: isVideo ? MediaAssetType.video : MediaAssetType.image,
      originalName: name,
      mimeType: mimeType,
      url: file.uri.toString(),
      localPath: file.path,
    );
  }

  /// Factory for the old backend JSON format (kept for reference).
  factory MediaAsset.fromJson(
    Map<String, dynamic> json, {
    String backendUrl = '',
  }) {
    final rawUrl = json['url'] as String? ?? '';
    final parsedUrl = Uri.tryParse(rawUrl);
    final resolvedUrl = parsedUrl?.hasScheme == true
        ? rawUrl
        : '$backendUrl${rawUrl.startsWith('/') ? '' : '/'}$rawUrl';

    return MediaAsset(
      id: json['id'] as int,
      kind: json['kind'] as String,
      type: json['media_type'] == 'image'
          ? MediaAssetType.image
          : MediaAssetType.video,
      originalName: json['original_name'] as String? ?? 'Media',
      mimeType: json['mime_type'] as String? ?? '',
      url: resolvedUrl,
    );
  }

  static String _guessMimeType(String ext, bool isVideo) {
    if (isVideo) {
      return {
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
        'mkv': 'video/x-matroska',
      }[ext] ?? 'video/mp4';
    }
    return {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
    }[ext] ?? 'image/png';
  }
}

class MediaCatalog {
  final List<MediaAsset> ads;
  final MediaAsset? tutorial;
  final MediaAsset? homescreen;

  const MediaCatalog({
    required this.ads,
    required this.tutorial,
    required this.homescreen,
  });

  static const empty = MediaCatalog(ads: [], tutorial: null, homescreen: null);

  /// Factory for the old backend JSON format (kept for reference).
  factory MediaCatalog.fromJson(
    Map<String, dynamic> json, {
    String backendUrl = '',
  }) {
    final rawAds = json['ads'];
    final rawTutorial = json['tutorial'];
    final rawHomescreen = json['homescreen'];
    return MediaCatalog(
      ads: rawAds is List
          ? rawAds
              .map(
                (item) => MediaAsset.fromJson(
                  Map<String, dynamic>.from(item as Map),
                  backendUrl: backendUrl,
                ),
              )
              .toList()
          : const [],
      tutorial: rawTutorial is Map
          ? MediaAsset.fromJson(
              Map<String, dynamic>.from(rawTutorial),
              backendUrl: backendUrl,
            )
          : null,
      homescreen: rawHomescreen is Map
          ? MediaAsset.fromJson(
              Map<String, dynamic>.from(rawHomescreen),
              backendUrl: backendUrl,
            )
          : null,
    );
  }
}
