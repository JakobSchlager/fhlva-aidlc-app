// Beer Tracker load driver (k6).
//
// Replays the frontend's main journey against the public API. See README.md
// for profiles and environment variables. Run with, for example:
//   k6 run -e PROFILE=smoke -e BASE_URL=http://localhost:8080 script.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';
import exec from 'k6/execution';
import { buildScenario } from './profiles.js';

const PROFILE = __ENV.PROFILE || 'smoke';
const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const URLS = {
  auth: __ENV.AUTH_URL || BASE_URL,
  tracking: __ENV.TRACKING_URL || BASE_URL,
  statistics: __ENV.STATISTICS_URL || BASE_URL,
  notifications: __ENV.NOTIFICATIONS_URL || BASE_URL,
};
const USERS = Math.min(Number(__ENV.USERS || 20), 500);
const WRITE_RATIO = Number(__ENV.WRITE_RATIO || 0.3);
const PASSWORD = 'load-test-password';
// A request slower than this counts as failed, so a hanging dependency shows up as an
// error-rate violation instead of a stuck run.
const REQUEST_TIMEOUT = __ENV.REQUEST_TIMEOUT || '10s';
const SLO = JSON.parse(open(__ENV.SLO_FILE || './slo.json'));

// --- Options ------------------------------------------------------------------

function thresholds() {
  // The gate profile stops as soon as an SLO is clearly violated.
  const abort = PROFILE === 'gate';
  const rule = (threshold) =>
    abort ? { threshold, abortOnFail: true, delayAbortEval: '10s' } : threshold;

  const t = {
    // Smoke must be clean; the other profiles use the group's error budget.
    http_req_failed: [rule(PROFILE === 'smoke' ? 'rate==0' : `rate<${SLO.errorRate}`)],
  };
  for (const [step, slo] of Object.entries(SLO.steps || {})) {
    const rules = [];
    if (slo.p95) rules.push(rule(`p(95)<${slo.p95}`));
    if (slo.p99) rules.push(rule(`p(99)<${slo.p99}`));
    if (rules.length) t[`http_req_duration{name:${step}}`] = rules;
  }
  if (PROFILE === 'newcomers') {
    // Not SLOs: always-true thresholds, only so the summary lists these steps.
    for (const step of ['auth_register', 'auth_login', 'statistics_me_first']) {
      t[`http_req_duration{name:${step}}`] = ['max>=0'];
    }
  }
  return t;
}

