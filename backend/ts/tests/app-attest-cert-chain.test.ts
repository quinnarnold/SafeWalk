/**
 * Tests for app-attest.ts certificate chain verification helpers.
 *
 * Generates a 3-cert chain (root P-384, intermediate P-256, leaf P-256)
 * that mirrors Apple App Attest chain structure, then exercises the
 * DER-parsing and signature-verification paths.
 *
 * Run with: bun test tests/app-attest-cert-chain.test.ts
 */
import { describe, it, expect } from 'bun:test';
import crypto from 'node:crypto';
import { execFileSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

// ---- re-export internal helpers for testing --------------------------------
// The functions below are copies of the private functions in app-attest.ts.
// They are duplicated here so tests can exercise them without exporting internals.

function readDerLength(buf: Buffer, pos: number): { length: number; nextPos: number } | null {
  if (pos >= buf.length) return null;
  const first = buf[pos]!;
  if (first < 0x80) return { length: first, nextPos: pos + 1 };
  const numBytes = first & 0x7f;
  if (numBytes === 0 || pos + 1 + numBytes > buf.length) return null;
  let length = 0;
  for (let i = 0; i < numBytes; i++) {
    length = (length << 8) | buf[pos + 1 + i]!;
  }
  return { length, nextPos: pos + 1 + numBytes };
}

function extractSpkiFromCert(certDer: Buffer): Buffer | null {
  let pos = 0;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const certSeq = readDerLength(certDer, pos);
  if (!certSeq) return null;
  pos = certSeq.nextPos;

  if (certDer[pos] !== 0x30) return null;
  pos++;
  const tbsSeq = readDerLength(certDer, pos);
  if (!tbsSeq) return null;
  pos = tbsSeq.nextPos;

  if (certDer[pos] === 0xa0) {
    pos++;
    const vLen = readDerLength(certDer, pos);
    if (!vLen) return null;
    pos = vLen.nextPos + vLen.length;
  }

  if (certDer[pos] !== 0x02) return null;
  pos++;
  const serialLen = readDerLength(certDer, pos);
  if (!serialLen) return null;
  pos = serialLen.nextPos + serialLen.length;

  if (certDer[pos] !== 0x30) return null;
  pos++;
  const sigAlgLen = readDerLength(certDer, pos);
  if (!sigAlgLen) return null;
  pos = sigAlgLen.nextPos + sigAlgLen.length;

  if (certDer[pos] !== 0x30) return null;
  pos++;
  const issuerLen = readDerLength(certDer, pos);
  if (!issuerLen) return null;
  pos = issuerLen.nextPos + issuerLen.length;

  if (certDer[pos] !== 0x30) return null;
  pos++;
  const validityLen = readDerLength(certDer, pos);
  if (!validityLen) return null;
  pos = validityLen.nextPos + validityLen.length;

  if (certDer[pos] !== 0x30) return null;
  pos++;
  const subjectLen = readDerLength(certDer, pos);
  if (!subjectLen) return null;
  pos = subjectLen.nextPos + subjectLen.length;

  if (certDer[pos] !== 0x30) return null;
  const spkiStart = pos;
  pos++;
  const spkiLen = readDerLength(certDer, pos);
  if (!spkiLen) return null;
  const spkiEnd = spkiLen.nextPos + spkiLen.length;
  return certDer.subarray(spkiStart, spkiEnd);
}

function extractTbsAndSignature(certDer: Buffer): {
  tbs: Buffer;
  signatureAlgorithm: Buffer;
  signature: Buffer;
} | null {
  let pos = 0;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const outerLen = readDerLength(certDer, pos);
  if (!outerLen) return null;
  pos = outerLen.nextPos;

  const tbsStart = pos;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const tbsLen = readDerLength(certDer, pos);
  if (!tbsLen) return null;
  const tbsEnd = tbsLen.nextPos + tbsLen.length;
  const tbs = certDer.subarray(tbsStart, tbsEnd);
  pos = tbsEnd;

  const sigAlgStart = pos;
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const sigAlgLen = readDerLength(certDer, pos);
  if (!sigAlgLen) return null;
  const sigAlgEnd = sigAlgLen.nextPos + sigAlgLen.length;
  const signatureAlgorithm = certDer.subarray(sigAlgStart, sigAlgEnd);
  pos = sigAlgEnd;

  if (certDer[pos] !== 0x03) return null;
  pos++;
  const sigLen = readDerLength(certDer, pos);
  if (!sigLen) return null;
  pos = sigLen.nextPos;
  pos++;
  const signature = certDer.subarray(pos, pos + sigLen.length - 1);

  return { tbs, signatureAlgorithm, signature };
}

function detectCurveFromSpki(spki: Buffer): { namedCurve: string; hash: string } {
  const p256Oid = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]);
  const p384Oid = Buffer.from([0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22]);
  if (spki.includes(p384Oid)) return { namedCurve: 'P-384', hash: 'SHA-384' };
  if (spki.includes(p256Oid)) return { namedCurve: 'P-256', hash: 'SHA-256' };
  return { namedCurve: 'P-256', hash: 'SHA-256' };
}

