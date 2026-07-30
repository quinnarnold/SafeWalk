import { FastifyRequest, FastifyReply } from 'fastify';
import { verifyAssertion } from '../services/app-attest.js';
import { config } from '../config.js';
import { canonicalRequestData } from '../utils/request-canonicalization.js';

const MAX_TIMESTAMP_AGE_MS = 5 * 60 * 1000;

const PUBLIC_PATHS = ['/', '/health', '/cities'];

export const APP_ATTEST_CREDENTIAL_NOT_FOUND = 'app-attest-credential-not-found';

function isPublicPath(path: string): boolean {
  if (PUBLIC_PATHS.includes(path)) {
    return true;
  }
  if (path.startsWith('/watch/')) {
    return true;
  }
  if (/^\/[^/]+\/attest\/(?:challenge|verify)$/.test(path)) {
    return true;
  }
  return false;
}

/**
 * Verify request authentication via App Attest assertion.
 *
 * Requires X-App-Attest-KeyId + X-App-Attest-Assertion + X-Timestamp headers.
 */
export async function verifyRequestSignature(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  if (config.authMode === 'disabled') {
    return;
  }

  const path = request.url.split('?')[0] ?? '';
  if (isPublicPath(path)) {
    return;
  }

  const appAttestKeyId = request.headers['x-app-attest-keyid'] as string | undefined;
  const appAttestAssertion = request.headers['x-app-attest-assertion'] as string | undefined;

  if (!appAttestKeyId || !appAttestAssertion) {
    reply.code(401).send({
      error: 'Unauthorized',
      message: 'App Attest authentication required',
    });
    return;
  }

  const timestamp = request.headers['x-timestamp'] as string | undefined;
  if (!timestamp) {
    reply.code(401).send({
      error: 'Unauthorized',
      message: 'Missing timestamp header for App Attest',
    });
    return;
  }

  const requestTime = parseInt(timestamp, 10) * 1000;
  const now = Date.now();

  if (isNaN(requestTime) || Math.abs(now - requestTime) > MAX_TIMESTAMP_AGE_MS) {
    reply.code(401).send({
      error: 'Unauthorized',
      message: 'Request timestamp expired',
    });
    return;
  }

  const method = request.method;
  const clientData = canonicalRequestData(timestamp, method, request.url, request.body);

  const result = await verifyAssertion(
    appAttestKeyId,
    appAttestAssertion,
    clientData,
    config.appAttestAppId,
  );
  if (!result.valid) {
    request.log.warn({ path, method, reason: result.reason }, 'Invalid App Attest assertion');
    if (result.reason === 'no-stored-credential') {
      reply.code(401).send({
        error: 'Unauthorized',
        code: APP_ATTEST_CREDENTIAL_NOT_FOUND,
        message: 'App Attest credential is no longer available',
      });
      return;
    }
    reply.code(401).send({
      error: 'Unauthorized',
      message: 'Invalid App Attest assertion',
    });
    return;
  }
}
