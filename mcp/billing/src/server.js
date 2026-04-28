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

function looksLikeUnresolvedReference(value) {
  return typeof value === "string" && value.includes("${") && value.includes("}");
}

function stripInlineSSLRootCert(rawConnectionString) {
  if (typeof rawConnectionString !== "string") {
    return rawConnectionString;
  }
  const parameter = "sslrootcert=";
  const index = rawConnectionString.indexOf(parameter);
  if (index === -1) {
    return rawConnectionString;
  }
  const valueStart = index + parameter.length;
  const nextAmpersand = rawConnectionString.indexOf("&", valueStart);
  const valueEnd = nextAmpersand === -1 ? rawConnectionString.length : nextAmpersand;
  const value = rawConnectionString.slice(valueStart, valueEnd);
  const hasInlineCert = value.includes("BEGIN")
    || value.includes("CERTIFICATE")
    || /[\n\r\t]/.test(value);
  if (!hasInlineCert) {
    return rawConnectionString;
  }
  let removeStart = index;
  if (removeStart > 0 && (rawConnectionString[removeStart - 1] === "?" || rawConnectionString[removeStart - 1] === "&")) {
    removeStart -= 1;
  }
  let removeEnd = valueEnd;
  if (removeEnd < rawConnectionString.length && rawConnectionString[removeEnd] === "&") {
    removeEnd += 1;
  }
  return rawConnectionString.slice(0, removeStart) + rawConnectionString.slice(removeEnd);
}

function firstUsableConnectionString(...candidates) {
  for (const candidate of candidates) {
    if (typeof candidate !== "string" || candidate.trim().length === 0) {
      continue;
    }
    if (looksLikeUnresolvedReference(candidate)) {
      continue;
    }
    return stripInlineSSLRootCert(candidate.trim());
  }
  return null;
}

function resolveConnectionString() {
  if (process.env.NODE_ENV === "test") {
    return firstUsableConnectionString(
      process.env.CINEFUSE_DATABASE_URL_TEST,
      process.env.DATABASE_URL_TEST,
      process.env.CINEFUSE_DATABASE_URL,
      process.env.DATABASE_URL,
      process.env.DATABASE_URL_RESOLVED,
      process.env.POSTGRES_URL
    );
  }
  return firstUsableConnectionString(
    process.env.CINEFUSE_DATABASE_URL,
    process.env.DATABASE_URL,
    process.env.DATABASE_URL_RESOLVED,
    process.env.POSTGRES_URL
  );
}

function resolvePoolConfig(connectionString) {
  const config = { connectionString };
  const sslMode = extractSSLMode(connectionString);

  const sslEnabled = ["require", "verify-ca", "verify-full"].includes(sslMode)
    || (process.env.DATABASE_SSL ?? "").toLowerCase() === "true";
  if (!sslEnabled) {
    return config;
  }

  const explicitRejectUnauthorized = process.env.DATABASE_SSL_REJECT_UNAUTHORIZED;
  const rejectUnauthorized = explicitRejectUnauthorized
    ? explicitRejectUnauthorized !== "false"
    : sslMode === "verify-full";
  const ssl = { rejectUnauthorized };
  const sslCA = process.env.DATABASE_SSL_CA ?? process.env.PGSSLROOTCERT_CONTENT;
  if (sslCA) {
    ssl.ca = sslCA.replace(/\\n/g, "\n");
  }
  config.ssl = ssl;
  return config;
}

function extractSSLMode(connectionString) {
  if (typeof connectionString !== "string") {
    return "";
  }
  try {
    const parsed = new URL(connectionString);
    return (parsed.searchParams.get("sslmode") ?? "").toLowerCase();
  } catch {
    const match = connectionString.match(/(?:\?|&)sslmode=([^&]+)/i);
    if (!match || !match[1]) {
      return "";
    }
    try {
      return decodeURIComponent(match[1]).toLowerCase();
    } catch {
      return match[1].toLowerCase();
    }
  }
}

function getPool() {
  if (process.env.NODE_ENV === "test" && process.env.CINEFUSE_USE_DB_IN_TESTS !== "true") {
    return null;
  }
  const connectionString = resolveConnectionString();
  if (!connectionString) {
    return null;
  }
  if (!pool) {
    pool = new Pool(resolvePoolConfig(connectionString));
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
