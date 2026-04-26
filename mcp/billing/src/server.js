import { randomUUID } from "node:crypto";
import { Pool } from "pg";

const TOOLS = [
  "quote_cost",
  "debit",
  "credit",
  "get_balance",
  "redeem_iap_receipt",
  "list_transactions",
  "reconcile_balance"
];

const memoryState = {
  balances: new Map(),
  idempotency: new Map(),
  transactions: new Map()
};

let pool;

function getPool() {
  const connectionString = process.env.CINEFUSE_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    return null;
  }
  if (!pool) {
    pool = new Pool({ connectionString });
  }
  return pool;
}

async function getDbBalance(db, userId, defaultBalance) {
  const { rows } = await db.query(
    `SELECT balance_after
     FROM cinefuse_spark_transactions
     WHERE user_id = $1
     ORDER BY created_at DESC
     LIMIT 1`,
    [userId]
  );
  return Number(rows[0]?.balance_after ?? defaultBalance);
}

function getMemoryBalance(userId, defaultBalance) {
  return memoryState.balances.get(userId) ?? defaultBalance;
}

function recordMemoryTransaction(transaction) {
  const list = memoryState.transactions.get(transaction.userId) ?? [];
  list.push(transaction);
  memoryState.transactions.set(transaction.userId, list);
}

async function applyTransaction({
  kind,
  userId,
  amount,
  idempotencyKey,
  relatedResourceType,
  relatedResourceId,
  defaultBalance
}) {
  const db = getPool();
  const normalizedAmount = Number(amount ?? 0);
  if (!Number.isFinite(normalizedAmount) || normalizedAmount < 0) {
    throw new Error("Invalid amount");
  }
  if (!idempotencyKey) {
    throw new Error("idempotencyKey is required");
  }

  if (db) {
    const existing = await db.query(
      `SELECT id, user_id, kind, amount, idempotency_key, related_resource_type, related_resource_id, balance_after, created_at
       FROM cinefuse_spark_transactions
       WHERE idempotency_key = $1
       LIMIT 1`,
      [idempotencyKey]
    );
    if (existing.rows.length > 0) {
      return {
        transaction: existing.rows[0],
        balance: Number(existing.rows[0].balance_after)
      };
    }

    const currentBalance = await getDbBalance(db, userId, defaultBalance);
    const nextBalance = kind === "debit"
      ? currentBalance - normalizedAmount
      : currentBalance + normalizedAmount;
    if (nextBalance < 0) {
      throw new Error("insufficient sparks balance");
    }

    const tx = {
      id: randomUUID(),
      userId,
      kind,
      amount: normalizedAmount,
      idempotencyKey,
      relatedResourceType: relatedResourceType ?? null,
      relatedResourceId: relatedResourceId ?? null,
      balanceAfter: nextBalance
    };

    await db.query(
      `INSERT INTO cinefuse_spark_transactions
       (id, user_id, kind, amount, idempotency_key, related_resource_type, related_resource_id, balance_after)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [
        tx.id,
        tx.userId,
        tx.kind,
        tx.amount,
        tx.idempotencyKey,
        tx.relatedResourceType,
        tx.relatedResourceId,
        tx.balanceAfter
      ]
    );
    return { transaction: tx, balance: nextBalance };
  }

  const existing = memoryState.idempotency.get(idempotencyKey);
  if (existing) {
    return {
      transaction: existing,
      balance: getMemoryBalance(userId, defaultBalance)
    };
  }

  const currentBalance = getMemoryBalance(userId, defaultBalance);
  const nextBalance = kind === "debit"
    ? currentBalance - normalizedAmount
    : currentBalance + normalizedAmount;
  if (nextBalance < 0) {
    throw new Error("insufficient sparks balance");
  }

  const tx = {
    id: randomUUID(),
    userId,
    kind,
    amount: normalizedAmount,
    idempotencyKey,
    relatedResourceType: relatedResourceType ?? null,
    relatedResourceId: relatedResourceId ?? null,
    balanceAfter: nextBalance,
    createdAt: new Date().toISOString()
  };

  memoryState.idempotency.set(idempotencyKey, tx);
  memoryState.balances.set(userId, nextBalance);
  recordMemoryTransaction(tx);
  return { transaction: tx, balance: nextBalance };
}

async function listTransactions(userId) {
  const db = getPool();
  if (db) {
    const { rows } = await db.query(
      `SELECT id, user_id, kind, amount, idempotency_key, related_resource_type, related_resource_id, balance_after, created_at
       FROM cinefuse_spark_transactions
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [userId]
    );
    return rows;
  }
  return (memoryState.transactions.get(userId) ?? []).slice().reverse();
}

export function createServer(defaultBalance = 100000) {
  return {
    name: "billing",
    listTools() {
      return TOOLS;
    },
    async invoke(tool, input = {}) {
      if (!TOOLS.includes(tool)) {
        throw new Error(`Unknown tool: ${tool}`);
      }

      const userId = input.userId ?? input.cinefuse_user_id ?? "unknown";

      if (tool === "get_balance") {
        const db = getPool();
        const balance = db
          ? await getDbBalance(db, userId, defaultBalance)
          : getMemoryBalance(userId, defaultBalance);
        return {
          ok: true,
          server: "billing",
          tool,
          balance,
          input
        };
      }

      if (tool === "debit" || tool === "credit") {
        const result = await applyTransaction({
          kind: tool,
          userId,
          amount: input.amount,
          idempotencyKey: input.idempotencyKey,
          relatedResourceType: input.relatedResourceType,
          relatedResourceId: input.relatedResourceId,
          defaultBalance
        });
        return {
          ok: true,
          server: "billing",
          tool,
          balance: result.balance,
          transaction: result.transaction
        };
      }

      if (tool === "redeem_iap_receipt") {
        const result = await applyTransaction({
          kind: "credit",
          userId,
          amount: input.amount ?? 0,
          idempotencyKey: input.idempotencyKey ?? `iap:${input.appleTransactionId ?? randomUUID()}`,
          relatedResourceType: "iap_receipt",
          relatedResourceId: input.appleTransactionId ?? null,
          defaultBalance
        });
        return {
          ok: true,
          server: "billing",
          tool,
          balance: result.balance,
          transaction: result.transaction
        };
      }

      if (tool === "list_transactions") {
        return {
          ok: true,
          server: "billing",
          tool,
          transactions: await listTransactions(userId)
        };
      }

      if (tool === "reconcile_balance") {
        const db = getPool();
        const balance = db
          ? await getDbBalance(db, userId, defaultBalance)
          : getMemoryBalance(userId, defaultBalance);
        return {
          ok: true,
          server: "billing",
          tool,
          balance
        };
      }

      return {
        ok: true,
        server: "billing",
        tool,
        input
      };
    }
  };
}
