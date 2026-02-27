/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  webpack: (config) => {
    // Required for Noir.js + @aztec/bb.js WASM support
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
    };

    // Handle WASM files
    config.module.rules.push({
      test: /\.wasm$/,
      type: "webassembly/async",
    });

    // Resolve fallbacks for Node.js modules used by @aztec/bb.js
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      path: false,
      crypto: false,
      net: false,
      tls: false,
      "pino-pretty": false,
      "@react-native-async-storage/async-storage": false,
    };

    return config;
  },
};

module.exports = nextConfig;
