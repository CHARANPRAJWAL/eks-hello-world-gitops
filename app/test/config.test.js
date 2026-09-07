'use strict';

/**
 * config.js reads process.env once at require time, so every case needs a fresh
 * module registry. The environment is snapshotted and restored around each load
 * so cases cannot leak into one another.
 */
function loadConfig(overrides = {}) {
  const original = process.env;
  process.env = { ...original };

  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    jest.resetModules();
    return require('../src/config');
  } finally {
    process.env = original;
  }
}

describe('defaults', () => {
  it('supplies working defaults with an empty environment', () => {
    const config = loadConfig({
      PORT: undefined,
      SERVICE_NAME: undefined,
      APP_VERSION: undefined,
      GREETING: undefined,
      LOG_LEVEL: undefined,
      DRAIN_DELAY_MS: undefined,
      SHUTDOWN_TIMEOUT_MS: undefined,
    });

    expect(config.port).toBe(8080);
    expect(config.serviceName).toBe('hello-world');
    expect(config.version).toBe('dev');
    expect(config.message).toBe('Hello World');
    expect(config.drainDelayMs).toBe(5000);
    expect(config.shutdownTimeoutMs).toBe(15_000);
  });

  it('keeps the drain delay below the shutdown timeout', () => {
    // If this inverts, the force-exit fires before the listener ever closes and
    // in-flight requests are killed on every deploy.
    const config = loadConfig();

    expect(config.drainDelayMs).toBeLessThan(config.shutdownTimeoutMs);
  });
});

describe('overrides', () => {
  it('reads the port from the environment', () => {
    expect(loadConfig({ PORT: '3000' }).port).toBe(3000);
  });

  it('accepts zero for the drain delay', () => {
    expect(loadConfig({ DRAIN_DELAY_MS: '0' }).drainDelayMs).toBe(0);
  });

  it('reads service identity and greeting from the environment', () => {
    const config = loadConfig({
      SERVICE_NAME: 'checkout',
      APP_VERSION: '1.4.2',
      GREETING: 'Hei Maailma',
    });

    expect(config.serviceName).toBe('checkout');
    expect(config.version).toBe('1.4.2');
    expect(config.message).toBe('Hei Maailma');
  });
});

describe('environment-dependent logging', () => {
  it('silences logs under test so assertions are not buried in output', () => {
    expect(loadConfig({ NODE_ENV: 'test', LOG_LEVEL: undefined }).logLevel).toBe('silent');
  });

  it('defaults to info outside of test', () => {
    const config = loadConfig({ NODE_ENV: undefined, LOG_LEVEL: undefined });

    expect(config.env).toBe('development');
    expect(config.logLevel).toBe('info');
  });

  it('lets an explicit log level win', () => {
    expect(loadConfig({ LOG_LEVEL: 'debug' }).logLevel).toBe('debug');
  });
});

describe('validation', () => {
  // The point of failing at boot: a bad value crashes the pod immediately and
  // the rollout stalls with a clear reason, instead of the service coming up
  // listening on NaN or shutting down after zero milliseconds.
  it.each([
    ['not a number', 'abc'],
    ['a negative value', '-1'],
    ['a fractional value', '1.5'],
  ])('rejects %s', (_label, value) => {
    expect(() => loadConfig({ PORT: value })).toThrow(
      /env PORT must be a non-negative integer/,
    );
  });

  it('names the offending variable so the failure is self-diagnosing', () => {
    expect(() => loadConfig({ SHUTDOWN_TIMEOUT_MS: 'soon' })).toThrow(
      /env SHUTDOWN_TIMEOUT_MS must be a non-negative integer, got "soon"/,
    );
  });

  it('treats an empty value as unset rather than invalid', () => {
    // Kubernetes injects empty strings for absent ConfigMap keys, so an empty
    // value must fall back rather than crash the pod.
    expect(loadConfig({ PORT: '' }).port).toBe(8080);
  });
});
