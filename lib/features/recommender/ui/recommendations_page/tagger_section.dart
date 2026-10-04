part of '../recommendations_page.dart';

/// r74: the downloadable image tagger — which one, its state, the download,
/// Try it on a picture, and the two switches.
class TaggerModelSection extends StatefulWidget {
  const TaggerModelSection({super.key});

  @override
  State<TaggerModelSection> createState() => _TaggerModelSectionState();
}

class _TaggerModelSectionState extends State<TaggerModelSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;
  TaggerResult? tried;
  String tryError = '';

  /// r77: a neutral note (nothing came back from the picker - a cancel looks
  /// the same), not an error.
  String tryNote = '';
  bool trying = false;

  @override
  void initState() {
    super.initState();
    final String current = settings.imageTaggerModel.trim();
    if (TaggerPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = TaggerPreset.wdVit.id;
    }
    unawaited(_recoverLostPick());
  }

  /// r77: a Try it whose picture came back after Android had ended the app
  /// is finished now instead of being lost without a word.
  Future<void> _recoverLostPick() async {
    final Uint8List? bytes = await _keptPicture();
    if (bytes == null || !mounted) return;
    Logger.Inst().log('tagger: Try it - a picture picked before the app was restarted came back (${bytes.length ~/ 1024} KB)', 'RecommendationsPage', '_recoverLostPick', LogTypes.booruHandlerInfo);
    await _readPicked(bytes);
  }

  /// r78: a picture the picker kept for us, if any. Its failure is said,
  /// not swallowed.
  Future<Uint8List?> _keptPicture() async {
    try {
      return await RecommendationsPage.lostPick();
    } catch (e) {
      Logger.Inst().log('tagger: Try it - could not ask the picker for a kept picture: $e', 'RecommendationsPage', '_keptPicture', LogTypes.booruHandlerInfo);
      return null;
    }
  }

  /// r78: why the tagger cannot read a picture right now.
  String _notReadyNote(TaggerStatus s) {
    switch (s.state) {
      case TaggerState.none:
        return 'Download an image tagger first.';
      case TaggerState.downloading:
        return 'The image tagger is still downloading.';
      case TaggerState.error:
        return 'The image tagger is not ready: ${s.message}';
      case TaggerState.ready:
        return '';
    }
  }

  Future<void> _readPicked(Uint8List bytes) async {
    if (trying) return;
    setState(() {
      trying = true;
      tryError = '';
      tryNote = '';
      tried = null;
    });
    try {
      final TaggerResult? r = await RecommendationsPage.tagImage?.call(bytes);
      if (mounted) setState(() => tried = r);
    } catch (e) {
      Logger.Inst().log('tagger: Try it failed: $e', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      if (mounted) setState(() => tryError = 'Could not read the picture: $e');
    } finally {
      if (mounted) setState(() => trying = false);
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(TaggerStatus s) {
    switch (s.state) {
      case TaggerState.none:
        return 'No image tagger downloaded. Boards read a reference image through SauceNAO only.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case TaggerState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case TaggerState.ready:
        return 'Ready: ${s.repo} · ${s.tagCount} tags · ${s.inputSize} px · ${_mb(s.bytes)} MB'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case TaggerState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(ImageTaggerHandler tagger) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await tagger.download(setting);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Image tagger download failed', style: TextStyle(fontSize: 18)),
        content: Text(tagger.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _tryIt() async {
    // r78: a tap is never silent. Before, the button was simply dead while a
    // pick was in flight or the tagger was not ready - and a pick that never
    // answered left it dead for good.
    if (trying) {
      Logger.Inst().log('tagger: Try it - still reading the last picture', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      setState(() {
        tryError = '';
        tryNote = 'Still reading the last picture…';
      });
      return;
    }
    final TaggerStatus status = ImageTaggerHandler.maybe?.status.value ?? TaggerStatus.none;
    if (status.state != TaggerState.ready) {
      Logger.Inst().log('tagger: Try it - the tagger is not ready (${status.state.name})', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      setState(() {
        tryError = '';
        tryNote = _notReadyNote(status);
      });
      return;
    }
    setState(() {
      trying = true;
      tryError = '';
      tryNote = '';
      tried = null;
    });
    try {
      // r77: how long the picker was open tells an instant automatic
      // cancel from a person who cancelled.
      final PickResult<Uint8List> picked = await PickerWatch.run<Uint8List>(
        () => RecommendationsPage.pickImageBytes?.call() ?? Future<Uint8List?>.value(),
        onLate: (Uint8List bytes) => unawaited(_readPicked(bytes)),
      );
      final String openFor = '${picked.openFor}, ${PhotoPicker.systemPickerOn ? "Android's photo picker" : 'the default picker'}';
      if (picked.outcome == PickOutcome.failed) {
        Logger.Inst().log('tagger: Try it failed: ${picked.error}', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
        if (mounted) setState(() => tryError = 'Could not read the picture: ${picked.error}');
        return;
      }
      if (picked.outcome == PickOutcome.lost) {
        // r78: the picker never answered. Before, this waited for ever.
        Logger.Inst().log('tagger: Try it - gave up waiting for the picker (${picked.reason}, open $openFor)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
        final Uint8List? kept = await _keptPicture();
        if (kept != null) {
          Logger.Inst().log('tagger: Try it - the picker had kept the picture (${kept.length ~/ 1024} KB)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
          final TaggerResult? r = await RecommendationsPage.tagImage?.call(kept);
          if (mounted) setState(() => tried = r);
          return;
        }
        if (mounted) setState(() => tryNote = 'The picker closed without giving a picture. Try again.');
        return;
      }
      final Uint8List? bytes = picked.value;
      if (bytes == null) {
        // r77: said, not swallowed - on 19 Sep the phone showed nothing and
        // logged nothing.
        Logger.Inst().log('tagger: Try it - no picture came back from the picker (open $openFor)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
        if (mounted) setState(() => tryNote = 'No picture came back from the picker.');
        return;
      }
      Logger.Inst().log('tagger: Try it on a picture of ${bytes.length ~/ 1024} KB (picker open $openFor)', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      final TaggerResult? r = await RecommendationsPage.tagImage?.call(bytes);
      if (mounted) setState(() => tried = r);
    } catch (e) {
      Logger.Inst().log('tagger: Try it failed: $e', 'RecommendationsPage', '_tryIt', LogTypes.booruHandlerInfo);
      if (mounted) setState(() => tryError = 'Could not read the picture: $e');
    } finally {
      if (mounted) setState(() => trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ImageTaggerHandler? tagger = ImageTaggerHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image tagger', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A booru tagger from Hugging Face (ONNX) that reads tags straight from the pixels, on the phone: general tags, characters and a rating in the danbooru spelling. '
            "A board's reference image is read with it (no SauceNAO key needed), and, with the switch below, so is the thumbnail of a post you react to.",
            style: muted,
          ),
          if (tagger == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The image tagger is not available in this build.'))
          else
            ValueListenableBuilder<TaggerStatus>(
              valueListenable: tagger.status,
              builder: (context, status, _) {
                final bool downloading = status.state == TaggerState.downloading;
                final bool ready = status.state == TaggerState.ready;
                final TaggerPreset? preset = TaggerPreset.byId(choice);
                final TaggerResult? r = tried;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('tagger-status'),
                      style: TextStyle(color: status.state == TaggerState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('tagger-cancel'), onPressed: tagger.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final TaggerPreset p in TaggerPreset.values)
                          ChoiceChip(
                            key: ValueKey('tagger-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('tagger-preset-custom'),
                          label: const Text('Custom repo'),
                          selected: choice == 'custom',
                          onSelected: downloading ? null : (_) => setState(() => choice = 'custom'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (preset != null)
                      Text(preset.description, style: muted)
                    else
                      TextField(
                        key: const ValueKey('tagger-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model — needs model.onnx (one picture in, one score per tag out) and selected_tags.csv',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('tagger-download'),
                          onPressed: downloading || chosenSetting.isEmpty ? null : () => _download(tagger),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(ready && settings.imageTaggerModel == chosenSetting ? 'Download again' : 'Download'),
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('tagger-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await tagger.delete();
                                    if (mounted) setState(() => tried = null);
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                        // r80: a job of its own in Models; switched off, not built.
                        ValueListenableBuilder<int>(
                          valueListenable: ModelTasks.revision,
                          builder: (context, _, _) => ModelTasks.isOn(ModelTasks.taggerTryIt)
                              ? OutlinedButton.icon(
                                  key: const ValueKey('tagger-try'),
                                  // r78: never a dead grey rectangle - a tap that
                                  // cannot read a picture says why.
                                  onPressed: _tryIt,
                                  icon: const Icon(Symbols.image_search_rounded),
                                  label: Text(trying ? 'Reading…' : 'Try it on a picture'),
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text('Try it is switched off (Models).', key: const ValueKey('tagger-try-off'), style: muted),
                                ),
                        ),
                      ],
                    ),
                    Text('Models come from huggingface.co; download over Wi-Fi. The model is opened on first use and closed after two idle minutes.', style: muted),
                    if (tryError.isNotEmpty || tryNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tryError.isNotEmpty ? tryError : tryNote,
                          key: const ValueKey('tagger-try-message'),
                          style: tryError.isNotEmpty ? TextStyle(color: theme.colorScheme.error) : muted,
                        ),
                      ),
                    if (r != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${r.count} tags in ${r.totalMs} ms (decode ${r.decodeMs} ms, model ${r.modelMs} ms, ${r.provider}) · rating ${r.rating} ${(r.ratingConfidence * 100).round()}%',
                        key: const ValueKey('tagger-try-result'),
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final PixelTag p in r.all)
                            Chip(
                              avatar: p.character ? const Icon(Symbols.person_rounded, size: 16) : null,
                              label: Text('${p.tag} ${(p.confidence * 100).round()}%'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                    SettingsToggle(
                      key: const ValueKey('ai-tagger-toggle'),
                      value: settings.aiImageTagger,
                      onChanged: (bool v) {
                        setState(() => settings.aiImageTagger = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the image tagger',
                      subtitle: Text(
                        ready ? 'Boards read their reference image with it. Off = the downloaded model is kept but not read.' : 'Takes effect once a tagger is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.image_search_rounded),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
