// Load profiles for the Beer Tracker k6 driver.
//
// Each profile turns the environment variables RATE, DURATION and SPIKE_FACTOR
// into one k6 scenario. Every profile has hard caps on duration, rate and VUs,
// so a mistyped parameter cannot produce an unbounded run.

const MAX_RATE = 200; // iterations per second
const MAX_VUS = 300;

// Parses k6-style durations such as "30s", "5m", "1h30m" into seconds.
export function parseDuration(value) {
  const re = /(\d+)(h|m|s)/g;
  let seconds = 0;
  let matched = '';
  let m;
  while ((m = re.exec(value)) !== null) {
    seconds += Number(m[1]) * { h: 3600, m: 60, s: 1 }[m[2]];
    matched += m[0];
  }
  if (matched !== value || seconds === 0) {
    throw new Error(`Invalid duration "${value}" (expected e.g. 30s, 5m, 1h30m)`);
  }
  return seconds;
}

function capDuration(name, value, capSeconds) {
  const seconds = parseDuration(value);
  if (seconds > capSeconds) {
    if (__VU === 0) console.warn(`DURATION ${value} exceeds the ${name} cap of ${capSeconds}s; capping it`);
    return `${capSeconds}s`;
  }
  return `${seconds}s`;
}

function capNumber(label, value, cap) {
  if (!(value > 0)) {
    throw new Error(`${label} must be a positive number, got "${value}"`);
  }
  if (value > cap) {
    if (__VU === 0) console.warn(`${label} ${value} exceeds the cap of ${cap}; capping it`);
    return cap;
  }
  return value;
}

export function buildScenario(profile, env) {
  const rate = capNumber('RATE', Number(env.RATE || 2), MAX_RATE);
  const spikeFactor = Number(env.SPIKE_FACTOR || 5);
  const peak = capNumber('RATE × SPIKE_FACTOR', Math.round(rate * spikeFactor), MAX_RATE);
  const vus = (n) => Math.min(MAX_VUS, Math.max(5, n));

  const profiles = {
    // One VU walking the journey: does the script, auth and every step work?
    smoke: () => ({
      executor: 'constant-vus',
      exec: 'visit',
      vus: 1,
      duration: capDuration('smoke', env.DURATION || '30s', 120),
    }),

    // Steady state at RATE visits per second (open model).
    baseline: () => ({
      executor: 'constant-arrival-rate',
      exec: 'visit',
      rate,
      timeUnit: '1s',
      duration: capDuration('baseline', env.DURATION || '5m', 4 * 3600),
      preAllocatedVUs: vus(rate * 2),
      maxVUs: vus(rate * 20),
    }),

    // Baseline, then a fast ramp to RATE × SPIKE_FACTOR, hold, and back down.
    spike: () => ({
      executor: 'ramping-arrival-rate',
      exec: 'visit',
      startRate: rate,
      timeUnit: '1s',
      stages: [
        { target: rate, duration: '1m' },
        { target: peak, duration: '30s' },
        { target: peak, duration: capDuration('spike hold', env.DURATION || '5m', 30 * 60) },
        { target: rate, duration: '30s' },
        { target: rate, duration: '1m' },
      ],
      preAllocatedVUs: vus(peak * 2),
      maxVUs: vus(peak * 20),
    }),

    // Like spike, but each iteration is a brand-new user: register, log in,
    // log one beer, open statistics. Reaches the first-access code paths.
    newcomers: () => ({
      executor: 'ramping-arrival-rate',
      exec: 'newcomer',
      startRate: rate,
      timeUnit: '1s',
      stages: [
        { target: peak, duration: '30s' },
        { target: peak, duration: capDuration('newcomers hold', env.DURATION || '3m', 30 * 60) },
        { target: 0, duration: '30s' },
      ],
      preAllocatedVUs: vus(peak * 2),
      maxVUs: vus(peak * 20),
    }),

    // Short check for pipelines and canaries; thresholds abort on failure.
    gate: () => ({
      executor: 'constant-arrival-rate',
      exec: 'visit',
      rate,
      timeUnit: '1s',
      duration: capDuration('gate', env.DURATION || '1m', 120),
      preAllocatedVUs: vus(rate * 2),
      maxVUs: vus(rate * 10),
    }),
  };

  if (!profiles[profile]) {
    throw new Error(
      `Unknown PROFILE "${profile}". Valid profiles: ${Object.keys(profiles).join(', ')}`,
    );
  }
  return profiles[profile]();
}
