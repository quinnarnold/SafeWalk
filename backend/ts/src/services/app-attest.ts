import crypto from 'node:crypto';
import { decode, decodeMultiple } from 'cbor-x';
import { getRedis } from './redis-cache.js';
import { config } from '../config.js';

const CHALLENGE_TTL = 300;
const ATTEST_KEY_TTL = 90 * 24 * 3600;

const APPLE_APP_ATTEST_ROOT_CA = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const APPLE_NONCE_OID_DER = Buffer.from([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02,
]);

/**
 * Extract the nonce from the App Attest credential certificate.
 *
 * The nonce is stored in an X.509 extension with OID 1.2.840.113635.100.8.2.
 * The extension value is an ASN.1 SEQUENCE containing an OCTET STRING with
 * the 32-byte nonce.
 */
function extractNonceFromCert(certDer: Buffer): Buffer | null {
  const oidIndex = certDer.indexOf(APPLE_NONCE_OID_DER);
  if (oidIndex === -1) return null;

  let pos = oidIndex + APPLE_NONCE_OID_DER.length;

  // Skip the OCTET STRING wrapper for the extension value
  if (pos >= certDer.length || certDer[pos] !== 0x04) return null;
  pos++;
  const outerLen = readDerLength(certDer, pos);
  if (!outerLen) return null;
  pos = outerLen.nextPos;

  // Inside is a SEQUENCE (0x30)
  if (pos >= certDer.length || certDer[pos] !== 0x30) return null;
  pos++;
  const seqLen = readDerLength(certDer, pos);
  if (!seqLen) return null;
  pos = seqLen.nextPos;

  // Inside the SEQUENCE: context-tagged [1] (0xa1)
  if (pos >= certDer.length || certDer[pos] !== 0xa1) return null;
  pos++;
  const tagLen = readDerLength(certDer, pos);
  if (!tagLen) return null;
  pos = tagLen.nextPos;

  // Inside: OCTET STRING with the 32-byte nonce
  if (pos >= certDer.length || certDer[pos] !== 0x04) return null;
  pos++;
  const nonceLen = readDerLength(certDer, pos);
  if (!nonceLen) return null;
  pos = nonceLen.nextPos;

  return certDer.subarray(pos, pos + nonceLen.length);
}

/**
 * Extract the SubjectPublicKeyInfo (SPKI) DER block from a DER-encoded X.509
 * certificate by walking ASN.1 structure.
 *
 * Bypasses Bun's broken X509Certificate.publicKey (returns CryptoKey instead
 * of KeyObject, making .export() fail).
 */
function extractSpkiFromCert(certDer: Buffer): Buffer | null {
  let pos = 0;

  // Certificate SEQUENCE
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const certSeq = readDerLength(certDer, pos);
  if (!certSeq) return null;
  pos = certSeq.nextPos;

  // TBSCertificate SEQUENCE
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const tbsSeq = readDerLength(certDer, pos);
  if (!tbsSeq) return null;
  pos = tbsSeq.nextPos;

  // version [0] EXPLICIT — optional, skip if present
  if (certDer[pos] === 0xa0) {
    pos++;
    const vLen = readDerLength(certDer, pos);
    if (!vLen) return null;
    pos = vLen.nextPos + vLen.length;
  }

  // serialNumber INTEGER — skip
  if (certDer[pos] !== 0x02) return null;
  pos++;
  const serialLen = readDerLength(certDer, pos);
  if (!serialLen) return null;
  pos = serialLen.nextPos + serialLen.length;

  // signature AlgorithmIdentifier SEQUENCE — skip
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const sigAlgLen = readDerLength(certDer, pos);
  if (!sigAlgLen) return null;
  pos = sigAlgLen.nextPos + sigAlgLen.length;

  // issuer Name SEQUENCE — skip
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const issuerLen = readDerLength(certDer, pos);
  if (!issuerLen) return null;
  pos = issuerLen.nextPos + issuerLen.length;

  // validity SEQUENCE — skip
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const validityLen = readDerLength(certDer, pos);
  if (!validityLen) return null;
  pos = validityLen.nextPos + validityLen.length;

  // subject Name SEQUENCE — skip
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const subjectLen = readDerLength(certDer, pos);
  if (!subjectLen) return null;
  pos = subjectLen.nextPos + subjectLen.length;

  // subjectPublicKeyInfo SEQUENCE — this is what we want
  if (certDer[pos] !== 0x30) return null;
  const spkiStart = pos;
  pos++;
  const spkiLen = readDerLength(certDer, pos);
  if (!spkiLen) return null;
  const spkiEnd = spkiLen.nextPos + spkiLen.length;

  return certDer.subarray(spkiStart, spkiEnd);
}

