import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vending_ui/core/app_theme.dart';

class NetworkVideo extends StatefulWidget {
  final String url;
  final String? localPath;
  final VoidCallback onFinished;
  final bool loop;

  const NetworkVideo({
    super.key,
    required this.url,
    this.localPath,
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

  @override
  void didUpdateWidget(covariant NetworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.localPath != widget.localPath) {
      _finished = false;
      unawaited(_open());
    }
  }

  Future<void> _open() async {
    try {
      if (widget.loop) {
        await _player.setPlaylistMode(PlaylistMode.loop);
      }

      // Prefer local path if available.
      final localPath = widget.localPath;
      if (localPath != null && File(localPath).existsSync()) {
        await _player.open(Media.file(File(localPath)), play: true);
      } else {
        await _player.open(Media(widget.url), play: true);
      }
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