const ECDSA_SHA384_OID = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]);

function detectHashFromSignatureAlgorithm(sigAlg: Buffer): { hash: string; componentLen: number } {
  if (sigAlg.includes(ECDSA_SHA384_OID)) return { hash: 'SHA-384', componentLen: 48 };
  return { hash: 'SHA-256', componentLen: 32 };
}

function derSignatureToP1363(derSig: Buffer, componentLen: number): Buffer | null {
  let pos = 0;
  if (derSig[pos] !== 0x30) return null;
  pos++;
  const seqLen = readDerLength(derSig, pos);
  if (!seqLen) return null;
  pos = seqLen.nextPos;

  if (derSig[pos] !== 0x02) return null;
  pos++;
  const rLen = readDerLength(derSig, pos);
  if (!rLen) return null;
  pos = rLen.nextPos;
  let r = derSig.subarray(pos, pos + rLen.length);
  pos += rLen.length;

  if (derSig[pos] !== 0x02) return null;
  pos++;
  const sLen = readDerLength(derSig, pos);
  if (!sLen) return null;
  pos = sLen.nextPos;
  let s = derSig.subarray(pos, pos + sLen.length);

  if (r.length > componentLen && r[0] === 0x00) r = r.subarray(1);
  if (s.length > componentLen && s[0] === 0x00) s = s.subarray(1);

  const result = Buffer.alloc(componentLen * 2);
  r.copy(result, componentLen - r.length);
  s.copy(result, componentLen * 2 - s.length);
  return result;
}

// Current verifyCertSignature from app-attest.ts (copied verbatim for comparison)
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

  const { hash, componentLen } = detectHashFromSignatureAlgorithm(parts.signatureAlgorithm);
  const p1363Sig = derSignatureToP1363(Buffer.from(parts.signature), componentLen);
  if (!p1363Sig) return false;

  // BUG CANDIDATE: parts.tbs is a subarray (non-zero byteOffset in Bun's allocator).
  // Bun's crypto.subtle.verify may not read from byteOffset correctly.
  return crypto.subtle.verify(
    { name: 'ECDSA', hash },
    key,
    p1363Sig,
    parts.tbs
  );
}

