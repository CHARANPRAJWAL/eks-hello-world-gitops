'use strict';

module.exports = {
  testEnvironment: 'node',
  collectCoverageFrom: [
    'src/**/*.js',
    // Excluded deliberately: server.js binds a port and installs process
    // signal handlers, so it is verified by the container smoke test and the
    // rolling-deploy validation in Phase 8 rather than by unit tests.
    '!src/server.js',
  ],
  coverageThreshold: {
    global: {
      branches: 80,
      functions: 80,
      lines: 85,
      statements: 85,
    },
  },
  coverageReporters: ['text-summary', 'lcov'],
  // A hanging handle should fail CI loudly, not stall the job until timeout.
  detectOpenHandles: false,
  testTimeout: 10_000,
};
