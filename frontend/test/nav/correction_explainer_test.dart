import 'package:flutter_test/flutter_test.dart';
import 'package:gatisaarth/core/nav/ekf/navigation_filter.dart';
import 'package:gatisaarth/core/nav/model/correction_explainer.dart';

MeasurementResult _r(String name, MeasurementOutcome o,
        {double? nis, double? gate}) =>
    MeasurementResult(name: name, outcome: o, nis: nis, gateLimit: gate);

void main() {
  test('a refused GNSS fix is explained by how far it disagreed', () {
    final e = CorrectionExplainer()
      ..record(_r('gnss_position', MeasurementOutcome.rejectedByGate,
          nis: 41.2, gate: 9.21), 1000000);
    final x = e.explain(nowUs: 1500000).single;
    expect(x.source, 'GNSS position');
    expect(x.used, isFalse);
    expect(x.reason, startsWith('Refused'));
    expect(x.reason, contains('2.1×'));
  });

  test('an accepted fix says it agreed, and counts are kept per source', () {
    final e = CorrectionExplainer();
    for (var i = 0; i < 3; i++) {
      e.record(_r('gnss_position', MeasurementOutcome.accepted, nis: 1.1, gate: 9.21),
          i * 1000000);
    }
    e.record(_r('nhc', MeasurementOutcome.accepted), 3000000);
    final list = e.explain(nowUs: 3000000);
    final gnss = list.firstWhere((x) => x.source == 'GNSS position');
    expect(gnss.used, isTrue);
    expect(gnss.accepted, 3);
    expect(gnss.reason, contains('agreed'));
    expect(list.firstWhere((x) => x.name == 'nhc').reason,
        contains('cannot slide sideways'));
  });

  test('sources silent for longer than the window drop out', () {
    final e = CorrectionExplainer(window: const Duration(seconds: 10))
      ..record(_r('zupt', MeasurementOutcome.accepted), 0)
      ..record(_r('nhc', MeasurementOutcome.accepted), 20000000);
    final names = e.explain(nowUs: 20000000).map((x) => x.name);
    expect(names, ['nhc']);
  });

  test('an unknown measurement still gets a readable line', () {
    final e = CorrectionExplainer()
      ..record(_r('something_new', MeasurementOutcome.accepted), 0);
    expect(e.explain(nowUs: 0).single.source, 'something new');
  });
}
