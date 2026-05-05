import 'dart:async';
import 'dart:math';

// Mocked sendBooruItem
Future<String> sendBooruItem(int item, int total, int current) async {
  // Simulate network latency
  await Future.delayed(Duration(milliseconds: 50));
  return 'OK';
}

void main() async {
  final fetched = List.generate(100, (i) => i);
  final favouritesCount = 100;
  final offset = 0;

  print('Testing sequential (current implementation)...');
  final seqStart = DateTime.now();
  for (int x = 0; x < fetched.length; x++) {
    final int count = offset + x;
    if (count < favouritesCount) {
      final String resp = await sendBooruItem(fetched.elementAt(x), favouritesCount, count);
    }
  }
  final seqDuration = DateTime.now().difference(seqStart);
  print('Sequential time: ${seqDuration.inMilliseconds} ms');

  print('Testing concurrent (Future.wait)...');
  final concStart = DateTime.now();
  final List<Future<String>> futures = [];
  for (int x = 0; x < fetched.length; x++) {
    final int count = offset + x;
    if (count < favouritesCount) {
      futures.add(sendBooruItem(fetched.elementAt(x), favouritesCount, count));
    }
  }
  final responses = await Future.wait(futures);
  final concDuration = DateTime.now().difference(concStart);
  print('Concurrent time: ${concDuration.inMilliseconds} ms');
}
