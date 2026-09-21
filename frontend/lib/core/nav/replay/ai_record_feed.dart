import '../navigation_engine.dart';
import 'drive_log.dart';

/// Hands the model outputs of an `ai` [record] to [engine]: the disturbance and
/// the fusion confidence first, then the speed, so the speed gate sees the noise
/// scaling that came with it. Replay and the outage benchmark both go through
/// this, in the order the live engine saw the same calls, which is what keeps a
/// replay bit-identical to the run that recorded it.
void feedAiRecord(NavigationEngine engine, DriveRecord record) {
  final disturbance = record.disturbance;
  final fusion = record.fusion;
  final speed = record.aiSpeed;
  if (disturbance != null) engine.onDisturbance(disturbance);
  if (fusion != null) engine.onFusionConfidence(fusion);
  if (speed != null) engine.onAiSpeed(speed);
}
