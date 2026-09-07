'use strict';

const express = require('express');
const pinoHttp = require('pino-http');

const config = require('./config');
const { logger } = require('./logger');
const { createMetrics } = require('./metrics');

const OPERATIONAL_PATHS = new Set(['/healthz', '/readyz', '/metrics']);

/**
 * Builds the Express app. Kept separate from server.js so tests can exercise
 * the routes with supertest without binding a port or installing signal
 * handlers.
 *
 * @param {object}  options
 * @param {{ready: boolean}} options.state  Mutable readiness flag owned by the
 *   server. Passed in rather than module-global so a test can flip readiness
 *   and assert on /readyz.
 */
function createApp({ state = { ready: true }, metrics = createMetrics() } = {}) {
  const app = express();

  // Do not advertise the framework. Free, and one less hint for a scanner.
  app.disable('x-powered-by');

  // Behind an AWS load balancer, so honour X-Forwarded-* for the client IP.
  app.set('trust proxy', true);

  app.use(
    pinoHttp({
      logger,
      // Probes and scrapes run every few seconds. Logging them buries real
      // traffic and costs money in log ingestion for zero diagnostic value.
      autoLogging: {
        ignore: (req) => OPERATIONAL_PATHS.has(req.url),
      },
    }),
  );

  /**
   * Liveness: is this process still functioning, or does it need a restart?
   *
   * Deliberately checks nothing external. If liveness depended on a database,
   * a database blip would fail the probe on every pod at once and the kubelet
   * would restart the entire fleet, converting a degraded dependency into a
   * full outage. Liveness answers "is this process wedged", nothing more.
   */
  app.get('/healthz', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  /**
   * Readiness: should this pod receive traffic right now?
   *
   * Flipped to false at the very start of shutdown so Kubernetes removes this
   * pod from the Service endpoints before the listener closes. That ordering
   * is what makes rolling deploys drop zero requests.
   */
  app.get('/readyz', (_req, res) => {
    if (!state.ready) {
      return res.status(503).json({ status: 'draining' });
    }
    return res.status(200).json({ status: 'ready' });
  });

  app.get('/metrics', metrics.handler);

  // Registered after the operational endpoints so probe and scrape traffic is
  // excluded from the RED metrics below. Those metrics drive the SLO burn-rate
  // alert, and a constant flood of successful self-checks would dilute the
  // error ratio badly enough to hide a real customer-facing failure.
  app.use(metrics.middleware);

  app.get('/', (_req, res) => {
    res.status(200).type('text/plain').send(config.message);
  });

  app.use((_req, res) => {
    res.status(404).json({ error: 'not found' });
  });

  // Express identifies error handlers by arity, so the unused 4th parameter is
  // required. It is underscore-prefixed to satisfy the lint rule.
  app.use((err, req, res, _next) => {
    req.log.error({ err }, 'unhandled request error');
    // Never leak stack traces or internal messages to the caller.
    res.status(500).json({ error: 'internal server error' });
  });

  return app;
}

module.exports = { createApp };