/**
 * Extract the TBS (To-Be-Signed) certificate data and signature from a
 * DER-encoded X.509 certificate for manual signature verification.
 *
 * Bypasses Bun's broken X509Certificate.verify().
 */
function extractTbsAndSignature(certDer: Buffer): {
  tbs: Buffer;
  signatureAlgorithm: Buffer;
  signature: Buffer;
} | null {
  let pos = 0;

  // Outer Certificate SEQUENCE
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const outerLen = readDerLength(certDer, pos);
  if (!outerLen) return null;
  pos = outerLen.nextPos;

  // TBSCertificate SEQUENCE — capture the full TLV
  const tbsStart = pos;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const tbsLen = readDerLength(certDer, pos);
  if (!tbsLen) return null;
  const tbsEnd = tbsLen.nextPos + tbsLen.length;
  const tbs = certDer.subarray(tbsStart, tbsEnd);
  pos = tbsEnd;

  // signatureAlgorithm SEQUENCE
  const sigAlgStart = pos;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const sigAlgLen = readDerLength(certDer, pos);
  if (!sigAlgLen) return null;
  const sigAlgEnd = sigAlgLen.nextPos + sigAlgLen.length;
  const signatureAlgorithm = certDer.subarray(sigAlgStart, sigAlgEnd);
  pos = sigAlgEnd;

  // signature BIT STRING
  if (certDer[pos] !== 0x03) return null;
  pos++;
  const sigLen = readDerLength(certDer, pos);
  if (!sigLen) return null;
  pos = sigLen.nextPos;
  // Skip the unused-bits byte (always 0x00 for signatures)
  pos++;
  const signature = certDer.subarray(pos, pos + sigLen.length - 1);

  return { tbs, signatureAlgorithm, signature };
}

/**
 * Detect EC curve from an SPKI DER block by checking the algorithm OID.
 * Returns the WebCrypto namedCurve string and corresponding hash algorithm.
 */
function detectCurveFromSpki(spki: Buffer): { namedCurve: string; hash: string } {
  // OID 1.2.840.10045.3.1.7 = prime256v1 (P-256)
  const p256Oid = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]);
  // OID 1.3.132.0.34 = secp384r1 (P-384)
  const p384Oid = Buffer.from([0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22]);

  if (spki.includes(p384Oid)) return { namedCurve: 'P-384', hash: 'SHA-384' };
  if (spki.includes(p256Oid)) return { namedCurve: 'P-256', hash: 'SHA-256' };
  return { namedCurve: 'P-256', hash: 'SHA-256' };
}

/**
 * Import an SPKI DER key via WebCrypto (crypto.subtle.importKey).
 * Bypasses crypto.createPublicKey which fails in Bun's BoringSSL on Apple EC keys.
 */
// ecdsa-with-SHA384 OID: 1.2.840.10045.4.3.3
const ECDSA_SHA384_OID = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]);

/**
 * Determine hash algorithm and P1363 component length from a cert's
 * signatureAlgorithm field. More reliable than inferring from the
 * issuer's curve, since the cert explicitly states how it was signed.
 */
function detectHashFromSignatureAlgorithm(sigAlg: Buffer): { hash: string } {
  if (sigAlg.includes(ECDSA_SHA384_OID)) {
    return { hash: 'SHA-384' };
  }
  return { hash: 'SHA-256' };
}

/**
 * Verify a DER certificate's signature against an issuer's public key.
 * Uses WebCrypto (crypto.subtle) instead of Node crypto.createPublicKey +
 * crypto.verify, which fail in Bun's BoringSSL on Apple EC keys.
 */
