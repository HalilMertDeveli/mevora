import {createHmac} from "node:crypto";

export type SumsubHttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

/**
 * Signs Sumsub API requests per official docs:
 * HMAC-SHA256(secret, timestamp + METHOD + pathWithQuery + rawBody)
 */
export function signSumsubRequest(input: {
  secretKey: string;
  method: SumsubHttpMethod;
  pathWithQuery: string;
  body?: string;
  timestampSeconds?: number;
}): {timestamp: string; signature: string} {
  const timestamp = String(input.timestampSeconds ?? Math.floor(Date.now() / 1000));
  const body = input.body ?? "";
  const signingString = `${timestamp}${input.method}${input.pathWithQuery}${body}`;
  const signature = createHmac("sha256", input.secretKey)
    .update(signingString)
    .digest("hex");
  return {timestamp, signature};
}

export type WebhookDigestAlgorithm =
  | "HMAC_SHA1_HEX"
  | "HMAC_SHA256_HEX"
  | "HMAC_SHA512_HEX";

const digestAlgoMap: Record<WebhookDigestAlgorithm, string> = {
  HMAC_SHA1_HEX: "sha1",
  HMAC_SHA256_HEX: "sha256",
  HMAC_SHA512_HEX: "sha512",
};

/** Verifies Sumsub webhook x-payload-digest against raw request body bytes. */
export function verifyWebhookDigest(input: {
  secretKey: string;
  rawBody: Buffer | string;
  digest: string;
  algorithm: WebhookDigestAlgorithm;
}): boolean {
  const nodeAlgo = digestAlgoMap[input.algorithm];
  if (!nodeAlgo) {
    return false;
  }
  const body = typeof input.rawBody === "string"
    ? input.rawBody
    : input.rawBody.toString("utf8");
  const calculated = createHmac(nodeAlgo, input.secretKey)
    .update(body)
    .digest("hex");
  return timingSafeEqualHex(calculated, input.digest);
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < a.length; i += 1) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
