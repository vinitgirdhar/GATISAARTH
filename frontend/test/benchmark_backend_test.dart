import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/features/benchmark/data/benchmark_backend.dart';

void main() {
  group('friendlyDriveName', () {
    test('turns a recorder file name into the phone-local date and time', () {
      expect(friendlyDriveName('drive-20260920T155523266723.jsonl'),
          '20 Sep 2026, 15:55');
      expect(friendlyDriveName('drive-20260105T070102000000.jsonl'),
          '5 Jan 2026, 07:01');
    });

    test('leaves any other name alone rather than inventing a date', () {
      expect(friendlyDriveName('ride.jsonl'), 'ride.jsonl');
      expect(friendlyDriveName('drive-20261320T155523.jsonl'),
          'drive-20261320T155523.jsonl');
    });
  });
}
