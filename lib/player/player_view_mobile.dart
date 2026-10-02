import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../config.dart';
import 'player_controller.dart';

/// The player page in a WebView.
class PlayerView extends StatefulWidget {
  const PlayerView({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();

    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const {},
      );
    }

    _web = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'KC',
        onMessageReceived: (m) =>
            widget.controller.handleHostMessage(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // Links inside a player must not replace the player page itself.
          onNavigationRequest: (request) =>
              request.isMainFrame && !request.url.startsWith(webAppUrl)
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
        ),
      );

    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }

    widget.controller.attach((json) {
      _web.runJavaScript('window.kcCommand(${jsonEncode(json)})');
    });

    // A real https origin is required by YouTube and VK embeds.
    rootBundle.loadString('assets/player/player.html').then((html) {
      if (mounted) _web.loadHtmlString(html, baseUrl: webAppUrl);
    });
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
