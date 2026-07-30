import { mock } from 'bun:test';

mock.module('ioredis', () => {
  function Redis() {
    return {
      get: () => Promise.resolve(null),
      set: () => Promise.resolve('OK'),
      setex: () => Promise.resolve('OK'),
      del: () => Promise.resolve(1),
      expire: () => Promise.resolve(1),
      quit: () => Promise.resolve('OK'),
      publish: () => Promise.resolve(0),
      subscribe: () => Promise.resolve(),
      on: () => {},
      duplicate: function() { return this; },
    };
  }
  Redis.prototype = {};
  return { default: Redis };
});
