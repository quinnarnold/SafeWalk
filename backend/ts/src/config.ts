export const config = {
  port: parseInt(process.env.PORT || '8080', 10),
  host: process.env.HOST || '0.0.0.0',
  nodeEnv: process.env.NODE_ENV || 'development',
  pythonUrl: process.env.PYTHON_URL || 'http://127.0.0.1:8000',
  cityName: process.env.CITY_NAME || 'boston',
  redisHost: process.env.REDIS_HOST || 'localhost',
  redisPort: parseInt(process.env.REDIS_PORT || '6379', 10),
  redisPassword: process.env.REDIS_PASSWORD || undefined,
  routeCacheTtl: parseInt(process.env.ROUTE_CACHE_TTL_SEC || String(30 * 24 * 3600), 10),
  mmCacheTtl: parseInt(process.env.MM_CACHE_TTL_SEC || String(30 * 24 * 3600), 10),
  mapboxToken: process.env.MAPBOX_TOKEN || '',
  mapboxUsername: process.env.MAPBOX_USERNAME || '',
  logLevel: process.env.LOG_LEVEL || 'info',
  trustProxy: process.env.TRUST_PROXY === 'true',
  otpUrl: process.env.OTP_URL || 'http://otp-svc.safewalk.svc.cluster.local:8090',
  transitCacheTtl: parseInt(process.env.TRANSIT_CACHE_TTL_SEC || '300', 10),
  appAttestAppId: process.env.APP_ATTEST_APP_ID || '',
  appAttestBundleVersion: process.env.APP_ATTEST_BUNDLE_VERSION || '',
  appAttestAllowedValidationCategories: (process.env.APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES || '2,3,4,5')
    .split(',')
    .map((value) => Number.parseInt(value.trim(), 10))
    .filter(Number.isInteger),
  publicBaseUrl: process.env.PUBLIC_BASE_URL || 'http://localhost:8080',
  authMode: process.env.AUTH_MODE || 'app-attest',
  allowedOrigins: (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
} as const;

export function validateConfig(): void {
  const positiveIntegers = {
    PORT: config.port,
    REDIS_PORT: config.redisPort,
    ROUTE_CACHE_TTL_SEC: config.routeCacheTtl,
    MM_CACHE_TTL_SEC: config.mmCacheTtl,
    TRANSIT_CACHE_TTL_SEC: config.transitCacheTtl,
  };
  for (const [name, value] of Object.entries(positiveIntegers)) {
    if (!Number.isInteger(value) || value <= 0) {
      throw new Error(`${name} must be a positive integer`);
    }
  }

  if (!['app-attest', 'disabled'].includes(config.authMode)) {
    throw new Error('AUTH_MODE must be "app-attest" or "disabled"');
  }

  let publicBaseUrl: URL;
  try {
    publicBaseUrl = new URL(config.publicBaseUrl);
  } catch {
    throw new Error('PUBLIC_BASE_URL must be an absolute URL');
  }

  if (config.nodeEnv === 'production' && config.authMode === 'disabled') {
    throw new Error('AUTH_MODE=disabled is not allowed in production');
  }
  if (config.nodeEnv === 'production' && !config.appAttestAppId) {
    throw new Error('APP_ATTEST_APP_ID is required in production');
  }
  if (config.nodeEnv === 'production' && !config.appAttestBundleVersion) {
    throw new Error('APP_ATTEST_BUNDLE_VERSION is required in production');
  }
  if (config.nodeEnv === 'production' && config.appAttestAllowedValidationCategories.length === 0) {
    throw new Error('APP_ATTEST_ALLOWED_VALIDATION_CATEGORIES must contain at least one integer');
  }
  if (config.nodeEnv === 'production' && !config.mapboxUsername) {
    throw new Error('MAPBOX_USERNAME is required in production');
  }
  if (config.nodeEnv === 'production' && !config.mapboxToken) {
    throw new Error('MAPBOX_TOKEN is required in production');
  }
  if (config.nodeEnv === 'production' && publicBaseUrl.protocol !== 'https:') {
    throw new Error('PUBLIC_BASE_URL must use HTTPS in production');
  }
}

export const CITIES = [
  { name: 'atlanta', center: [-84.388, 33.749] as const, defaultZoom: 12 },
  { name: 'boston', center: [-71.057083, 42.361145] as const, defaultZoom: 12 },
  { name: 'chicago', center: [-87.6298, 41.8781] as const, defaultZoom: 12 },
  { name: 'newyork', center: [-74.006, 40.7128] as const, defaultZoom: 12 },
  { name: 'philadelphia', center: [-75.1652, 39.9526] as const, defaultZoom: 12 },
  { name: 'seattle', center: [-122.3321, 47.6062] as const, defaultZoom: 12 },
] as const;
