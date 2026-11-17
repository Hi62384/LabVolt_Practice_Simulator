import assert from "node:assert/strict";
import crypto from "node:crypto";
import { readFile } from "node:fs/promises";

const source = (await readFile(new URL("./worker.mjs", import.meta.url), "utf8"))
  .replace('import { DurableObject } from "cloudflare:workers";',
    "class DurableObject { constructor(ctx) { this.ctx = ctx; } }");
const worker = await import("data:text/javascript;base64," + Buffer.from(source).toString("base64"));
const records = new Map();
const instances = new Map();
const queues = new Map();
const env = { CLAIMS: {
  idFromName: name => name,
  get(id) {
    if (!instances.has(id)) {
      if (!records.has(id)) records.set(id, new Map());
      const data = records.get(id);
      const storage = { get: key => data.get(key), transaction(fn) {
        const next = (queues.get(id) ?? Promise.resolve()).then(() => fn({
          get: key => data.get(key), put: (key, value) => data.set(key, value), delete: key => data.delete(key),
        }));
        queues.set(id, next.catch(() => {}));
        return next;
      } };
      instances.set(id, new worker.Claim({ storage }));
    }
    return instances.get(id);
  },
} };

const token = crypto.randomBytes(16).toString("hex");
const hash = crypto.createHash("sha256").update(token).digest("hex");
const request = secret => new Request("https://claims.example/v1/claims/" + hash, {
  method: "POST", headers: { Authorization: "Bearer " + secret },
});
const status = () => new Request("https://claims.example/v1/claims/" + hash, {
  method: "GET", headers: { Authorization: "Bearer " + token },
});
assert.equal((await worker.default.fetch(status(), env)).status, 404);
const results = await Promise.all(Array.from({ length: 12 }, () => worker.default.fetch(request(token), env)));
assert.equal(results.filter(result => result.status === 201).length, 1);
assert.equal(results.filter(result => result.status === 409).length, 11);
assert.equal((await worker.default.fetch(request(crypto.randomBytes(16).toString("hex")), env)).status, 401);
instances.clear(); // Durable Object instance restarted; storage remains.
assert.equal((await worker.default.fetch(request(token), env)).status, 409);
assert.equal((await worker.default.fetch(status(), env)).status, 200);
const otherToken = crypto.randomBytes(16).toString("hex");
const otherHash = crypto.createHash("sha256").update(otherToken).digest("hex");
const otherUrl = "https://claims.example/v1/claims/" + otherHash;
const firstHolder = crypto.randomBytes(16).toString("hex");
const secondHolder = crypto.randomBytes(16).toString("hex");
const operation = (suffix, holder, method = "POST") => worker.default.fetch(new Request(otherUrl + suffix, {
  method, headers: { Authorization: "Bearer " + otherToken, "X-Claim-Holder": holder },
}), env);
assert.equal((await operation("/reserve", firstHolder)).status, 200);
assert.equal((await operation("", firstHolder, "GET")).status, 423);
assert.equal((await operation("/reserve", secondHolder)).status, 423);
assert.equal((await operation("/release", firstHolder)).status, 200);
assert.equal((await operation("", firstHolder, "GET")).status, 404);
assert.equal((await operation("/reserve", secondHolder)).status, 200);
assert.equal((await operation("/commit", secondHolder)).status, 200);
assert.equal((await operation("", secondHolder, "GET")).status, 200);
const expiringToken = crypto.randomBytes(16).toString("hex");
const expiringHash = crypto.createHash("sha256").update(expiringToken).digest("hex");
const expiringUrl = "https://claims.example/v1/claims/" + expiringHash;
const expiring = (suffix, holder, method = "POST") => worker.default.fetch(new Request(expiringUrl + suffix, {
  method, headers: { Authorization: "Bearer " + expiringToken, "X-Claim-Holder": holder },
}), env);
const realNow = Date.now;
try {
  let time = realNow();
  Date.now = () => time;
  assert.equal((await expiring("/reserve", firstHolder)).status, 200);
  time += 120001;
  assert.equal((await expiring("", firstHolder, "GET")).status, 404);
  assert.equal((await expiring("/reserve", secondHolder)).status, 200);
  assert.equal((await expiring("/commit", firstHolder)).status, 404);
  assert.equal((await expiring("/commit", secondHolder)).status, 200);
} finally {
  Date.now = realNow;
}
console.log("CLAIM_WORKER_PASS");
