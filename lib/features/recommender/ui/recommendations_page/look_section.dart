part of '../recommendations_page.dart';

/// r75: the downloadable looks model — which one, its state, the download
/// and the switch.
class LookModelSection extends StatefulWidget {
  const LookModelSection({super.key});

  @override
  State<LookModelSection> createState() => _LookModelSectionState();
}

class _LookModelSectionState extends State<LookModelSection> {
  final SettingsHandler settings = SettingsHandler.instance;
  final TextEditingController custom = TextEditingController();
  late String choice;

  @override
  void initState() {
    super.initState();
    final String current = settings.lookModel.trim();
    if (LookPreset.byId(current) != null) {
      choice = current;
    } else if (current.isNotEmpty) {
      choice = 'custom';
      custom.text = current;
    } else {
      choice = LookPreset.s0.id;
    }
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  String get chosenSetting => choice == 'custom' ? custom.text.trim() : choice;

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(bytes >= 100000000 ? 0 : 1);

  String _statusText(LookStatus s) {
    switch (s.state) {
      case LookState.none:
        return 'No looks model downloaded. Posts are ordered by their tags alone.${s.message.isEmpty ? '' : ' ${s.message}'}';
      case LookState.downloading:
        return 'Downloading ${s.repo}… ${(s.progress * 100).round()} %${s.bytes > 0 ? ' of ${_mb(s.bytes)} MB' : ''}';
      case LookState.ready:
        return 'Ready: ${s.repo} · ${_mb(s.bytes)} MB · ${s.inputSize} px'
            '${s.dim > 0 ? ' · ${s.dim} numbers' : ''}'
            '${s.downloadedAt == null ? '' : ' · downloaded ${DateFormat('dd MMM').format(s.downloadedAt!)}'}';
      case LookState.error:
        return 'Error: ${s.message}';
    }
  }

  Future<void> _download(LookModelHandler look) async {
    final String setting = chosenSetting;
    if (setting.isEmpty) return;
    final bool ok = await look.download(setting);
    if (ok) _followSaved(settings.lookModel);
    if (!ok && mounted) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Looks model download failed', style: TextStyle(fontSize: 18)),
        content: Text(look.status.value.message, style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 4),
        sideColor: Colors.red,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _import(LookModelHandler look) async {
    await runModelImport(
      context: context,
      stillMounted: () => mounted,
      refresh: () {
        _followSaved(settings.lookModel);
        if (mounted) setState(() {});
      },
      title: 'Looks model import failed',
      message: () => look.status.value.message,
      run: (Map<String, String> files) => look.importLocal(label: '', files: files, copy: (String relative, File dest) => copyListedModelFile(files, relative, dest)),
    );
  }

  void _followSaved(String saved) {
    if (LookPreset.byId(saved) != null) {
      choice = saved;
    } else if (saved.isNotEmpty) {
      choice = 'custom';
      custom.text = saved;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LookModelHandler? look = LookModelHandler.maybe;
    final TextStyle muted = TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Looks model', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A small model from Hugging Face (MobileCLIP, ONNX) that turns a picture, or a sentence, into numbers, so pictures that look alike sit close together. '
            '"Posts like this" and boards order their results by it, and For You learns from what the pictures look like, not only from their tags. Everything runs on the phone.',
            style: muted,
          ),
          if (look == null)
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('The looks model is not available in this build.'))
          else
            ValueListenableBuilder<LookStatus>(
              valueListenable: look.status,
              builder: (context, status, _) {
                final bool downloading = status.state == LookState.downloading;
                final bool ready = status.state == LookState.ready;
                final LookPreset? preset = LookPreset.byId(choice);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      _statusText(status),
                      key: const ValueKey('look-status'),
                      style: TextStyle(color: status.state == LookState.error ? theme.colorScheme.error : null),
                    ),
                    if (downloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: status.progress > 0 ? status.progress : null),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(key: const ValueKey('look-cancel'), onPressed: look.cancelDownload, child: const Text('Cancel')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final LookPreset p in LookPreset.values)
                          ChoiceChip(
                            key: ValueKey('look-preset-${p.id}'),
                            label: Text(p.label),
                            selected: choice == p.id,
                            onSelected: downloading ? null : (_) => setState(() => choice = p.id),
                          ),
                        ChoiceChip(
                          key: const ValueKey('look-preset-custom'),
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
                        key: const ValueKey('look-custom-repo'),
                        controller: custom,
                        enabled: !downloading,
                        decoration: const InputDecoration(
                          labelText: 'Hugging Face repo id',
                          hintText: 'owner/model or a huggingface.co link — CLIP vision and text ONNX files, plus tokenizer.json',
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
                          key: const ValueKey('look-download'),
                          onPressed: downloading || chosenSetting.isEmpty ? null : () => _download(look),
                          icon: const Icon(Symbols.download_rounded),
                          label: Text(ready && settings.lookModel == chosenSetting ? 'Download again' : 'Download'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('look-import'),
                          onPressed: downloading ? null : () => _import(look),
                          icon: const Icon(Symbols.folder_open_rounded),
                          label: const Text('Import from a folder'),
                        ),
                        ExplainButton(
                          key: const ValueKey('look-import-explain'),
                          title: 'Bringing in a looks model',
                          intro: 'Presets are the two MobileCLIP models. A custom repo has to be CLIP, split into a picture half and a text half.',
                          choices: () => const [
                            ExplainChoice(
                              name: 'Hugging Face repo',
                              text:
                                  'Type owner/model, or paste the repo page. The app prefers the quantized vision and text ONNX files, then the full-precision ones. A single combined onnx/model.onnx is refused. If config.json says the model is not CLIP (SigLIP, for example), the picture half is not downloaded. The full-precision picture half, when the repo has one, is fetched later from Speed → Run on → NPU.',
                            ),
                            ExplainChoice(
                              name: 'Import from a folder',
                              text:
                                  'Pick a folder you already downloaded. The app reads that folder and one level inside it. If both the quantized and the full-precision picture halves are there, the full-precision one is kept for the NPU.',
                            ),
                          ],
                          footer: 'A private or gated repo is refused. The message names the file that was missing.',
                        ),
                        if (ready)
                          OutlinedButton.icon(
                            key: const ValueKey('look-delete'),
                            onPressed: downloading
                                ? null
                                : () async {
                                    await look.delete();
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(Symbols.delete_rounded),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                    Text(
                      'Type owner/model or paste a repo link, or import a folder you already downloaded. Downloads come from huggingface.co; use Wi-Fi. Thumbnails are read once and remembered.',
                      style: muted,
                    ),
                    SettingsToggle(
                      key: const ValueKey('ai-look-toggle'),
                      value: settings.aiLook,
                      onChanged: (bool v) {
                        setState(() => settings.aiLook = v);
                        settings.saveSettings(restate: false);
                      },
                      title: 'Use the looks model',
                      subtitle: Text(
                        ready
                            ? 'Boards, Posts like this and For You read pictures with it. Off = the downloaded model is kept but not read.'
                            : 'Takes effect once a model is downloaded.',
                      ),
                      leadingIcon: const Icon(Symbols.visibility_rounded),
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
