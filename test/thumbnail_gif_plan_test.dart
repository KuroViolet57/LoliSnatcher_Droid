import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/features/feed/ui/thumbnail/thumbnail_gif_plan.dart';

void main() {
  ThumbnailLoadPlan plan({
    bool previewIsThumbnail = false,
    bool isAnimation = true,
    bool disableImageScaling = true,
    bool gifsAsThumbnails = true,
    bool isHidden = false,
    bool isVideo = false,
    bool needsGuess = false,
    bool needsLoadItem = false,
    bool standalone = true,
    String fileUrl = 'https://cdn.example/file.png',
    String sampleUrl = 'https://cdn.example/sample.gif',
    String thumbnailUrl = 'https://cdn.example/thumb.jpg',
  }) {
    return planThumbnailLoad(
      previewIsThumbnail: previewIsThumbnail,
      isAnimation: isAnimation,
      disableImageScaling: disableImageScaling,
      gifsAsThumbnails: gifsAsThumbnails,
      isHidden: isHidden,
      isVideo: isVideo,
      needsGuess: needsGuess,
      needsLoadItem: needsLoadItem,
      standalone: standalone,
      fileUrl: fileUrl,
      sampleUrl: sampleUrl,
      thumbnailUrl: thumbnailUrl,
    );
  }

  test('an allowed GIF sample plays in the grid and is not resized to one frame', () {
    final ThumbnailLoadPlan gif = plan();
    expect(gif.url, 'https://cdn.example/sample.gif');
    expect(gif.folder, 'samples');
    expect(gif.animate, isTrue);
    expect(gif.resize, isFalse);

    expect(plan(gifsAsThumbnails: false).url, 'https://cdn.example/thumb.jpg');
    expect(plan(disableImageScaling: false).animate, isFalse);
    expect(plan(isHidden: true).animate, isFalse, reason: 'a hidden GIF stays a static thumbnail');
    expect(plan(isVideo: true).url, 'https://cdn.example/thumb.jpg');
    expect(plan(needsLoadItem: true).animate, isFalse);
    expect(
      plan(fileUrl: 'https://cdn.example/sample.gif', standalone: false).animate,
      isFalse,
      reason: 'a sample that is the full file stays a thumbnail in the grid',
    );

    final ThumbnailLoadPlan still = plan(
      isAnimation: false,
      sampleUrl: 'https://cdn.example/sample.jpg',
      fileUrl: 'https://cdn.example/file.jpg',
    );
    expect(still.url, 'https://cdn.example/sample.jpg');
    expect(still.animate, isFalse);
    expect(still.resize, isTrue, reason: 'a normal sample still decodes to the cell size');
  });
}
