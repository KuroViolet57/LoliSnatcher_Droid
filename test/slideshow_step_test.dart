import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/features/viewer/logic/slideshow_step.dart';

void main() {
  test('a slideshow advances, loads another page, or stops', () {
    expect(slideshowStep(index: 0, loaded: 3, canLoadMore: true), SlideshowStep.advance);
    expect(slideshowStep(index: 2, loaded: 3, canLoadMore: true), SlideshowStep.loadMore);
    expect(slideshowStep(index: 2, loaded: 3, canLoadMore: false), SlideshowStep.stop);
    expect(slideshowStep(index: 0, loaded: 0, canLoadMore: true), SlideshowStep.stop);
    expect(slideshowStep(index: 5, loaded: 3, canLoadMore: true), SlideshowStep.stop);
  });

  test('the viewer uses that step and loads the next page only then', () {
    final String src = File('lib/features/viewer/ui/chrome/hideable_appbar.dart').readAsStringSync();
    expect(src, contains('slideshowStep('));
    expect(src, contains('SlideshowStep.loadMore'));
    expect(src, contains('runSearch()'));
  });
}
