part of '../recommendations_page.dart';

/// r34: the downloadable sentence encoder — which one, its state, the
/// download and the switch that lets its vectors into the learner.
class EncoderModelSection extends StatefulWidget {
  const EncoderModelSection({required this.onChanged, super.key});

  final Future<void> Function() onChanged;

  @override
  State<EncoderModelSection> createState() => _EncoderModelSectionState();
}

class _EncoderModelSectionState extends State<EncoderModelSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;

  @override
  void initState() {
    super.initState();
    final String current = settings.encoderModel.trim();
    if (EncoderPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = EncoderPreset.english.id;
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(EncoderStatus s) {
    switch (s.state) {
      case EncoderState.none:
        return 'No encoder downloaded. The learner reads tags alone.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case EncoderState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case EncoderState.ready:
        return 'Ready: ${s.repo} · ${s.dim} dimensions · ${_mb(s.bytes)} MB'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case EncoderState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(EncoderHandler encoder) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await encoder.download(setting);
    if (ok) _followSaved(settings.encoderModel);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Encoder download failed', style: TextStyle(fontSize: 18)),
        content: Text(encoder.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _import(EncoderHandler encoder) async {
    await runModelImport(
      context: context,
      stillMounted: () => mounted,
      refresh: () {
        _followSaved(settings.encoderModel);
        if (mounted) setState(() {});
      },
      title: 'Text model import failed',
      message: () => encoder.status.value.message,
      run: (Map<String, String> files) => encoder.importLocal(label: '', files: files, copy: (String relative, File dest) => copyListedModelFile(files, relative, dest)),
    );
  }

  void _followSaved(String saved) {
    if (EncoderPreset.byId(saved) != null) {
      choice = saved;
    } else if (saved.isNotEmpty) {
      choice = 'custom';
      custom.text = saved;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EncoderHandler? encoder = EncoderHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Downloaded encoder', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "A small sentence model from Hugging Face (ONNX) that reads each item's title and tags into a vector. "
            'Its components become features of the learner above, so two things that were never seen together but read alike '
            'can be liked alike. The model itself never learns — it understands language; the learner learns you.',
            style: muted,
          ),
          if (encoder == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The encoder is not available in this build.'))
          else
            ValueListenableBuilder<EncoderStatus>(
              valueListenable: encoder.status,
              builder: (context, status, _) {
                final bool downloading = status.state == EncoderState.downloading;
                final bool ready = status.state == EncoderState.ready;
                final EncoderPreset? preset = EncoderPreset.byId(choice);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('encoder-status'),
                      style: TextStyle(color: status.state == EncoderState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('encoder-cancel'), onPressed: encoder.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final EncoderPreset p in EncoderPreset.values)
                          ChoiceChip(
                            key: ValueKey('encoder-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('encoder-preset-custom'),
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
                        key: const ValueKey('encoder-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model or a huggingface.co link — an ONNX file, vocab.txt (WordPiece), tokenizer_config.json, config.json',
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
                          key: const ValueKey('encoder-download'),
                          onPressed: downloading || chosenSetting.isEmpty || chosenSetting.startsWith('files:') ? null : () => _download(encoder),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(chosenSetting.startsWith('files:') ? 'Imported from a folder' : (ready && settings.encoderModel == chosenSetting ? 'Download again' : 'Download')),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('encoder-import'),
                          onPressed: downloading ? null : () => _import(encoder),
                          icon: const Icon(Symbols.folder_open_rounded),
                          label: const Text('Import from a folder'),
                        ),
                        ExplainButton(
                          key: const ValueKey('encoder-import-explain'),
                          title: 'Bringing in a text model',
                          intro: 'Presets are the two sentence models this app was built around. A custom repo has to be WordPiece, the same tokenizer those use.',
                          choices: () => const [
                            ExplainChoice(
                              name: 'Hugging Face repo',
                              text:
                                  'Type owner/model, or paste the repo page. The app prefers onnx/model_quantized.onnx, then onnx/model.onnx. fp16, 4-bit and AVX builds are skipped. vocab.txt is required: a repo that only has tokenizer.json (SentencePiece) is refused before the model downloads.',
                            ),
                            ExplainChoice(
                              name: 'Import from a folder',
                              text: 'Pick a folder you already downloaded. The app reads that folder and one level inside it (the onnx folder first). Nothing is uploaded.',
                            ),
                          ],
                          footer: 'A private or gated repo is refused. The message names the file that was missing.',
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('encoder-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await encoder.delete();
                                    await widget.onChanged();
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                    Text('Type owner/model or paste a repo link, or import a folder you already downloaded. Downloads come from huggingface.co; use Wi-Fi.', style: muted),
                    SettingsToggle(
                      key: const ValueKey('ai-encoder-toggle'),
                      value: settings.aiEncoder,
                      onChanged: (bool v) {
                        setState(() => settings.aiEncoder = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the encoder',
                      subtitle: Text(
                        ready
                            ? 'Its vectors join the features the learner sees. Off = the downloaded model is kept but not read.'
                            : 'Takes effect once an encoder is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.psychology_rounded),
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
