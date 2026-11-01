import 'package:flutter/material.dart';
import 'package:x9_core/x9_core.dart';

import '../util/helpers.dart';
import 'skeleton.dart';

/// One page of results (works with Laravel paginators and plain arrays).
class PageResult {
  PageResult(this.items, this.hasMore);
  final List<dynamic> items;
  final bool hasMore;

  factory PageResult.from(dynamic json) {
    final items = asList(json);
    var hasMore = false;
    Map<String, dynamic>? pager;
    if (json is Map) {
      if (json['current_page'] != null) {
        pager = asMap(json);
      } else {
        for (final v in json.values) {
          if (v is Map && v['current_page'] != null) {
            pager = asMap(v);
            break;
          }
        }
      }
    }
    if (pager != null) hasMore = asInt(pager['current_page']) < asInt(pager['last_page']);
    return PageResult(items, hasMore);
  }
}

/// Infinite list with pull-to-refresh, skeleton loading, error retry and empty state.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.empty,
    this.header,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32),
    this.separator = 10,
  });

  final Future<PageResult> Function(int page) fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> item, int index) itemBuilder;
  final Widget? empty;
  final Widget? header;
  final EdgeInsets padding;
  final double separator;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final List<dynamic> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _first = true;
  Object? _error;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _page = 0;
      _hasMore = true;
      _error = null;
      _first = _items.isEmpty;
    });
    await _load(reset: true);
  }

  Future<void> _more() async {
    if (_loading || !_hasMore || _error != null) return;
    await _load();
  }

  Future<void> _load({bool reset = false}) async {
    _loading = true;
    try {
      final r = await widget.fetch(reset ? 1 : _page + 1);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(r.items);
        _page = reset ? 1 : _page + 1;
        _hasMore = r.hasMore;
        _error = null;
        _first = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _first = false;
      });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_first) {
      return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: widget.padding, children: [
        if (widget.header != null) widget.header!,
        for (var i = 0; i < 5; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonTile()),
      ]);
    }
    if (_error != null && _items.isEmpty) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          if (widget.header != null) widget.header!,
          const SizedBox(height: 60),
          ErrorRetry(message: friendlyError(_error!), onRetry: reload),
        ]),
      );
    }
    final count = _items.length + (widget.header != null ? 1 : 0) + 1;
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: count,
        itemBuilder: (context, i) {
          if (widget.header != null) {
            if (i == 0) return widget.header!;
            i -= 1;
          }
          if (i == _items.length) {
            if (_items.isEmpty) {
              return widget.empty ?? const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing here yet');
            }
            if (_error != null) {
              return Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    _more();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Could not load more. Retry'),
                ),
              );
            }
            if (_hasMore) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _more());
              return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            return const SizedBox(height: 24);
          }
          return Padding(
            padding: EdgeInsets.only(bottom: widget.separator),
            child: widget.itemBuilder(context, asMap(_items[i]), i),
          );
        },
      ),
    );
  }
}
