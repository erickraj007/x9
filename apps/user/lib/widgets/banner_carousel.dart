import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:x9_core/x9_core.dart';

import '../screens/merchant/ad_popup.dart';
import '../util/helpers.dart';
import 'bits.dart';

/// Banner / video file through the app's own signed-in connection (same address and Bearer token as every API call).
/// The signed `media_url` is only the second choice: it breaks when the server's public address is set wrong.
String adMediaApiUrl(int id) => '${ServerSettings.effectiveApiBase.replaceAll(RegExp(r'/+$'), '')}/app/ads/$id/media';
Map<String, String> adMediaHeaders() {
  final t = SessionStore.instance.token;
  return {if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t'};
}

/// Banner picture: tries the signed-in route first, then the signed link, then a plain gradient.
class _BannerImage extends StatefulWidget {
  const _BannerImage({required this.id, required this.signedUrl});
  final int id;
  final String signedUrl;

  @override
  State<_BannerImage> createState() => _BannerImageState();
}

class _BannerImageState extends State<_BannerImage> {
  int _try = 0;

  @override
  Widget build(BuildContext context) {
    const ph = DecoratedBox(decoration: BoxDecoration(gradient: X9Colors.heroGradient));
    final urls = <String>[if (widget.id > 0) adMediaApiUrl(widget.id), if (widget.signedUrl.isNotEmpty) widget.signedUrl];
    if (_try >= urls.length) return ph;
    final authed = widget.id > 0 && _try == 0;
    return Image.network(
      urls[_try],
      key: ValueKey('${widget.id}-$_try'),
      headers: authed ? adMediaHeaders() : null,
      fit: BoxFit.cover,
      loadingBuilder: (c, child, p) => p == null ? child : ph,
      errorBuilder: (_, e, __) {
        StartupLog.add('Banner image ${widget.id} try $_try failed: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _try++);
        });
        return ph;
      },
    );
  }
}

/// v6.13: an ad's picture (same signed-in route as the banner carousel) for other widgets.
class AdPicture extends StatelessWidget {
  const AdPicture({super.key, required this.id, this.signedUrl = ''});
  final int id;
  final String signedUrl;

  @override
  Widget build(BuildContext context) => _BannerImage(id: id, signedUrl: signedUrl);
}

