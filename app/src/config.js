'use strict';

/**
 * Configuration is read from the environment exactly once, at startup, and
 * validated immediately. Failing fast here means a misconfigured pod crashes
 * on boot and is caught by the deployment rollout, rather than serving broken
 * traffic silently.
 */

function requireInt(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`env ${name} must be a non-negative integer, got "${raw}"`);
  }
  return parsed;
}

const env = process.env.NODE_ENV || 'development';

const config = {
  env,
  serviceName: process.env.SERVICE_NAME || 'hello-world',

  // Injected by the Helm chart from the image tag so logs and metrics can be
  // correlated to a specific release.
  version: process.env.APP_VERSION || 'dev',

  port: requireInt('PORT', 8080),

  // Silence logs during tests; otherwise every assertion prints a request line.
  logLevel: process.env.LOG_LEVEL || (env === 'test' ? 'silent' : 'info'),

  // How long to keep serving after SIGTERM before closing the listener. This
  // covers the window where Kubernetes has sent SIGTERM but kube-proxy and the
  // load balancer have not yet removed this pod from their endpoint lists.
  drainDelayMs: requireInt('DRAIN_DELAY_MS', 5000),

  // Hard ceiling on shutdown. Must stay below the pod's
  // terminationGracePeriodSeconds or the kubelet SIGKILLs us mid-request.
  shutdownTimeoutMs: requireInt('SHUTDOWN_TIMEOUT_MS', 15000),

  message: process.env.GREETING || 'Hello World',
};

module.exports = config;
