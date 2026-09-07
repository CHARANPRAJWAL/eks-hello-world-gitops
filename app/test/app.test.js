'use strict';

const request = require('supertest');

const { createApp } = require('../src/app');
const { createMetrics } = require('../src/metrics');

/**
 * Each test gets a fresh app and a fresh metrics registry so assertions on
 * counter values are not polluted by earlier tests. Default process metrics are
 * disabled here: they install an event-loop monitor we do not want per-test.
 */
function build({ ready = true } = {}) {
  const state = { ready };
  const metrics = createMetrics({ collectDefault: false });
  return { app: createApp({ state, metrics }), state };
}

describe('createApp defaults', () => {
  it('is constructible with no arguments, defaulting to ready', async () => {
    // Exercises the default-argument paths. Every other test injects state and
    // metrics explicitly, so without this the defaults are never executed and a
    // typo in them would only surface in production.
    const app = createApp();

    const res = await request(app).get('/readyz');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ready' });
  });

  it('builds its own metrics registry when none is supplied', async () => {
    const app = createApp();

    await request(app).get('/');
    const res = await request(app).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.text).toContain('http_requests_total');
  });
});

describe('GET /', () => {
  it('returns Hello World', async () => {
    const { app } = build();

    const res = await request(app).get('/');

    expect(res.status).toBe(200);
    expect(res.text).toBe('Hello World');
    expect(res.headers['content-type']).toMatch(/text\/plain/);
  });

  it('does not advertise the framework', async () => {
    const { app } = build();

    const res = await request(app).get('/');

    expect(res.headers['x-powered-by']).toBeUndefined();
  });
});

describe('GET /healthz', () => {
  it('reports ok while the process is alive', async () => {
    const { app } = build();

    const res = await request(app).get('/healthz');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });

  it('stays ok even while draining, so the pod is not restarted mid-shutdown', async () => {
    const { app, state } = build();
    state.ready = false;

    const res = await request(app).get('/healthz');

    expect(res.status).toBe(200);
  });
});

describe('GET /readyz', () => {
  it('reports ready when serving', async () => {
    const { app } = build();

    const res = await request(app).get('/readyz');

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ready' });
  });

  it('returns 503 once draining so Kubernetes removes the endpoint', async () => {
    const { app, state } = build();
    state.ready = false;

    const res = await request(app).get('/readyz');

    expect(res.status).toBe(503);
    expect(res.body).toEqual({ status: 'draining' });
  });
});

describe('unknown routes', () => {
  it('returns a 404 without leaking internals', async () => {
    const { app } = build();

    const res = await request(app).get('/does-not-exist');

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'not found' });
  });
});

describe('GET /metrics', () => {
  it('exposes the Prometheus text format', async () => {
    const { app } = build();

    const res = await request(app).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
    expect(res.text).toContain('# HELP http_requests_total');
  });

  it('counts application requests with method, route and status labels', async () => {
    const { app } = build();

    await request(app).get('/');
    const res = await request(app).get('/metrics');

    // Asserted label-by-label rather than with one regex, so the test does not
    // depend on the order the client happens to serialise labels in.
    const line = res.text
      .split('\n')
      .find((l) => l.startsWith('http_requests_total{'));

    expect(line).toBeDefined();
    expect(line).toContain('method="GET"');
    expect(line).toContain('route="/"');
    expect(line).toContain('status_code="200"');
    expect(line).toMatch(/\s1$/);
  });

  it('records latency observations for application requests', async () => {
    const { app } = build();

    await request(app).get('/');
    const res = await request(app).get('/metrics');

    const countLine = res.text
      .split('\n')
      .find((l) => l.startsWith('http_request_duration_seconds_count{'));

    expect(res.text).toContain('http_request_duration_seconds_bucket');
    expect(countLine).toBeDefined();
    expect(countLine).toContain('route="/"');
    expect(countLine).toMatch(/\s1$/);
  });

  it('labels unmatched routes with a fixed value to bound cardinality', async () => {
    const { app } = build();

    await request(app).get('/some/random/path');
    const res = await request(app).get('/metrics');

    expect(res.text).toMatch(/route="unmatched"/);
    expect(res.text).not.toContain('/some/random/path');
  });

  it('excludes probe and scrape traffic from the RED metrics', async () => {
    const { app } = build();

    await request(app).get('/healthz');
    await request(app).get('/readyz');
    const res = await request(app).get('/metrics');

    expect(res.text).not.toContain('route="/healthz"');
    expect(res.text).not.toContain('route="/readyz"');
    expect(res.text).not.toContain('route="/metrics"');
  });

  it('tags every series with the service and version for release correlation', async () => {
    const { app } = build();

    await request(app).get('/');
    const res = await request(app).get('/metrics');

    expect(res.text).toContain('service="hello-world"');
    expect(res.text).toContain('version="dev"');
  });
});
