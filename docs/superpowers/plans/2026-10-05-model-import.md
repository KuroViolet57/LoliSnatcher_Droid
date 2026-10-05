# Model import (2026-10-05)

Goal: Settings → Recommendations & AI → Models can take a Hugging Face repo that is not one of the three preset file layouts, and can import a model folder from the device. Preset downloads stay on their current URLs.

This is a bounded change. Spec is the design in the session, grounded on the Hugging Face API and HEAD checks of 2026-10-05 (saved in the test comments of `test/hf_repo_test.dart`).

## Global constraints

- Work only on `grok/1.0-continue`. Do not touch Claude's worktree.
- No package, Flutter, Gradle or engine bump. No new settings key: the existing `imageTaggerModel` / `encoderModel` / `lookModel` strings and the same on-disk files.
- Preset downloads keep `https://huggingface.co/<repo>/resolve/main/<the preset file>`. Tests already lock those URLs.
- Model bytes stay under the settings path (`tagger/`, `encoder/`, `look/`). They are not added to backup: a model is hundreds of MB and Drive backup already holds whole files in memory. A restore still needs the model downloaded or imported again, which is what a preset restore does today.
- Do not copy the APK to K:.

## What failed, from live responses

- Pasting `https://huggingface.co/owner/model` is sent on as the repo id. HEAD of that URL shape was 404, 52,455 bytes (an HTML page), on 2026-10-05.
- A trailing slash (`owner/model/`) was HEAD 404 for `model.onnx`.
- `sentence-transformers/all-MiniLM-L6-v2` has `onnx/model.onnx` (90,405,214 bytes) and `vocab.txt`. HEAD of `onnx/model_quantized.onnx` was 404. The text encoder asks for that quantized name first and stops.
- `Xenova/paraphrase-multilingual-MiniLM-L12-v2` has `onnx/model_quantized.onnx` and `tokenizer.json`, and no `vocab.txt`. The text encoder needs a WordPiece `vocab.txt`.
- `openai/clip-vit-base-patch32` has `tokenizer.json` and no ONNX. The looks model asks for `onnx/vision_model_quantized.onnx` and surfaces a bare download error.
- `Xenova/siglip-base-patch16-224` `config.json` says `model_type` `siglip`. The looks model only runs a CLIP tokenizer. Refuse it before the large files.
- `Xenova/clip-vit-base-patch32` and the three SmilingWolf v3 taggers do have the preset names. Presets keep working. `resolve/<sha>/file` was HEAD 200 for the ViT `model.onnx` (378,536,310 bytes) and the MiniLM `onnx/model.onnx`.
- A missing repo returns HTTP 401 `{"error":"Invalid username or password."}`, not 404. The message has to cover a wrong name, a private repo and a gated repo.
- `hf.co/owner/model` redirects to `huggingface.co/owner/model`.

## Review focus

- A pasted link, a trailing slash, `hf.co`, and `owner/model` must land on the same repo. A github.com link, a lookalike host, and two links must not.
- Preset downloads must not call the file-list API and must keep their URLs.
- The large file is last, so a missing `vocab.txt` or a SigLIP `model_type` fails before hundreds of MB.
- A folder with two `model.onnx` files is refused by name. `../` in a file name is ignored.
- Import copies by stream. It does not read the whole ONNX into memory.
- Cancelling the folder picker is not an error.

## Tasks

1. `HfRepo` parse, choose, folder index. Test: `test/hf_repo_test.dart`.
2. Custom download and folder import on the three handlers, preset path unchanged. Tests added on the existing handler tests.
3. Folder picker (`selectModelFolder`, its own request code) and Import / explain on each model page.
4. Build the side-by-side arm64 APK and point at the folder. Do not copy to K:.

## Execution notes (2026-10-05)

- A pasted `/tree/main` link is pinned to the commit the file list was taken from. A link that names some other revision keeps that revision. The file list itself is still the repo's default branch.
- Folder import of a looks model copies `onnx/vision_model.onnx` to `vision_model_npu.onnx` when both halves are in the folder. A Hugging Face download stores the name and fetches it only from Speed → Run on → NPU.
- qint8_arm64 remains the last encoder choice and has not been loaded on a phone.
- Tests this session: `test/hf_repo_test.dart` 14, `test/image_tagger_handler_test.dart` 21, `test/encoder_handler_test.dart` 18, `test/look_model_handler_test.dart` 17, `test/recommendations_page_test.dart` 11, `test/architecture_test.dart` 2. All passed. The full suite was not re-run. Not tried on a phone.
- Linux/Windows plugin registrant files dirtied by `flutter test` were restored and not committed.
