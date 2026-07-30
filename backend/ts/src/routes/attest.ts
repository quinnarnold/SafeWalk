import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import {
  generateChallenge,
  storeChallenge,
  consumeChallenge,
  verifyAttestation,
} from '../services/app-attest.js';
import { config } from '../config.js';
import { setPrivateNoStore } from '../utils/private-response.js';

async function getChallenge(_request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const challenge = generateChallenge();
  await storeChallenge(challenge);
  return { challenge };
}

async function verify(request: FastifyRequest, reply: FastifyReply) {
  setPrivateNoStore(reply);
  const body = request.body as {
    keyId?: string;
    attestation?: string;
    challenge?: string;
  };

  if (!body?.keyId || !body?.attestation || !body?.challenge) {
    return reply.status(400).send({
      error: 'Missing required fields: keyId, attestation, challenge',
    });
  }

  if (!config.appAttestAppId) {
    request.log.error('APP_ATTEST_APP_ID not configured');
    return reply.status(500).send({ error: 'App Attest not configured' });
  }

  const consumed = await consumeChallenge(body.challenge);
  if (!consumed) {
    request.log.warn('Challenge already consumed or expired');
    return reply.status(403).send({
      error: 'Invalid or expired challenge',
    });
  }

  const result = await verifyAttestation(
    body.keyId,
    body.attestation,
    body.challenge,
    config.appAttestAppId
  );

  if (!result.valid) {
    request.log.warn('Attestation verification failed');
    return reply.status(403).send({
      error: 'Attestation verification failed',
    });
  }

  return { verified: true };
}

export const attestRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get('/:city/attest/challenge', {
    config: {
      rateLimit: {
        max: 10,
        timeWindow: '1 minute',
      },
    },
  }, getChallenge);
  fastify.post('/:city/attest/verify', {
    config: {
      rateLimit: {
        max: 5,
        timeWindow: '1 minute',
      },
    },
  }, verify);
};
