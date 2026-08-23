import {logger} from "firebase-functions";
import {signSumsubRequest, type SumsubHttpMethod} from "./sumsubAuth.js";
import {DEFAULT_SUMSUB_BASE_URL} from "./sumsubConfig.js";

export type SumsubAccessTokenResponse = {
  token: string;
  userId: string;
};

export class SumsubClient {
  constructor(
    private readonly appToken: string,
    private readonly secretKey: string,
    private readonly baseUrl: string = DEFAULT_SUMSUB_BASE_URL,
  ) {}

  async generateAccessToken(input: {
    userId: string;
    levelName: string;
    ttlInSecs?: number;
    email?: string;
    phone?: string;
  }): Promise<SumsubAccessTokenResponse> {
    const path = "/resources/accessTokens/sdk";
    const payload: Record<string, unknown> = {
      userId: input.userId,
      levelName: input.levelName,
      ttlInSecs: input.ttlInSecs ?? 600,
    };
    const identifiers: Record<string, string> = {};
    if (input.email) {
      identifiers.email = input.email;
    }
    if (input.phone) {
      identifiers.phone = input.phone;
    }
    if (Object.keys(identifiers).length > 0) {
      payload.applicantIdentifiers = identifiers;
    }
    const body = JSON.stringify(payload);
    const {timestamp, signature} = signSumsubRequest({
      secretKey: this.secretKey,
      method: "POST",
      pathWithQuery: path,
      body,
    });

    const response = await fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-App-Token": this.appToken,
        "X-App-Access-Ts": timestamp,
        "X-App-Access-Sig": signature,
      },
      body,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => "");
      logger.warn("Sumsub access token request failed", {
        status: response.status,
        reason: errorText.slice(0, 200),
      });
      throw new SumsubApiError(response.status, "sumsub-token-failed");
    }

    const data = (await response.json()) as {token?: string; userId?: string};
    const token = String(data.token ?? "");
    if (!token) {
      throw new SumsubApiError(502, "sumsub-token-empty");
    }
    return {token, userId: String(data.userId ?? input.userId)};
  }

  async request<T>(method: SumsubHttpMethod, pathWithQuery: string, bodyObj?: unknown): Promise<T> {
    const body = bodyObj === undefined ? "" : JSON.stringify(bodyObj);
    const {timestamp, signature} = signSumsubRequest({
      secretKey: this.secretKey,
      method,
      pathWithQuery,
      body: body || undefined,
    });
    const response = await fetch(`${this.baseUrl}${pathWithQuery}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-App-Token": this.appToken,
        "X-App-Access-Ts": timestamp,
        "X-App-Access-Sig": signature,
      },
      ...(body ? {body} : {}),
    });
    if (!response.ok) {
      throw new SumsubApiError(response.status, "sumsub-api-failed");
    }
    return (await response.json()) as T;
  }
}

export class SumsubApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
  ) {
    super(code);
    this.name = "SumsubApiError";
  }
}