async function verifyCertSignature(certDer: Buffer, issuerSpki: Buffer): Promise<boolean> {
  const parts = extractTbsAndSignature(certDer);
  if (!parts) return false;

  const spki = Buffer.from(issuerSpki);
  const { namedCurve } = detectCurveFromSpki(spki);

  const key = await crypto.subtle.importKey(
    'spki',
    spki,
    { name: 'ECDSA', namedCurve },
    false,
    ['verify']
  );

  // Hash from cert's signatureAlgorithm; componentLen from issuer's curve (independent)
  const { hash } = detectHashFromSignatureAlgorithm(parts.signatureAlgorithm);
  const componentLen = namedCurve === 'P-384' ? 48 : 32;

  const p1363Sig = derSignatureToP1363(Buffer.from(parts.signature), componentLen);
  if (!p1363Sig) return false;

  return crypto.subtle.verify(
    { name: 'ECDSA', hash },
    key,
    p1363Sig,
    parts.tbs
  );
}

/**
 * Convert a DER-encoded ECDSA signature (ASN.1 SEQUENCE of two INTEGERs)
 * to IEEE P1363 format (raw r || s, each zero-padded to componentLen bytes).
 * WebCrypto requires P1363 format for ECDSA verify.
 */
function derSignatureToP1363(derSig: Buffer, componentLen: number): Buffer | null {
  let pos = 0;
  if (derSig[pos] !== 0x30) return null;
  pos++;
  const seqLen = readDerLength(derSig, pos);
  if (!seqLen) return null;
  pos = seqLen.nextPos;

  // Read r INTEGER
  if (derSig[pos] !== 0x02) return null;
  pos++;
  const rLen = readDerLength(derSig, pos);
  if (!rLen) return null;
  pos = rLen.nextPos;
  let r = derSig.subarray(pos, pos + rLen.length);
  pos += rLen.length;

  // Read s INTEGER
  if (derSig[pos] !== 0x02) return null;
  pos++;
  const sLen = readDerLength(derSig, pos);
  if (!sLen) return null;
  pos = sLen.nextPos;
  let s = derSig.subarray(pos, pos + sLen.length);

  // Strip leading zero bytes (ASN.1 INTEGER sign padding)
  if (r.length > componentLen && r[0] === 0x00) r = r.subarray(1);
  if (s.length > componentLen && s[0] === 0x00) s = s.subarray(1);

  // Zero-pad to componentLen
  const result = Buffer.alloc(componentLen * 2);
  r.copy(result, componentLen - r.length);
  s.copy(result, componentLen * 2 - s.length);
  return result;
}

function readDerLength(buf: Buffer, pos: number): { length: number; nextPos: number } | null {
  if (pos >= buf.length) return null;
  const first = buf[pos]!;
  if (first < 0x80) {
    return { length: first, nextPos: pos + 1 };
  }
  const numBytes = first & 0x7f;
  if (numBytes === 0 || pos + 1 + numBytes > buf.length) return null;
  let length = 0;
  for (let i = 0; i < numBytes; i++) {
    length = (length << 8) | buf[pos + 1 + i]!;
  }
  return { length, nextPos: pos + 1 + numBytes };
}

export function generateChallenge(): string {
  return crypto.randomBytes(32).toString('base64url');
}

export async function storeChallenge(challenge: string): Promise<void> {
  try {
    const redis = getRedis();
    await redis.set(`attest:challenge:${challenge}`, '1', 'EX', CHALLENGE_TTL);
  } catch {
    throw new Error('Storage operation failed');
  }
}

export async function consumeChallenge(challenge: string): Promise<boolean> {
  try {
    const redis = getRedis();
    const result = await redis.del(`attest:challenge:${challenge}`);
    return result === 1;
  } catch {
    throw new Error('Storage operation failed');
  }
}

interface AttestationObject {
  fmt: string;
  attStmt: {
    x5c: Buffer[];
    receipt: Buffer;
  };
  authData: Buffer;
}

interface StoredCredential {
  publicKey: string;
  receipt: string;
  signCount: number;
  validationCategory: number;
  bundleVersion: string;
  createdAt: number;
}

function extensionValue(extensions: unknown, key: string): unknown {
  if (extensions instanceof Map) {
    return extensions.get(key);
  }
  if (extensions && typeof extensions === 'object') {
    return (extensions as Record<string, unknown>)[key];
  }
  return undefined;
}

