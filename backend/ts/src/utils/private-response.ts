import type { FastifyReply } from 'fastify';

export const PRIVATE_NO_STORE = 'private, no-store, max-age=0';

export function setPrivateNoStore(reply: FastifyReply): void {
  reply.header('Cache-Control', PRIVATE_NO_STORE);
}
