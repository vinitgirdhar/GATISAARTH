// Frontend-only illustrations. These values are not navigation-engine measurements.
export const outageDurations = [10, 20, 30, 45, 60];
export const faultPresets = [
  ["GNSS outage", "Motion estimate continues; uncertainty expands", 1.4],
  ["GNSS position jump (+120 m)", "Position innovation rejected", 0.4],
  ["GNSS integrity anomaly", "Integrity warning; suspect fixes withheld", 0.8],
  [
    "Gyro bias (+0.5 deg/s)",
    "Heading error accumulates; no immediate alarm",
    2.2,
  ],
  ["Accelerometer bias (+0.3 m/s²)", "Velocity estimate diverges", 2.8],
  ["Magnetometer disturbance (×2)", "Magnetic heading excluded", 0.7],
  ["Gyro dropout", "Sensor freshness warning", 1.9],
  ["Accelerometer dropout", "Motion estimate degraded", 2.4],
  ["GNSS fixes delayed (+800 ms)", "Stale fixes withheld", 1.1],
];

export function signalState(kind, seconds, duration = 30) {
  if (!kind) return { signal: "locked", accuracy: 5, speed: 45 };
  if (kind === "canyon") {
    const cycle = seconds % 8;
    return {
      signal: cycle < 5 ? "lost" : "degraded",
      accuracy: Math.round(12 + cycle * 2 + seconds * 0.15),
      speed: 30,
    };
  }
  const recovering = kind === "timed" && seconds >= duration;
  return {
    signal: recovering ? "recovering" : "lost",
    accuracy: recovering
      ? Math.max(
          5,
          Math.round((14 + duration * 1.1) * (1 - (seconds - duration) / 3)),
        )
      : Math.round(14 + seconds * 1.1),
    speed: 45,
  };
}

export function outageResult(kind, seconds, distanceM) {
  const errorM =
    Math.round((1.5 + seconds * (kind === "canyon" ? 0.28 : 0.42)) * 10) / 10;
  return {
    source:
      "Illustrative browser simulation — not an engine or field measurement",
    scenario: kind,
    seconds: Math.round(seconds),
    distanceM: Math.round(distanceM),
    errorM,
    driftPct: distanceM > 0 ? +((errorM / distanceM) * 100).toFixed(1) : null,
    alongTrackM: +(errorM * 0.8).toFixed(1),
    crossTrackM: +(errorM * 0.6).toFixed(1),
    initialSigmaM: 5,
    peakSigmaM: Math.round(14 + seconds * 1.1),
    recoveryJumpM: errorM,
  };
}
