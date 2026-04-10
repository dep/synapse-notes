const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Polyfills for Node.js core modules required by isomorphic-git
config.resolver.extraNodeModules = {
  ...config.resolver.extraNodeModules,
  crypto: require.resolve('crypto-browserify'),
  stream: require.resolve('stream-browserify'),
  buffer: require.resolve('buffer'),
  util: require.resolve('util'),
  events: require.resolve('events'),
  path: require.resolve('path-browserify'),
  os: require.resolve('os-browserify'),
  url: require.resolve('url'),
  assert: require.resolve('assert'),
  punycode: require.resolve('punycode'),
};

module.exports = config;
