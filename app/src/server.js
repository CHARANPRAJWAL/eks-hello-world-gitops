'use strict';

const { createServer } = require('node:http');

const config = require('./config');
const { logger } = require('./logger');
const { createApp } = require('./app');

// Owned here, read by the /readyz handler.
const state = { ready: false };

const server = createServer(createApp({ state }));

// Slightly above the load balancer idle timeout so the LB, not the app, is the
// side that closes idle connections. The reverse causes sporadic 502s when a
// connection is reused microseconds after the server decided to drop it.
server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;

server.listen(config.port, () => {
  state.ready = true;
  logger.info({ port: config.port }, 'listening');
});

server.on('error', (err) => {
  logger.fatal({ err }, 'server failed to start');
  process.exit(1);
});

let shuttingDown = false;

/**
 * Graceful shutdown, in the order that actually avoids dropped requests:
 *
 *   1. Fail readiness. Kubernetes notices and removes this pod from the
 *      Service endpoints.
 *   2. Keep serving for drainDelayMs. Endpoint removal is eventually
 *      consistent: kube-proxy, the AWS load balancer and any client-side
 *      connection pool all need time to stop routing here. Closing the
 *      listener immediately on SIGTERM is the single most common cause of
 *      5xx spikes during a deploy.
 *   3. Stop accepting new connections and let in-flight requests finish.
 *   4. Hard-exit if step 3 overruns, so a stuck request cannot hold the pod
 *      open until the kubelet SIGKILLs it.
 */
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;

  state.ready = false;
  logger.info({ signal, drainDelayMs: config.drainDelayMs }, 'shutdown: draining');

  const forceExit = setTimeout(() => {
    logger.error('shutdown: timed out with connections still open, forcing exit');
    process.exit(1);
  }, config.shutdownTimeoutMs);

  setTimeout(() => {
    logger.info('shutdown: closing listener');
    server.close((err) => {
      clearTimeout(forceExit);
      if (err) {
        logger.error({ err }, 'shutdown: error closing server');
        process.exit(1);
      }
      logger.info('shutdown: complete');
      process.exit(0);
    });
  }, config.drainDelayMs);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// A promise rejection or thrown error that reaches here means the process is in
// an unknown state. Log it and die: the deployment will restart us, and a
// CrashLoop is far easier to detect than a zombie serving corrupt responses.
process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'unhandled promise rejection');
  process.exit(1);
});

process.on('uncaughtException', (err) => {
  logger.fatal({ err }, 'uncaught exception');
  process.exit(1);
});



