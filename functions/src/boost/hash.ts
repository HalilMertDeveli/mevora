import {createHash} from "node:crypto";

/** Store hashes of Play tokens / receipts. Never persist the raw secret. */
export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
