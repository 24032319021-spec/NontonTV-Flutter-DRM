import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/branding/brand_assets.dart';
import '../../../core/platform/tv_display.dart';
import '../../../core/theme/app_theme.dart';
import '../../player/presentation/player_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../domain/channel.dart';
import '../domain/playlist_source.dart';
import 'home_controller.dart';
import 'tv_home_metrics.dart';

enum _ChannelFilter { all, favorites, group }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});
  final HomeController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  final _search = TextEditingController();
  Timer? _searchTimer;
  _ChannelFilter _filter = _ChannelFilter.group;
  String? _selectedGroup;
  String? _displayedSourceId;
  String _query = '';
  List<TvChannel> _visible = const [];
  bool _didAutoResume = false;
  bool _playerOpen = false;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? HomeController();
    _controller.addListener(_onControllerChanged);
    _updateVisible();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _updateVisible() {
    final groups = _controller.groupedChannels;
    if (_displayedSourceId != _controller.selectedSource?.id ||
        (_filter == _ChannelFilter.group && !groups.containsKey(_selectedGroup))) {
      _displayedSourceId = _controller.selectedSource?.id;
      _selectedGroup = groups.isEmpty ? null : groups.keys.first;
      _filter = _selectedGroup == null ? _ChannelFilter.all : _ChannelFilter.group;
    }
    final items = switch (_filter) {
      _ChannelFilter.all => _controller.channels,
      _ChannelFilter.favorites => _controller.currentFavorites,
      _ChannelFilter.group => groups[_selectedGroup] ?? <TvChannel>[],
    };
    _visible = _query.isEmpty ? items : items.where((channel) =>
      channel.name.toLowerCase().contains(_query) ||
      channel.group.toLowerCase().contains(_query)).toList(growable: false);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(_updateVisible);
    if (!_didAutoResume && _controller.initialized && !_controller.loading) {
      _didAutoResume = true;
      final channel = _controller.resumableChannel;
      if (channel != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openPlayer(channel);
        });
      }
    }
  }

  void _select(_ChannelFilter filter, [String? group]) => setState(() {
    _filter = filter;
    _selectedGroup = group;
    _updateVisible();
  });

  Future<void> _openPlayer(TvChannel channel) async {
    if (_playerOpen) return;
    final channels = _controller.channels;
    final index = channels.indexWhere((item) => identical(item, channel));
    if (index < 0) return;
    _playerOpen = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(
        channels: channels, initialIndex: index, homeController: _controller,
      )));
    } finally {
      _playerOpen = false;
      if (mounted) unawaited(TvDisplay.enterFullscreen());
    }
  }

  Future<void> _addPlaylist() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(controller: _controller, initialTab: 0),
    ));
    if (!mounted) return;
    _searchTimer?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _searchOpen = false;
      _updateVisible();
    });
    unawaited(TvDisplay.enterFullscreen());
  }

  Future<void> _showLibrary() async {
    final choice = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Row(children: [
          Image.asset(BrandAssets.logo, width: 48, height: 48, cacheWidth: 128),
          const SizedBox(width: 12),
          const Expanded(child: Text('Playlist & favorit')),
          IconButton(tooltip: 'Tutup menu playlist',
            onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
        ]),
        children: [
          ListTile(leading: const Icon(Icons.playlist_add_rounded), title: const Text('Tambah playlist'),
            enabled: !_controller.loading,
            onTap: () => Navigator.pop(dialogContext, 'add')),
          ListTile(leading: const Icon(Icons.star_rounded), title: const Text('Favorit'),
            onTap: () => Navigator.pop(dialogContext, 'favorites')),
          ListTile(leading: const Icon(Icons.apps_rounded), title: const Text('Semua saluran'),
            onTap: () => Navigator.pop(dialogContext, 'all')),
          const Divider(),
          ..._controller.sources.map((source) => ListTile(
            title: Text(source.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            leading: const Icon(Icons.playlist_play_rounded),
            trailing: source.id == _controller.selectedSource?.id ? const Icon(Icons.check_rounded) : null,
            enabled: !_controller.loading,
            onTap: () => Navigator.pop(dialogContext, source),
          )),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'add') await _addPlaylist();
    if (choice == 'favorites') _select(_ChannelFilter.favorites);
    if (choice == 'all') _select(_ChannelFilter.all);
    if (choice is PlaylistSource) await _controller.selectSource(choice);
  }

  Future<void> _showSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(controller: _controller)));
    if (mounted) unawaited(TvDisplay.enterFullscreen());
  }

  void _setQuery(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {
          _query = value.trim().toLowerCase();
          _updateVisible();
        });
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchTimer?.cancel();
        _search.clear();
        _query = '';
        _updateVisible();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final metrics = TvHomeMetrics(viewport);
    if (!_controller.initialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          Image.asset(BrandAssets.loading, key: const ValueKey('loading-screen'),
            fit: metrics.landscape ? BoxFit.cover : BoxFit.contain,
            cacheWidth: 1672, excludeFromSemantics: true),
          Positioned(left: 0, right: 0, bottom: 24,
            child: Center(child: Semantics(label: 'Memuat SitorusTV',
              child: const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))))),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // This supplied artwork already includes the SitorusTV wordmark.
        // Fill preserves its complete frame; do not add a second header logo.
        RepaintBoundary(child: Image.asset(BrandAssets.menu,
          key: const ValueKey('menu-background'), fit: BoxFit.fill,
          cacheWidth: 1672, filterQuality: FilterQuality.low, excludeFromSemantics: true)),
        SafeArea(top: false, bottom: false,
          child: Column(children: [
            _buildHeader(metrics),
            if (_controller.loading) const LinearProgressIndicator(minHeight: 2),
            if (_controller.error != null && _controller.channels.isNotEmpty)
              Container(width: double.infinity, color: const Color(0xD0462323),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text('${_controller.error} Saluran sebelumnya tetap tersedia.',
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
            Expanded(child: _buildContent(metrics)),
          ])),
      ]),
    );
  }

  Widget _buildHeader(TvHomeMetrics metrics) {
    if (_searchOpen) {
      return SizedBox(height: metrics.headerHeight.clamp(52, 90).toDouble(),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(autofocus: true, controller: _search, onChanged: _setQuery,
            decoration: InputDecoration(hintText: 'Cari saluran atau kategori',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(tooltip: 'Tutup pencarian',
                onPressed: _toggleSearch, icon: const Icon(Icons.close_rounded))),
          )));
    }
    return SizedBox(height: metrics.headerHeight,
      child: Padding(padding: EdgeInsets.symmetric(horizontal: metrics.landscape ? 16 * metrics.unit : 8),
        child: Row(children: [
          Tooltip(message: 'Playlist & favorit',
            child: SizedBox(width: metrics.landscape ? 370 * metrics.unit : 130,
              height: metrics.headerHeight,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: _showLibrary,
                child: metrics.landscape
                    ? Semantics(label: 'SitorusTV — buka playlist dan favorit', child: const SizedBox.expand())
                    : const Text('SitorusTV', style: TextStyle(fontWeight: FontWeight.w700)),
              ))),
          const Spacer(),
          _headerButton('Cari channel', Icons.search_rounded, _toggleSearch, metrics),
          _headerButton('Muat ulang playlist', Icons.refresh_rounded,
            _controller.loading ? null : _controller.reload, metrics),
          _headerButton('Pengaturan', Icons.settings, _showSettings, metrics),
          _headerButton('Tutup aplikasi', Icons.power_settings_new_rounded,
            () => SystemNavigator.pop(), metrics),
        ])));
  }

  Widget _headerButton(String label, IconData icon, VoidCallback? action, TvHomeMetrics metrics) {
    final size = metrics.landscape ? 60 * metrics.unit : 44.0;
    return SizedBox(width: size, height: size,
      child: IconButton(tooltip: label,
        style: IconButton.styleFrom(padding: EdgeInsets.zero,
          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: Colors.white, focusColor: AppTheme.orange.withValues(alpha: .7)),
        onPressed: action,
        icon: Icon(icon, size: metrics.landscape ? 32 * metrics.unit : 24),
      ));
  }

  Widget _buildContent(TvHomeMetrics metrics) {
    if (_controller.channels.isEmpty) {
      return _EmptyState(
        title: _controller.error == null ? 'Tontonan dimulai di sini' : 'Playlist belum dapat dimuat',
        detail: _controller.error ?? 'Tambahkan playlist untuk mulai menonton.',
        onAdd: _controller.loading ? null : _addPlaylist,
        onRetry: _controller.loading ? null : _controller.reload,
      );
    }
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight < 100) return _channelGrid(metrics);
      if (!metrics.landscape) {
        return Column(children: [
          SizedBox(height: 52, child: _categoryList(metrics, horizontal: true)),
          Expanded(child: _channelGrid(metrics)),
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(key: const ValueKey('category-sidebar'), width: metrics.sidebarWidth,
          child: _categoryList(metrics)),
        Expanded(child: _channelGrid(metrics)),
      ]);
    });
  }

  Widget _channelGrid(TvHomeMetrics metrics) {
    if (_visible.isEmpty) return const Center(child: Text('Tidak ada channel yang cocok.'));
    return Padding(padding: EdgeInsets.only(left: 4 * metrics.unit, right: 12 * metrics.unit),
      child: GridView.builder(
        key: PageStorageKey('${_controller.selectedSource?.id}/$_filter/$_selectedGroup/$_query'),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: metrics.columns, mainAxisExtent: metrics.rowHeight),
        itemCount: _visible.length,
        itemBuilder: (context, index) {
          final channel = _visible[index];
          return _ChannelTile(
            key: ValueKey((channel.id, index)), channel: channel, metrics: metrics,
            favorite: _controller.isFavorite(channel),
            onTap: () => _openPlayer(channel),
            onFavorite: () => _controller.toggleFavorite(channel),
          );
        },
      ));
  }

  Widget _categoryList(TvHomeMetrics metrics, {bool horizontal = false}) {
    // Keep playlist order, as in the reference, instead of alphabetizing it.
    final groups = _controller.groupedChannels.keys.toList(growable: false);
    return ListView.builder(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      padding: EdgeInsets.fromLTRB(18 * metrics.unit, 7 * metrics.unit, 10 * metrics.unit, 8 * metrics.unit),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final selected = _filter == _ChannelFilter.group && _selectedGroup == group;
        return Padding(padding: EdgeInsets.only(bottom: metrics.categoryGap, right: horizontal ? 5 : 0),
          child: SizedBox(width: horizontal ? 165 : null,
            child: TextButton(
              style: ButtonStyle(
                alignment: Alignment.centerLeft,
                minimumSize: WidgetStatePropertyAll(Size(0, metrics.categoryHeight)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(
                  horizontal: 30 * metrics.unit, vertical: 12 * metrics.unit)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5 * metrics.unit))),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) return AppTheme.orange;
                  if (states.contains(WidgetState.pressed)) return const Color(0xFF03DAC6);
                  return selected ? AppTheme.teal : Colors.transparent;
                }),
              ),
              onPressed: () => _select(_ChannelFilter.group, group),
              child: Text(group.toUpperCase(), maxLines: horizontal ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: metrics.categoryFontSize, height: 1.25,
                  fontWeight: FontWeight.w700)),
            ),
          ));
      },
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({super.key, required this.channel, required this.metrics,
    required this.favorite, required this.onTap, required this.onFavorite});
  final TvChannel channel;
  final TvHomeMetrics metrics;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  Future<void> _favoriteMenu() async {
    final change = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(widget.channel.name),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.star_rounded),
          label: Text(widget.favorite ? 'Hapus dari favorit' : 'Tambah ke favorit')),
      ],
    ));
    if (change == true && mounted) widget.onFavorite();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final fallback = Icon(Icons.live_tv_rounded, size: m.logoSize * .5, color: Colors.white70);
    return Shortcuts(shortcuts: const {
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    }, child: CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.contextMenu): () => unawaited(_favoriteMenu()),
    }, child: Material(color: Colors.transparent,
      child: InkWell(onTap: widget.onTap, onLongPress: _favoriteMenu,
        onFocusChange: (focused) => setState(() => _focused = focused),
        focusColor: AppTheme.orange.withValues(alpha: .22),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white38, width: .6))),
          child: Column(children: [
            SizedBox(height: m.logoTop),
            SizedBox(width: m.logoSize, height: m.logoSize,
              child: widget.channel.logo == null ? Center(child: fallback) : Image.network(widget.channel.logo!,
                fit: BoxFit.contain, cacheWidth: 256, filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => Center(child: fallback))),
            SizedBox(height: m.captionGap),
            Padding(padding: EdgeInsets.symmetric(horizontal: 6 * m.unit),
              child: Text(widget.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: m.captionSize, height: 1.1, fontWeight: FontWeight.w700,
                  color: _focused ? AppTheme.orange : Colors.white))),
          ]),
        ),
      ),
    )));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.detail, this.onAdd, this.onRetry});
  final String title;
  final String detail;
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.live_tv_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10), Text(detail, textAlign: TextAlign.center),
        const SizedBox(height: 24), Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Tambah playlist')),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Coba lagi')),
        ]),
      ]))));
}