export const options = {
  scenarios: { [PROFILE]: buildScenario(PROFILE, __ENV) },
  thresholds: thresholds(),
  // Room for the user pool even when every setup request runs into REQUEST_TIMEOUT.
  setupTimeout: '5m',
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

// --- Helpers ------------------------------------------------------------------

let runName = __ENV.RUN_NAME || PROFILE;

function params(name, token, extra = {}) {
  const headers = {
    'Content-Type': 'application/json',
    // Dynatrace load-test tagging: VU, source, test name, script, step.
    'x-dynatrace-test': `VU=${exec.vu.idInTest};SI=k6;LTN=${runName};LSN=${extra.script || 'beertracker-journey'};TSN=${name};`,
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  return { headers, timeout: REQUEST_TIMEOUT, tags: { name, ...(extra.tags || {}) } };
}

function ok(res, step) {
  return check(res, { [`${step} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
}

function register(email, name = 'auth_register', extra) {
  return http.post(`${URLS.auth}/auth/register`, JSON.stringify({ email, password: PASSWORD }), params(name, null, extra));
}

function login(email, name = 'auth_login', extra) {
  const res = http.post(`${URLS.auth}/auth/login`, JSON.stringify({ email, password: PASSWORD }), params(name, null, extra));
  return res.status === 200 ? res.json('accessToken') : null;
}

// Expiry (epoch seconds) from the JWT's exp claim.
function expiry(token) {
  const payload = token.split('.')[1];
  return JSON.parse(encoding.b64decode(payload, 'rawurl', 's')).exp;
}

function createEntry(token, name = 'tracking_create', extra) {
  const body = {
    beerName: `Load Lager ${Math.floor(Math.random() * 10)}`,
    volumeMl: 500,
    abv: 5.0,
    timestamp: new Date().toISOString(),
  };
  return http.post(`${URLS.tracking}/tracking/entries`, JSON.stringify(body), params(name, token, extra));
}

// --- Setup: create the user pool outside the measured load --------------------

export function setup() {
  const stamp = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);
  const runId = `${stamp}-${Math.floor(Math.random() * 1e4)}`;
  runName = __ENV.RUN_NAME || `${PROFILE}-${stamp}`;
  if (PROFILE === 'newcomers') return { runId, runName, users: [] };

  const setupTag = { tags: { phase: 'setup' } };
  const users = [];
  for (let n = 0; n < USERS; n++) {
    const email = `load-${runId}-${n}@example.com`;
    const reg = register(email, 'setup_register', setupTag);
    const token = reg.status === 201 ? login(email, 'setup_login', setupTag) : null;
    if (!token) {
      throw new Error(`setup: could not register/login ${email} (status ${reg.status}); is BASE_URL right?`);
    }
    // One entry and one statistics call per user, so the measured load starts
    // with warm statistics caches instead of the first-access refresh path.
    createEntry(token, 'setup_create', setupTag);
    http.get(`${URLS.statistics}/statistics/me`, params('setup_statistics', token, setupTag));
    users.push({ email, token, exp: expiry(token) });
  }
  return { runId, runName, users };
}

// --- Per-VU token handling ----------------------------------------------------

let session = null;

// Returns a valid token for this VU's pool user. Tokens from setup() are reused;
// a VU renews its own token at a random point in the last 20–30 % of its life,
// so renewals in long runs are spread out instead of arriving as one burst.
function tokenFor(data) {
  if (!session) {
    const user = data.users[(exec.vu.idInTest - 1) % data.users.length];
    session = { ...user, renewAt: null };
  }
  if (session.renewAt === null) {
    const now = Date.now() / 1000;
    const life = session.exp - now;
    session.renewAt = now + life * (0.7 + Math.random() * 0.1);
  }
  if (Date.now() / 1000 >= session.renewAt) {
    const token = login(session.email, 'auth_renew');
    if (token) {
      session.token = token;
      session.exp = expiry(token);
      session.renewAt = null;
    }
  }
  return session.token;
}

// --- Scenarios ------------------------------------------------------------------

// One visit to the dashboard and history, as the frontend makes it.
export function visit(data) {
  runName = data.runName;
  const token = tokenFor(data);

  const steps = [
    ['statistics_me', () => http.get(`${URLS.statistics}/statistics/me`, params('statistics_me', token))],
    ['statistics_trend', () => http.get(`${URLS.statistics}/statistics/me/trend?days=30`, params('statistics_trend', token))],
    ['tracking_list', () => http.get(`${URLS.tracking}/tracking/entries?page=0&size=20`, params('tracking_list', token))],
  ];
  if (Math.random() < WRITE_RATIO) {
    steps.push(['tracking_create', () => createEntry(token)]);
  }
  steps.push(
    ['statistics_global', () => http.get(`${URLS.statistics}/statistics/global`, params('statistics_global', token))],
    ['notifications_list', () => http.get(`${URLS.notifications}/notifications/warnings`, params('notifications_list', token))],
  );

  for (const [step, call] of steps) {
    const res = call();
    ok(res, step);
    if (res.status === 401) session.renewAt = 0; // token rejected: renew next time
  }

  if (PROFILE === 'smoke') sleep(1);
}

// A brand-new user: register, log in, log one beer, open statistics.
export function newcomer(data) {
  runName = data.runName;
  const extra = { script: 'beertracker-newcomer' };
  const email = `load-${data.runId}-new-${exec.vu.idInTest}-${exec.vu.iterationInScenario}@example.com`;

  const reg = register(email, 'auth_register', extra);
  if (!ok(reg, 'auth_register')) return;
  const token = login(email, 'auth_login', extra);
  if (!check(token, { 'auth_login token': (t) => !!t })) return;
  ok(createEntry(token, 'tracking_create', extra), 'tracking_create');
  ok(http.get(`${URLS.statistics}/statistics/me`, params('statistics_me_first', token, extra)), 'statistics_me_first');
}
