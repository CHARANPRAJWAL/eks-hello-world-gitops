'use strict';

const pino = require('pino');
const config = require('./config');

/**
 * Single-line JSON to stdout. No file handles, no log rotation, no sidecar
 * assumptions: the container runtime captures stdout and the cluster's log
 * agent ships it. This is the only logging contract a container should have.
 */
const logger = pino({
  level: config.logLevel,
  base: {
    service: config.serviceName,
    version: config.version,
    env: config.env,
  },
  // Emit `"level":"info"` rather than pino's numeric default, so log backends
  // can filter on the string without a lookup table.
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  // Defensive: these headers should never reach logs even by accident.
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'req.headers["set-cookie"]',
      'req.headers["x-api-key"]',
    ],
    censor: '[redacted]',
  },
});

module.exports = { logger };
