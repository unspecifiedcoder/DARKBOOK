/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // @aztec/bb.js proves with a multi-threaded WASM backend, which needs
  // SharedArrayBuffer. Browsers only expose SharedArrayBuffer when the
  // document is cross-origin isolated, which requires these two headers
  // on every response. Without them, proving silently falls back to the
  // single-threaded path (much slower) or fails outright.
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
          { key: "Cross-Origin-Embedder-Policy", value: "require-corp" },
        ],
      },
    ];
  },

  webpack: (config) => {
    // Noir.js + @aztec/bb.js ship WASM modules.
    config.experiments = {
      ...config.experiments,
      asyncWebAssembly: true,
      layers: true,
      topLevelAwait: true,
    };

    config.module.rules.push({
      test: /\.wasm$/,
      type: "webassembly/async",
    });

    // Node built-ins referenced by @aztec/bb.js that have no browser
    // equivalent -- stub them out.
    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      path: false,
      crypto: false,
      net: false,
      tls: false,
      worker_threads: false,
      "pino-pretty": false,
      "@react-native-async-storage/async-storage": false,
    };

    return config;
  },
};

module.exports = nextConfig;
