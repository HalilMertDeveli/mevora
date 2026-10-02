import {AsyncLocalStorage} from "node:async_hooks";
import {DocumentReference, Firestore, Query, Transaction} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

/**
 * Billed Firestore reads made inside one metered call, counted the way
 * Firestore bills them: one per document fetched (a missing one included),
 * one per document a query returns and at least one per query.
 */
export interface ReadTally {
  reads: number;
  /** Documents fetched by reference (get / getAll, in or out of transactions). */
  documents: number;
  /** Queries run, and the documents they returned. */
  queries: number;
  queryDocuments: number;
}

const current = new AsyncLocalStorage<ReadTally>();
let installed: boolean | null = null;

function tally(): ReadTally | undefined {
  return current.getStore();
}

function countDocuments(args: unknown[]): number {
  return args.filter((arg) => arg instanceof DocumentReference).length;
}

function countQuery(size: number): void {
  const t = tally();
  if (!t) return;
  t.queries += 1;
  t.queryDocuments += size;
  t.reads += Math.max(1, size);
}

function countFetched(n: number): void {
  const t = tally();
  if (!t) return;
  t.documents += n;
  t.reads += n;
}

/**
 * Wraps the SDK's public read entry points once per process. Every read path
 * ends in one of them: DocumentReference.get delegates to Firestore.getAll,
 * and a transaction reads through its own get/getAll (which do not call the
 * two above, so nothing is counted twice). Outside a metered call the added
 * cost is one AsyncLocalStorage lookup per read.
 *
 * If the SDK ever changes shape, metering switches itself off rather than
 * touching a read.
 */
function install(): boolean {
  if (installed !== null) return installed;
  try {
    type Fn = (...args: unknown[]) => Promise<unknown>;
    const firestore = Firestore.prototype as unknown as Record<string, Fn>;
    const query = Query.prototype as unknown as Record<string, Fn>;
    const transaction = Transaction.prototype as unknown as Record<string, Fn>;
    const originals = {
      getAll: firestore.getAll,
      queryGet: query.get,
      txGet: transaction.get,
      txGetAll: transaction.getAll,
    };
    if (Object.values(originals).some((fn) => typeof fn !== "function")) {
      installed = false;
      return false;
    }
    firestore.getAll = function(this: unknown, ...args: unknown[]) {
      countFetched(countDocuments(args));
      return originals.getAll.apply(this, args);
    };
    query.get = async function(this: unknown, ...args: unknown[]) {
      const snap = (await originals.queryGet.apply(this, args)) as {size?: number};
      countQuery(Number(snap?.size ?? 0));
      return snap;
    };
    transaction.get = async function(this: unknown, ...args: unknown[]) {
      const result = (await originals.txGet.apply(this, args)) as {size?: number};
      if (args[0] instanceof DocumentReference) countFetched(1);
      else countQuery(Number(result?.size ?? 0));
      return result;
    };
    transaction.getAll = function(this: unknown, ...args: unknown[]) {
      countFetched(countDocuments(args));
      return originals.txGetAll.apply(this, args);
    };
    installed = true;
  } catch (error) {
    logger.warn("picks_read_meter_unavailable", {
      message: error instanceof Error ? error.message : String(error),
    });
    installed = false;
  }
  return installed;
}

/**
 * Runs `fn` and counts every billed Firestore read it makes, including reads
 * in helpers that use their own Firestore handle. Concurrent calls are kept
 * apart (AsyncLocalStorage). `tally` is null when metering is unavailable.
 */
export async function meterReads<T>(fn: () => Promise<T>): Promise<{result: T; tally: ReadTally | null}> {
  if (!install()) return {result: await fn(), tally: null};
  const t: ReadTally = {reads: 0, documents: 0, queries: 0, queryDocuments: 0};
  const result = await current.run(t, fn);
  return {result, tally: t};
}