function decodeAuthenticatorExtensions(
  authData: Buffer,
  offset: number,
  hasAttestedCredentialData: boolean,
): unknown | null {
  try {
    const values = decodeMultiple(authData.subarray(offset)) as unknown[];
    const extensionIndex = hasAttestedCredentialData ? 1 : 0;
    return values[extensionIndex] ?? null;
  } catch {
    return null;
  }
}

function parseAppExtensions(
  extensions: unknown,
  categoryKey: string,
  bundleVersionKey: string,
): { validationCategory: number; bundleVersion: string } | null {
  const validationCategory = extensionValue(extensions, categoryKey);
  const bundleVersion = extensionValue(extensions, bundleVersionKey);
  if (
    typeof validationCategory !== 'number'
    || !Number.isInteger(validationCategory)
    || typeof bundleVersion !== 'string'
  ) {
    return null;
  }
  return { validationCategory, bundleVersion };
}

/**
 * Verify an App Attest attestation object.
 *
 * Validates the CBOR-decoded attestation: verifies the certificate chain
 * leads to Apple's root CA, checks the nonce matches the challenge + keyId,
 * and extracts the public key for future assertion verification.
 *
 * Uses raw DER parsing instead of X509Certificate.publicKey and .verify()
 * which are broken in Bun's BoringSSL (publicKey returns CryptoKey instead
 * of KeyObject, and verify() fails on EC keys).
 */
