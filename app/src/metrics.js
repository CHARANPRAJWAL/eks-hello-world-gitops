'use strict';

const promClient = require('prom-client');
const config = require('./config');

/**
 * Metrics live on a per-instance Registry rather than prom-client's global
 * default. Two reasons: tests can build several app instances without
 * "metric already registered" collisions, and nothing can leak metrics into
 * this service's exposition from an unrelated module.
 */
function createMetrics({ collectDefault = config.env !== 'test' } = {}) {
  const registry = new promClient.Registry();

  // Labels attached to every series, so Grafana can slice by release without
  // each metric having to remember to carry the version itself.
  registry.setDefaultLabels({
    service: config.serviceName,
    version: config.version,
  });

  if (collectDefault) {
    // Process CPU/memory/handles, event loop lag, GC, Node version.
    promClient.collectDefaultMetrics({ register: registry });
  }

  const httpRequestsTotal = new promClient.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests handled, by method, route and status code',
    labelNames: ['method', 'route', 'status_code'],
    registers: [registry],
  });

  const httpRequestDuration = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request latency in seconds',
    labelNames: ['method', 'route', 'status_code'],
    // Buckets chosen around this service's expected sub-100ms latency, with a
    // long tail so a pathological request is still visible rather than being
    // dumped into +Inf. Bucket edges must include the SLO threshold (0.25s) or
    // the burn-rate alert cannot be computed accurately.
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
    registers: [registry],
  });

  const httpRequestsInFlight = new promClient.Gauge({
    name: 'http_requests_in_flight',
    help: 'Number of HTTP requests currently being served',
    registers: [registry],
  });

  /**
   * Express middleware recording count and latency for every request.
   *
   * The `route` label uses the matched Express route pattern (`/users/:id`),
   * never the raw URL. Using the raw path would let any client mint unbounded
   * label values by hitting random URLs and blow up Prometheus cardinality,
   * which is a genuine availability risk for the monitoring stack.
   */
  function middleware(req, res, next) {
    const startedAt = process.hrtime.bigint();
    httpRequestsInFlight.inc();

    res.on('finish', () => {
      const seconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
      const labels = {
        method: req.method,
        route: req.route?.path ?? 'unmatched',
        status_code: String(res.statusCode),
      };

      httpRequestsInFlight.dec();
      httpRequestsTotal.inc(labels);
      httpRequestDuration.observe(labels, seconds);
    });

    next();
  }

  // Express 4 does not catch rejections from async handlers, so failures are
  // forwarded to next() explicitly. A scrape that 500s is far better than a
  // process-killing unhandled rejection.
  async function handler(_req, res, next) {
    try {
      res.set('Content-Type', registry.contentType);
      res.end(await registry.metrics());
    } catch (err) {
      next(err);
    }
  }

  return { registry, middleware, handler };
}

module.exports = { createMetrics };