/// Push banners / videos from the central portal (feed `banner.items`).
/// Images advance after `duration_seconds`; videos play muted and advance when they end.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key, required this.items, required this.height});
  final List<dynamic> items;
  final double height;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final PageController _pc = PageController(viewportFraction: 0.92);
  int _index = 0;
  Timer? _advance;
  Timer? _viewTimer;
  VideoPlayerController? _video;
  int _videoFor = -1;
  bool _active = true;
  final Set<int> _viewed = <int>{};
  final Set<int> _failed = <int>{}; // video slides that could not be played (shown as a tap-to-watch card)
  final Map<int, int> _tries = <int, int>{};

  List<Map<String, dynamic>> get _items => widget.items.map(asMap).toList();

  @override
  void initState() {
    super.initState();
    if (widget.items.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _show(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pause when another page covers the home screen.
    final active = TickerMode.of(context);
    if (active == _active) return;
    _active = active;
    if (!active) {
      _advance?.cancel();
      _viewTimer?.cancel();
      _video?.pause();
    } else if (widget.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(_index, keepVideo: true));
    }
  }

  @override
  void didUpdateWidget(covariant BannerCarousel old) {
    super.didUpdateWidget(old);
    final a = old.items.map((e) => asMap(e)['id']).join(',');
    final b = widget.items.map((e) => asMap(e)['id']).join(',');
    if (a != b) {
      _index = 0;
      _disposeVideo();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pc.hasClients) _pc.jumpToPage(0);
        if (widget.items.isNotEmpty) _show(0);
      });
    }
  }

  @override
  void dispose() {
    _advance?.cancel();
    _viewTimer?.cancel();
    _disposeVideo();
    _pc.dispose();
    super.dispose();
  }

  void _disposeVideo() {
    final v = _video;
    _video = null;
    _videoFor = -1;
    if (v != null) {
      v.removeListener(_onVideoTick);
      v.pause();
      // Dispose after the VideoPlayer widget that still shows it has been rebuilt away.
      Timer(const Duration(milliseconds: 600), v.dispose);
    }
  }

  void _show(int i, {bool keepVideo = false}) {
    if (!mounted || i >= _items.length) return;
    _advance?.cancel();
    _viewTimer?.cancel();
    final item = _items[i];
    final id = asInt(item['id']);
    if (_active) {
      _viewTimer = Timer(const Duration(seconds: 1), () {
        if (_viewed.add(id)) fireAdEvent(id, 'VIEW');
      });
    }
    final isVideo = str(item['type']).toUpperCase() == 'VIDEO';
    if (isVideo) {
      if (keepVideo && _videoFor == i && _video != null) {
        if (_active) _video!.play();
        return;
      }
      _disposeVideo();
      // try 0: the signed-in route (Bearer token); try 1: the signed link
      final useApi = (_tries[i] ?? 0) == 0 && id > 0;
      final url = useApi ? adMediaApiUrl(id) : str(item['media_url']);
      final videoUri = url.isEmpty ? null : Uri.tryParse(url);
      if (videoUri == null) {
        _advance = Timer(const Duration(seconds: 6), _next);
        return;
      }
      _failed.remove(i);
      // mixWithOthers: a muted banner must not take audio focus from music / calls (Android pauses it otherwise).
      final c = VideoPlayerController.networkUrl(videoUri, httpHeaders: useApi ? adMediaHeaders() : const <String, String>{}, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      _video = c;
      _videoFor = i;
      c.initialize().timeout(const Duration(seconds: 20)).then((_) async {
        if (!mounted || _video != c) return;
        await c.setLooping(widget.items.length <= 1);
        await c.setVolume(0);
        if (_active) await c.play();
        c.addListener(_onVideoTick);
        if (mounted) setState(() {});
      }).catchError((Object e) {
        if (!mounted || _video != c) return;
        StartupLog.add('Banner video failed (${item['id']}): $e');
        final n = (_tries[i] ?? 0) + 1;
        _tries[i] = n;
        if (n < 2) {
          // one quick retry (a slow first request or a dropped connection)
          Timer(const Duration(seconds: 2), () {
            if (mounted && _index == i && _active) _show(i);
          });
        } else {
          setState(() => _failed.add(i));
          _advance = Timer(const Duration(seconds: 5), _next);
        }
      });
      setState(() {});
    } else {
      _disposeVideo();
      final secs = math.max(3, asInt(item['duration_seconds']) == 0 ? 6 : asInt(item['duration_seconds']));
      if (_active) _advance = Timer(Duration(seconds: secs), _next);
    }
  }

  void _onVideoTick() {
    final c = _video;
    if (c == null || !c.value.isInitialized || widget.items.length <= 1) return;
    final d = c.value.duration;
    if (d > Duration.zero && c.value.position >= d - const Duration(milliseconds: 250) && !c.value.isPlaying) {
      c.removeListener(_onVideoTick);
      _next();
    }
  }

  void _next() {
    if (!mounted || !_active || widget.items.length <= 1 || !_pc.hasClients) return;
    final n = (_index + 1) % widget.items.length;
    _pc.animateToPage(n, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  void _tap(Map<String, dynamic> item) {
    final id = asInt(item['id']);
    fireAdEvent(id, 'CLICK');
    _video?.pause();
    showAdPopup(context, item).then((_) {
      if (mounted && _active && _videoFor == _index) _video?.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      SizedBox(
        height: widget.height,
        child: PageView.builder(
          controller: _pc,
          itemCount: items.length,
          onPageChanged: (i) {
            setState(() => _index = i);
            _show(i);
          },
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _slide(items[i], i),
          ),
        ),
      ),
      if (items.length > 1) ...[
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (i) {
            final on = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: on ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(color: on ? X9Colors.primary : context.x9.textSecondary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4)),
            );
          }),
        ),
      ],
    ]);
  }

  Widget _slide(Map<String, dynamic> item, int i) {
    final isVideo = str(item['type']).toUpperCase() == 'VIDEO';
    final m = asMap(item['merchant']);
    final brand = asMap(m['brand']);
    final logo = str(m['logo_url']).isNotEmpty ? str(m['logo_url']) : str(brand['logo_url']);
    final offer = offerLabel(item['offer']);
    final title = str(item['title']);
    final shop = str(m['shop_name']);

    Widget media;
    final c = _video;
    if (isVideo) {
      if (c != null && _videoFor == i && c.value.isInitialized) {
        media = FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
        );
      } else if (_failed.contains(i)) {
        media = Container(
          decoration: const BoxDecoration(gradient: X9Colors.heroGradient),
          child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 54)),
        );
      } else {
        media = Container(
          decoration: const BoxDecoration(gradient: X9Colors.heroGradient),
          child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))),
        );
      }
    } else {
      media = _BannerImage(id: asInt(item['id']), signedUrl: str(item['media_url']));
    }

    return GestureDetector(
      onTap: () => _tap(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          media,
          // Neutral text-protection scrim over the photo / video.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Theme.of(context).colorScheme.scrim.withValues(alpha: 0.72)],
                begin: Alignment.center,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          if (offer.isNotEmpty) Positioned(top: 12, left: 12, child: OfferBadge(offer, large: true)),
          if (isVideo)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4), shape: BoxShape.circle),
                child: const Icon(Icons.volume_off_rounded, color: Colors.white, size: 15),
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (shop.isNotEmpty || logo.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(13)),
                  child: LetterAvatar(shop.isEmpty ? str(brand['name'], 'X9') : shop, size: 38, url: logo),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (title.isNotEmpty)
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.15)),
                  if (shop.isNotEmpty)
                    Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: const Text('View offer', style: TextStyle(color: X9Colors.primaryDark, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