export async function verifyAttestation(
  keyId: string,
  attestationBase64: string,
  challenge: string,
  appId: string
): Promise<{ valid: boolean; error?: string }> {
  try {
    const attestationBuffer = Buffer.from(attestationBase64, 'base64');
    const attestation = decode(attestationBuffer) as AttestationObject;

    if (attestation.fmt !== 'apple-appattest') {
      return { valid: false, error: 'Invalid attestation format' };
    }

    const { x5c, receipt } = attestation.attStmt;
    if (!x5c || x5c.length < 2) {
      return { valid: false, error: 'Missing certificate chain' };
    }

    const credCertBuf = Buffer.from(x5c[0]!);
    const intermediateCertBuf = Buffer.from(x5c[1]!);

    // Extract SPKI from each certificate via raw DER parsing
    const rootCertPem = APPLE_APP_ATTEST_ROOT_CA;
    const rootCertDer = pemToDer(rootCertPem);
    const rootSpki = extractSpkiFromCert(rootCertDer);
    const intermediateSpki = extractSpkiFromCert(intermediateCertBuf);

    if (!rootSpki || !intermediateSpki) {
      return { valid: false, error: 'Could not extract public keys from certificate chain' };
    }

    // Verify chain: intermediate signed by root, credential signed by intermediate
    if (!(await verifyCertSignature(intermediateCertBuf, rootSpki))) {
      return { valid: false, error: 'Intermediate cert not signed by Apple root CA' };
    }

    if (!(await verifyCertSignature(credCertBuf, intermediateSpki))) {
      return { valid: false, error: 'Credential cert not signed by intermediate' };
    }

    const authData = attestation.authData;
    if (authData.length < 55) {
      return { valid: false, error: 'Authenticator data is truncated' };
    }

    const clientDataHash = crypto.createHash('sha256').update(challenge).digest();
    const nonceData = Buffer.concat([authData, clientDataHash]);
    const expectedNonce = crypto.createHash('sha256').update(nonceData).digest();

    const extractedNonce = extractNonceFromCert(credCertBuf);
    if (!extractedNonce) {
      return { valid: false, error: 'Could not extract nonce from credential certificate' };
    }
    if (!extractedNonce.equals(expectedNonce)) {
      return { valid: false, error: 'Nonce mismatch in credential certificate' };
    }

    const rpIdHash = authData.subarray(0, 32);
    const appIdHash = crypto.createHash('sha256').update(appId).digest();
    if (!rpIdHash.equals(appIdHash)) {
      return { valid: false, error: 'App ID mismatch in attestation' };
    }

    const flags = authData[32]!;
    if ((flags & 0x40) === 0 || (flags & 0x80) === 0) {
      return { valid: false, error: 'Required authenticator data flags are missing' };
    }

    // Sign count must be zero during initial attestation
    const attestSignCount = Buffer.from(authData.subarray(33, 37)).readUInt32BE(0);
    if (attestSignCount !== 0) {
      return { valid: false, error: 'Sign count must be zero during attestation' };
    }

    // Credential ID in authData must equal the keyId (both are SHA-256 of the public key)
    const expectedAaguid = Buffer.concat([Buffer.from('appattest'), Buffer.alloc(7)]);
    const aaguid = Buffer.from(authData.subarray(37, 53));
    if (!aaguid.equals(expectedAaguid)) {
      return { valid: false, error: 'Unexpected App Attest AAGUID' };
    }

    const credIdLen = Buffer.from(authData.subarray(53, 55)).readUInt16BE(0);
    if (authData.length < 55 + credIdLen) {
      return { valid: false, error: 'Credential ID is truncated' };
    }
    const credentialId = Buffer.from(authData.subarray(55, 55 + credIdLen));
    const keyIdBytes = Buffer.from(keyId, 'base64url');
    if (!credentialId.equals(keyIdBytes)) {
      return { valid: false, error: 'Credential ID does not match key ID' };
    }
    const extensions = decodeAuthenticatorExtensions(authData, 55 + credIdLen, true);
    const extensionValues = parseAppExtensions(
      extensions,
      'apple_validation_category_01',
      'apple_bundle_version_01',
    );
    if (
      !extensionValues
      || !config.appAttestAllowedValidationCategories.includes(extensionValues.validationCategory)
      || extensionValues.bundleVersion !== config.appAttestBundleVersion
    ) {
      return { valid: false, error: 'Invalid App Attest validation extensions' };
    }

    // Extract public key from credential cert via raw DER, not X509Certificate.publicKey
    const credSpki = extractSpkiFromCert(credCertBuf);
    if (!credSpki) {
      return { valid: false, error: 'Could not extract public key from credential certificate' };
    }
    const publicPoint = Buffer.from(credSpki.subarray(-65));
    if (publicPoint.length !== 65 || publicPoint[0] !== 0x04) {
      return { valid: false, error: 'Credential certificate does not contain a P-256 public key' };
    }
    const publicKeyHash = crypto.createHash('sha256').update(publicPoint).digest();
    if (!publicKeyHash.equals(keyIdBytes)) {
      return { valid: false, error: 'Public key does not match key ID' };
    }

    const credential: StoredCredential = {
      publicKey: Buffer.from(credSpki).toString('base64'),
      receipt: Buffer.from(receipt).toString('base64'),
      signCount: 0,
      ...extensionValues,
      createdAt: Date.now(),
    };

    const redis = getRedis();
    await redis.set(
      `attest:key:${keyId}`,
      JSON.stringify(credential),
      'EX',
      ATTEST_KEY_TTL
    );

    return { valid: true };
  } catch {
    return { valid: false, error: 'internal-error' };
  }
}

function pemToDer(pem: string): Buffer {
  const base64 = pem
    .replace(/-----BEGIN CERTIFICATE-----/, '')
    .replace(/-----END CERTIFICATE-----/, '')
    .replace(/\s/g, '');
  return Buffer.from(base64, 'base64');
}

const SIGN_COUNT_CAS_SCRIPT = `
local key = KEYS[1]
local expectedCount = tonumber(ARGV[1])
local newJson = ARGV[2]
local ttl = tonumber(ARGV[3])
local current = redis.call('GET', key)
if not current then return 0 end
local data = cjson.decode(current)
if data.signCount ~= expectedCount then return 0 end
redis.call('SET', key, newJson, 'EX', ttl)
return 1
`;

/**
 * Atomically update the sign counter using a Redis Lua script.
 * Returns false if the stored counter has changed since we read it (TOCTOU protection).
 */
async function atomicUpdateSignCount(
  redis: ReturnType<typeof getRedis>,
  keyId: string,
  expectedCount: number,
  newCount: number,
  credential: StoredCredential,
  ttl: number
): Promise<boolean> {
  const updated = { ...credential, signCount: newCount };
  // ioredis Redis.eval uses `this.options` internally; call as method to
  // preserve `this` binding rather than detaching via destructuring.
  const redisClient = redis as unknown as {
    eval: (...args: unknown[]) => Promise<unknown>;
  };
  const result = await redisClient.eval(
    SIGN_COUNT_CAS_SCRIPT,
    1,
    `attest:key:${keyId}`,
    String(expectedCount),
    JSON.stringify(updated),
    String(ttl)
  );
  return result === 1;
}