// Fixed version: uses fresh Uint8Array copies (byteOffset=0) for all WebCrypto inputs,
// and derives componentLen from the ISSUER curve rather than the sigAlg OID.
async function verifyCertSignatureFixed(certDer: Buffer, issuerSpki: Buffer): Promise<boolean> {
  const parts = extractTbsAndSignature(certDer);
  if (!parts) return false;

  // Fresh copy ensures byteOffset=0 for Bun's WebCrypto importKey.
  const spkiCopy = new Uint8Array(issuerSpki);
  const spkiBuf = Buffer.from(spkiCopy);
  const { namedCurve } = detectCurveFromSpki(spkiBuf);

  // componentLen must derive from the ISSUER's curve (P-384=48, P-256=32),
  // NOT from the cert's sigAlg OID. A P-384 issuer can sign with ecdsa-with-SHA256,
  // producing 48-byte r,s values even though the OID maps to componentLen=32.
  const componentLen = namedCurve === 'P-384' ? 48 : 32;

  const key = await crypto.subtle.importKey(
    'spki',
    spkiCopy,
    { name: 'ECDSA', namedCurve },
    false,
    ['verify']
  );

  const { hash } = detectHashFromSignatureAlgorithm(parts.signatureAlgorithm);
  const p1363Sig = derSignatureToP1363(Buffer.from(parts.signature), componentLen);
  if (!p1363Sig) return false;

  // Fix: fresh Uint8Array ensures byteOffset=0 for Bun's crypto.subtle.verify.
  return crypto.subtle.verify(
    { name: 'ECDSA', hash },
    key,
    new Uint8Array(p1363Sig),
    new Uint8Array(parts.tbs)
  );
}

function pemToDer(pem: string): Buffer {
  const base64 = pem
    .replace(/-----BEGIN CERTIFICATE-----/, '')
    .replace(/-----END CERTIFICATE-----/, '')
    .replace(/\s/g, '');
  return Buffer.from(base64, 'base64');
}

// ---- cert chain generation -------------------------------------------------

interface CertChain {
  rootDer: Buffer;
  intermediateDer: Buffer;
  leafDer: Buffer;
}

function generateCertChain(hashForInt: string): CertChain {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'attest-test-'));

  execFileSync('openssl', ['ecparam', '-name', 'secp384r1', '-genkey', '-noout', '-out', `${dir}/root.key`]);
  execFileSync('openssl', ['req', '-new', '-x509', '-key', `${dir}/root.key`, '-out', `${dir}/root.crt`, '-days', '1', '-subj', '/CN=Test Root', '-sha384']);

  execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${dir}/int.key`]);
  execFileSync('openssl', ['req', '-new', '-key', `${dir}/int.key`, '-out', `${dir}/int.csr`, '-subj', '/CN=Test Intermediate']);
  execFileSync('openssl', ['x509', '-req', '-in', `${dir}/int.csr`, '-CA', `${dir}/root.crt`, '-CAkey', `${dir}/root.key`, '-out', `${dir}/int.crt`, '-days', '1', `-${hashForInt}`, '-CAcreateserial']);

  execFileSync('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${dir}/leaf.key`]);
  execFileSync('openssl', ['req', '-new', '-key', `${dir}/leaf.key`, '-out', `${dir}/leaf.csr`, '-subj', '/CN=Test Leaf']);
  execFileSync('openssl', ['x509', '-req', '-in', `${dir}/leaf.csr`, '-CA', `${dir}/int.crt`, '-CAkey', `${dir}/int.key`, '-out', `${dir}/leaf.crt`, '-days', '1', '-sha256', '-CAcreateserial']);

  return {
    rootDer: pemToDer(fs.readFileSync(`${dir}/root.crt`, 'utf8')),
    intermediateDer: pemToDer(fs.readFileSync(`${dir}/int.crt`, 'utf8')),
    leafDer: pemToDer(fs.readFileSync(`${dir}/leaf.crt`, 'utf8')),
  };
}

// ---- tests -----------------------------------------------------------------

describe('extractSpkiFromCert', () => {
  it('extracts SPKI matching X509Certificate for P-256 cert', () => {
    const chain = generateCertChain('sha384');
    const parsed = extractSpkiFromCert(chain.intermediateDer);
    expect(parsed).not.toBeNull();
    const x509 = new crypto.X509Certificate(chain.intermediateDer);
    const expected = Buffer.from(x509.publicKey.export({ type: 'spki', format: 'der' }));
    expect(parsed!.equals(expected)).toBe(true);
  });

  it('extracts SPKI matching X509Certificate for P-384 cert', () => {
    const chain = generateCertChain('sha384');
    const parsed = extractSpkiFromCert(chain.rootDer);
    expect(parsed).not.toBeNull();
    const x509 = new crypto.X509Certificate(chain.rootDer);
    const expected = Buffer.from(x509.publicKey.export({ type: 'spki', format: 'der' }));
    expect(parsed!.equals(expected)).toBe(true);
  });
});

