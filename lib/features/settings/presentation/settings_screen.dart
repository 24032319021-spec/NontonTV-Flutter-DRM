import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/android_tv_platform.dart';
import '../../channels/domain/playlist_source.dart';
import '../../channels/presentation/home_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.initialTab = 0,
  });

  final HomeController controller;
  final int initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _boot = false;
  bool _bootLoading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab < 0 ? 0 : (widget.initialTab > 2 ? 2 : widget.initialTab),
    );
    widget.controller.addListener(_refresh);
    unawaited(_loadPlatformSettings());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPlatformSettings() async {
    final boot = await AndroidTvPlatform.getAutoStartOnBoot();
    if (mounted) {
      setState(() {
        _boot = boot;
        _bootLoading = false;
      });
    }
  }

  Future<void> _setBoot(bool value) async {
    setState(() => _boot = value);
    try {
      await AndroidTvPlatform.setAutoStartOnBoot(value);
    } catch (_) {
      if (mounted) setState(() => _boot = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
        actions: [
          IconButton(
            tooltip: 'Tutup pengaturan',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'PLAYLIST'),
            Tab(text: 'APPLICATION'),
            Tab(text: 'ABOUT'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PlaylistTab(controller: widget.controller),
          _ApplicationTab(
            controller: widget.controller,
            boot: _boot,
            bootLoading: _bootLoading,
            onBootChanged: _setBoot,
          ),
          const _AboutTab(),
        ],
      ),
    );
  }
}

class _PlaylistTab extends StatefulWidget {
  const _PlaylistTab({required this.controller});
  final HomeController controller;

  @override
  State<_PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends State<_PlaylistTab> {
  final _url = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;

  @override
  void dispose() {
    _url.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _url.text.trim();
    if (_submitting || widget.controller.loading || value.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.addUrlSource(name: '', url: value);
      if (!mounted) return;
      _url.clear();
      _focus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.importResult?.summary ?? 'Playlist ditambahkan')),
      );
    } catch (_) {
      // HomeController already exposes a user-safe error below the input.
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final disabled = _submitting || controller.loading;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.description_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _url,
                focusNode: _focus,
                enabled: !disabled,
                autofocus: false,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'isikan link playlist disini, kemudian klik ikon rantai disamping...',
                  border: UnderlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Tambahkan link playlist',
              onPressed: disabled ? null : _submit,
              icon: const Icon(Icons.add_link_rounded),
            ),
          ],
        ),
        if (disabled) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Divider(height: 28),
        ...controller.sources.map(
          (source) => _SourceTile(
            source: source,
            selected: controller.selectedSource?.id == source.id,
            canDelete: !controller.loading && controller.sources.length > 1,
            onSelect: controller.loading ? null : () => controller.selectSource(source),
            onDelete: () => controller.removeSource(source),
          ),
        ),
      ],
    );
  }
}

class _ApplicationTab extends StatelessWidget {
  const _ApplicationTab({
    required this.controller,
    required this.boot,
    required this.bootLoading,
    required this.onBootChanged,
  });

  final HomeController controller;
  final bool boot;
  final bool bootLoading;
  final ValueChanged<bool> onBootChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        SwitchListTile(
          title: const Text('Optimize prebuffer'),
          subtitle: const Text('Mempercepat persiapan buffer saat channel dibuka.'),
          value: controller.optimizePrebuffer,
          onChanged: controller.setOptimizePrebuffer,
        ),
        const SizedBox(height: 8),
        _UserAgentInput(controller: controller),
        const Divider(height: 28),
        SwitchListTile(
          title: const Text('Lanjutkan channel terakhir'),
          subtitle: const Text('Buka kembali channel terakhir saat aplikasi dimulai.'),
          value: controller.autoResume,
          onChanged: controller.setAutoResume,
        ),
        SwitchListTile(
          title: const Text('Jalankan saat perangkat boot'),
          subtitle: const Text('Mulai SitorusTV otomatis pada perangkat yang mendukung fitur ini.'),
          value: boot,
          onChanged: bootLoading ? null : onBootChanged,
        ),
      ],
    );
  }
}

class _UserAgentInput extends StatefulWidget {
  const _UserAgentInput({required this.controller});
  final HomeController controller;

  @override
  State<_UserAgentInput> createState() => _UserAgentInputState();
}

class _UserAgentInputState extends State<_UserAgentInput> {
  late final TextEditingController _text;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.userAgent);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.setUserAgent(_text.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text.text.trim().isEmpty
              ? 'User-Agent kustom dinonaktifkan.'
              : 'User-Agent disimpan.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      enabled: !_saving,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: 'User-Agent',
        hintText: 'Masukkan User-Agent sendiri (opsional)',
        helperText: 'Kosongkan untuk memakai User-Agent dari playlist/player.',
        prefixIcon: const Icon(Icons.public_rounded),
        suffixIcon: IconButton(
          tooltip: 'Simpan User-Agent',
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded),
        ),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: const [
        Icon(Icons.live_tv_rounded, size: 64),
        SizedBox(height: 18),
        Center(
          child: Text(
            'SitorusTV',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(height: 8),
        Center(child: Text('Versi 0.6.2')),
        SizedBox(height: 26),
        Text(
          'SitorusTV adalah aplikasi pemutar TV dan playlist.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 18),
        Text(
          'Tampilan berbasis proyek NontonTV oleh Hari Murti. '
          'Kredit dan ketentuan sumber asli tersedia di ORIGINAL_PROJECT_NOTICE.md.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.canDelete,
    required this.onSelect,
    required this.onDelete,
  });

  final PlaylistSource source;
  final bool selected;
  final bool canDelete;
  final Future<void> Function()? onSelect;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Icon(
        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
      ),
      title: Text(source.name),
      subtitle: Text(source.location, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      onTap: onSelect,
      trailing: canDelete
          ? IconButton(
              tooltip: 'Hapus playlist',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Hapus playlist?'),
                    content: Text(source.name),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await onDelete();
              },
              icon: const Icon(Icons.remove_circle_outline_rounded),
            )
          : null,
    );
  }
}
