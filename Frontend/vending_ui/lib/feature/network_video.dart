import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vending_ui/core/app_theme.dart';

class NetworkVideo extends StatefulWidget {
  final String url;
  final VoidCallback onFinished;
  final bool loop;

  const NetworkVideo({
    super.key,
    required this.url,
    required this.onFinished,
    this.loop = false,
  });

  @override
  State<NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<NetworkVideo> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    if (!widget.loop) {
      _completedSubscription = _player.stream.completed.listen((completed) {
        if (completed) _finish();
      });
    }
    _errorSubscription = _player.stream.error.listen((_) => _finish());
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      if (widget.loop) {
        await _player.setPlaylistMode(PlaylistMode.loop);
      }
      await _player.open(Media(widget.url), play: true);
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    _errorSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Video(
        controller: _controller,
        controls: NoVideoControls,
        fit: BoxFit.cover,
        fill: VendingColors.background,
      ),
    );
  }
}