describe('derSignatureToP1363', () => {
  it('converts P-256 DER signature to correct 64-byte P1363', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const derSig = crypto.sign('sha256', crypto.randomBytes(32), privateKey);
    const p1363 = derSignatureToP1363(derSig, 32);
    expect(p1363).not.toBeNull();
    expect(p1363!.length).toBe(64);
  });

  it('converts P-384 DER signature to correct 96-byte P1363', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'secp384r1' });
    const derSig = crypto.sign('sha384', crypto.randomBytes(32), privateKey);
    const p1363 = derSignatureToP1363(derSig, 48);
    expect(p1363).not.toBeNull();
    expect(p1363!.length).toBe(96);
  });

  it('throws RangeError when P-384 signature used with componentLen=32 (sigAlg OID mismatch bug)', () => {
    // This demonstrates the latent bug: if a P-384 key signs using ecdsa-with-SHA256,
    // detectHashFromSignatureAlgorithm returns componentLen=32 but r,s are 48 bytes.
    // Buffer.copy with negative targetStart throws.
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'secp384r1' });
    const derSig = crypto.sign('sha256', crypto.randomBytes(32), privateKey);
    expect(() => derSignatureToP1363(derSig, 32)).toThrow();
  });
});

describe('cert chain verification - Apple-like (root P-384/SHA-384, int P-256/SHA-384, leaf P-256/SHA-256)', () => {
  const chain = generateCertChain('sha384');

  it('current code: verifies intermediate signed by root (P-384/SHA-384)', async () => {
    const rootSpki = extractSpkiFromCert(chain.rootDer)!;
    expect(await verifyCertSignature(chain.intermediateDer, rootSpki)).toBe(true);
  });

  it('current code: verifies leaf signed by intermediate (P-256/SHA-256)', async () => {
    const intSpki = extractSpkiFromCert(chain.intermediateDer)!;
    // This is the FAILING step in production on Bun.
    // If this passes in Node but fails in Bun, the Bun WebCrypto byteOffset bug is confirmed.
    expect(await verifyCertSignature(chain.leafDer, intSpki)).toBe(true);
  });

  it('fixed code: verifies leaf signed by intermediate (P-256/SHA-256)', async () => {
    const intSpki = extractSpkiFromCert(chain.intermediateDer)!;
    expect(await verifyCertSignatureFixed(chain.leafDer, intSpki)).toBe(true);
  });

  it('fixed code: rejects leaf cert with wrong issuer key', async () => {
    const wrongChain = generateCertChain('sha384');
    const wrongIntSpki = extractSpkiFromCert(wrongChain.intermediateDer)!;
    expect(await verifyCertSignatureFixed(chain.leafDer, wrongIntSpki)).toBe(false);
  });
});

describe('cert chain verification - componentLen mismatch (root P-384 signs int with SHA-256)', () => {
  const chain = generateCertChain('sha256');

  it('current code: throws RangeError for P-384 signer with SHA-256 sigAlg OID', async () => {
    const rootSpki = extractSpkiFromCert(chain.rootDer)!;
    // verifyCertSignature has no internal try-catch; the RangeError propagates.
    await expect(verifyCertSignature(chain.intermediateDer, rootSpki)).rejects.toThrow();
  });

  it('fixed code: correctly verifies P-384 signer with SHA-256 sigAlg OID', async () => {
    const rootSpki = extractSpkiFromCert(chain.rootDer)!;
    expect(await verifyCertSignatureFixed(chain.intermediateDer, rootSpki)).toBe(true);
  });
});
