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
    int? fileSize,
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
      fileSize: fileSize,
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

  test('a GIF file of at most 2 MiB plays when the sample is not a separate GIF', () {
    const String gif = 'https://cdn.example/file.gif';
    const String thumb = 'https://cdn.example/thumb.jpg';
    const String jpgSample = 'https://cdn.example/sample.jpg';

    final ThumbnailLoadPlan small = plan(
      fileUrl: gif,
      sampleUrl: gif,
      standalone: false,
      fileSize: 260100,
    );
    expect(small.animate, isTrue);
    expect(small.url, gif);
    expect(small.resize, isFalse);
    expect(small.folder, 'media');

    expect(
      plan(fileUrl: gif, sampleUrl: gif, standalone: false, fileSize: 2 * 1024 * 1024).animate,
      isTrue,
      reason: '2 MiB is still inside the cap',
    );
    expect(
      plan(fileUrl: gif, sampleUrl: gif, standalone: false, fileSize: 2 * 1024 * 1024 + 1).url,
      thumb,
      reason: 'a larger GIF stays a static thumbnail',
    );
    expect(
      plan(fileUrl: gif, sampleUrl: gif, standalone: false).animate,
      isFalse,
      reason: 'an unknown size does not download the full file',
    );

    final ThumbnailLoadPlan stillSample = plan(
      fileUrl: gif,
      sampleUrl: jpgSample,
      standalone: false,
      fileSize: 839558,
    );
    expect(stillSample.url, gif);
    expect(stillSample.animate, isTrue);
    expect(stillSample.resize, isFalse);

    expect(
      plan(fileUrl: gif, sampleUrl: jpgSample, standalone: false).url,
      jpgSample,
      reason: 'unknown size keeps the still sample',
    );
    expect(
      plan(fileUrl: gif, sampleUrl: gif, standalone: false, fileSize: 260100, isHidden: true).animate,
      isFalse,
    );
    expect(
      plan(fileUrl: gif, sampleUrl: gif, standalone: false, fileSize: 260100, previewIsThumbnail: true).url,
      thumb,
      reason: 'thumbnail preview mode does not download the full file',
    );
    expect(
      plan(
        fileUrl: 'https://cdn.example/file.gif?token=1',
        sampleUrl: jpgSample,
        fileSize: 1000,
      ).url,
      'https://cdn.example/file.gif?token=1',
    );
    expect(
      plan(fileUrl: 'https://cdn.example/file.gifv', sampleUrl: jpgSample, fileSize: 1000).animate,
      isFalse,
    );
  });
}
