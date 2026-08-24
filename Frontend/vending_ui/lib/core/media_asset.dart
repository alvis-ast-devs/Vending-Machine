enum MediaAssetType { image, video }

class MediaAsset {
  final int id;
  final String kind;
  final MediaAssetType type;
  final String originalName;
  final String mimeType;
  final String url;

  const MediaAsset({
    required this.id,
    required this.kind,
    required this.type,
    required this.originalName,
    required this.mimeType,
    required this.url,
  });

  factory MediaAsset.fromJson(
    Map<String, dynamic> json, {
    required String backendUrl,
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

  factory MediaCatalog.fromJson(
    Map<String, dynamic> json, {
    required String backendUrl,
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