/**
 * Verify an App Attest assertion for an authenticated request.
 *
 * Checks the assertion signature against the stored public key,
 * verifies the client data hash matches the request payload,
 * and enforces monotonically increasing sign counter.
 */
export async function verifyAssertion(
  keyId: string,
  assertionBase64: string,
  clientData: string,
  appId: string,
): Promise<{ valid: boolean; reason?: string }> {
  try {
    const redis = getRedis();
    const stored = await redis.get(`attest:key:${keyId}`);
    if (!stored) {
      return { valid: false, reason: 'no-stored-credential' };
    }

    const credential: StoredCredential = JSON.parse(stored);

    const assertionBuffer = Buffer.from(assertionBase64, 'base64');
    const assertion = decode(assertionBuffer) as {
      signature: Buffer;
      authenticatorData: Buffer;
    };

    const signature = Buffer.from(assertion.signature);
    const authenticatorData = Buffer.from(assertion.authenticatorData);
    if (!signature.length || authenticatorData.length < 37) {
      return { valid: false, reason: 'empty-assertion-parts' };
    }

    const rpIdHash = authenticatorData.subarray(0, 32);
    const expectedRpIdHash = crypto.createHash('sha256').update(appId).digest();
    if (!rpIdHash.equals(expectedRpIdHash)) {
      return { valid: false, reason: 'app-id-mismatch' };
    }
    const flags = authenticatorData[32]!;
    if ((flags & 0x80) === 0) {
      return { valid: false, reason: 'extensions-flag-missing' };
    }
    const extensions = decodeAuthenticatorExtensions(authenticatorData, 37, false);
    const extensionValues = parseAppExtensions(
      extensions,
      'validationCategory',
      'bundleVersion',
    );
    if (
      !extensionValues
      || extensionValues.validationCategory !== credential.validationCategory
      || extensionValues.bundleVersion !== credential.bundleVersion
    ) {
      return { valid: false, reason: 'invalid-validation-extensions' };
    }

    const signCountBuf = authenticatorData.subarray(33, 37);
    const signCount = Buffer.from(signCountBuf).readUInt32BE(0);
    if (signCount <= credential.signCount) {
      return { valid: false, reason: `signcount-not-increasing(got=${signCount},stored=${credential.signCount})` };
    }

    const clientDataHash = crypto.createHash('sha256').update(clientData).digest();
    const nonce = crypto
      .createHash('sha256')
      .update(Buffer.concat([authenticatorData, clientDataHash]))
      .digest();

    const publicKeyDer = Buffer.from(credential.publicKey, 'base64');
    const p1363Sig = derSignatureToP1363(signature, 32);
    if (!p1363Sig) {
      return { valid: false, reason: `der-to-p1363-failed(sigLen=${signature.length})` };
    }

    // Apple App Attest assertions: sig is ECDSA-SHA256 over nonce, where
    // nonce = SHA256(authenticatorData || clientDataHash). WebCrypto hashes
    // the supplied message internally, so pass `nonce` (not authData||cdh).
    let valid = false;
    try {
      const key = await crypto.subtle.importKey(
        'spki',
        publicKeyDer,
        { name: 'ECDSA', namedCurve: 'P-256' },
        false,
        ['verify']
      );
      valid = await crypto.subtle.verify(
        { name: 'ECDSA', hash: 'SHA-256' },
        key,
        p1363Sig,
        nonce
      );
    } catch {
      return { valid: false, reason: 'signature-verification-error' };
    }

    if (!valid) {
      return { valid: false, reason: 'signature-verification-failed' };
    }

    const updated = await atomicUpdateSignCount(
      redis, keyId, credential.signCount, signCount, credential, ATTEST_KEY_TTL
    );
    if (!updated) {
      return { valid: false, reason: 'sign-count-cas-conflict' };
    }

    return { valid: true };
  } catch {
    return { valid: false, reason: 'internal-error' };
  }
}
