import crypto from 'node:crypto';

function encodeQueryComponent(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (character) =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

export function canonicalQuery(rawUrl: string): string {
  const url = new URL(rawUrl, 'http://localhost');
  return [...url.searchParams.entries()]
    .sort(([leftName, leftValue], [rightName, rightValue]) =>
      compareText(leftName, rightName) || compareText(leftValue, rightValue),
    )
    .map(([name, value]) => `${encodeQueryComponent(name)}=${encodeQueryComponent(value)}`)
    .join('&');
}

export function stableJson(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableJson).join(',')}]`;
  }

  const entries = Object.entries(value as Record<string, unknown>)
    .sort(([left], [right]) => compareText(left, right));
  return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`).join(',')}}`;
}

export function canonicalRequestData(
  timestamp: string,
  method: string,
  rawUrl: string,
  body: unknown,
): string {
  const url = new URL(rawUrl, 'http://localhost');
  const bodyText = body === undefined ? '' : stableJson(body);
  const bodyHash = crypto.createHash('sha256').update(bodyText).digest('hex');
  return [
    timestamp,
    method.toUpperCase(),
    url.pathname,
    canonicalQuery(rawUrl),
    bodyHash,
  ].join('\n');
}
