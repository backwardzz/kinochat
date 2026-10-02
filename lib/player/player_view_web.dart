import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models.dart';
import 'player_controller.dart';

/// The player page in an iframe.
class PlayerView extends StatefulWidget {
  const PlayerView({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  final String _token = newId();
  web.HTMLIFrameElement? _iframe;
  late final JSFunction _listener;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent e) {
      final data = e.data;
      if (!data.isA<JSString>()) return;
      final text = (data as JSString).toDart;
      // Several iframes may be alive during a rebuild; only ours carries the token.
      if (text.contains('"tok":"$_token"')) {
        widget.controller.handleHostMessage(text);
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    widget.controller.attach((json) {
      _iframe?.contentWindow?.postMessage(json.toJS, '*'.toJS);
    });
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        final frame = element as web.HTMLIFrameElement;
        frame.allow =
            'autoplay; fullscreen; encrypted-media; picture-in-picture';
        frame.style
          ..border = '0'
          ..width = '100%'
          ..height = '100%'
          ..backgroundColor = '#000';
        frame.src =
            '${ui_web.assetManager.getAssetUrl('assets/player/player.html')}'
            '#$_token';
        _iframe = frame;
      },
    );
  }
}
