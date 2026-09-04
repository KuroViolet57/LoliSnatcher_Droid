import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:lolisnatcher/src/boorus/kemono_api.dart';
import 'package:lolisnatcher/src/boorus/kemono_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/kemono_creator_store.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

/// One DM or announcement as the site shows it: who, when, the text.
class KemonoMessage {
  const KemonoMessage({required this.service, required this.user, required this.text, this.date, this.hash});

  final String service;
  final String user;
  final String text;
  final DateTime? date;
  final String? hash;

  static KemonoMessage? fromJson(Map row) {
    final String service = row['service']?.toString() ?? '';
    final String user = (row['user'] ?? row['user_id'])?.toString() ?? '';
    final String text = KemonoHandler.textOf(row['content']?.toString());
    if (service.isEmpty || user.isEmpty) return null;
    final String when = (row['published'] ?? row['added'])?.toString() ?? '';
    return KemonoMessage(
      service: service,
      user: user,
      text: text,
      date: DateTime.tryParse(when),
      hash: row['hash']?.toString(),
    );
  }
}

/// The site's DM list (`/api/v1/dms`, 50 a page, searchable) or one
/// creator's DMs. Read-only; tapping opens the creator, long-press copies.
class KemonoDmsPage extends StatefulWidget {
  const KemonoDmsPage({required this.booru, this.creator, super.key});

  final Booru booru;
  final ({String service, String id})? creator;

  @override
  State<KemonoDmsPage> createState() => _KemonoDmsPageState();
}

class _KemonoDmsPageState extends State<KemonoDmsPage> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<KemonoMessage> _rows = [];
  int _offset = 0;
  int _count = 0;
  bool _loading = false;
  bool _lastPage = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) unawaited(_loadMore());
    });
    unawaited(_reset());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    _rows.clear();
    _offset = 0;
    _lastPage = false;
    _error = null;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _lastPage) return;
    setState(() => _loading = true);
    try {
      List raw;
      if (widget.creator != null) {
        raw = await KemonoApi.creatorDms(widget.creator!.service, widget.creator!.id, booru: widget.booru);
        _count = raw.length;
        _lastPage = true;
      } else {
        final page = await KemonoApi.dms(offset: _offset, q: _query.text.trim(), booru: widget.booru);
        raw = page.rows;
        _count = page.count;
        _offset += 50;
        if (raw.length < 50) _lastPage = true;
      }
      final List<KemonoMessage> got = [
        for (final r in raw)
          if (r is Map) ?KemonoMessage.fromJson(r),
      ];
      await KemonoCreatorStore.instance.warmNames([for (final m in got) (service: m.service, id: m.user)]);
      _rows.addAll(got);
    } catch (e) {
      _error = e.toString();
      _lastPage = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_reset());
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? name = widget.creator == null
        ? null
        : KemonoCreatorStore.instance.nameOf(widget.creator!.service, widget.creator!.id);
    return Scaffold(
      appBar: AppBar(title: Text(widget.creator == null ? 'DMs' : 'DMs from ${name ?? widget.creator!.id}')),
      body: Column(
        children: [
          if (widget.creator == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _query,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Symbols.search_rounded),
                  hintText: 'Search DMs',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error ?? (_count > 0 ? '$_count messages' : ''),
                style: TextStyle(
                  fontSize: 11.5,
                  color: _error != null ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: _rows.isEmpty && !_loading
                ? const Center(child: Text('No messages'))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _rows.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _rows.length) {
                        return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                      }
                      return KemonoMessageTile(message: _rows[index], booru: widget.booru, showCreator: widget.creator == null);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One creator's announcements (`/api/v1/{service}/user/{id}/announcements`).
class KemonoAnnouncementsPage extends StatefulWidget {
  const KemonoAnnouncementsPage({required this.booru, required this.service, required this.id, super.key});

  final Booru booru;
  final String service;
  final String id;

  @override
  State<KemonoAnnouncementsPage> createState() => _KemonoAnnouncementsPageState();
}

class _KemonoAnnouncementsPageState extends State<KemonoAnnouncementsPage> {
  List<KemonoMessage> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await KemonoApi.announcements(widget.service, widget.id, booru: widget.booru);
      _rows = [
        for (final r in rows)
          if (r is Map) ?KemonoMessage.fromJson(r),
      ];
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final String name = KemonoCreatorStore.instance.nameOf(widget.service, widget.id) ?? widget.id;
    return Scaffold(
      appBar: AppBar(title: Text('Announcements from $name')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.orange))))
          : _rows.isEmpty
          ? const Center(child: Text('No announcements'))
          : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) => KemonoMessageTile(message: _rows[index], booru: widget.booru, showCreator: false),
            ),
    );
  }
}

class KemonoMessageTile extends StatelessWidget {
  const KemonoMessageTile({required this.message, required this.booru, this.showCreator = true, super.key});

  final KemonoMessage message;
  final Booru booru;
  final bool showCreator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String name = KemonoCreatorStore.instance.nameOf(message.service, message.user) ?? '${message.service}:${message.user}';
    final String when = message.date == null ? '' : DateFormat.yMMMd().add_Hm().format(message.date!.toLocal());
    return InkWell(
      onTap: () {
        SearchHandler.instance.addTabByString('creator:${message.service}:${message.user}', customBooru: booru, switchToNew: true);
        Navigator.of(context).pop();
      },
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.text));
        FlashElements.showSnackbar(context: context, title: const Text('Copied'), sideColor: Colors.green, duration: const Duration(seconds: 2));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showCreator) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundImage: NetworkImage(KemonoApi.iconUrl(message.service, message.user)),
                    onForegroundImageError: (_, _) {},
                    child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?', style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ] else
                  const Spacer(),
                Text(when, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(message.text.isEmpty ? '(no text)' : message.text, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
