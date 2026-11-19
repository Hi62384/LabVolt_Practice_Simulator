import { DurableObject } from "cloudflare:workers";

const hex64 = /^[a-f0-9]{64}$/;
const hex32 = /^[a-f0-9]{32}$/;

export default {
  async fetch(request, env) {
    const match = /^\/v1\/claims\/([a-f0-9]{64})(?:\/(reserve|prepare|commit|release))?$/.exec(new URL(request.url).pathname);
    if (!["POST", "GET"].includes(request.method) || !match || (request.method === "GET" && match[2])) return new Response("Not found", { status: 404 });
    const token = request.headers.get("Authorization")?.match(/^Bearer ([a-f0-9]{32})$/)?.[1];
    if (!token || !hex32.test(token) || !hex64.test(match[1])) return new Response("Unauthorized", { status: 401 });
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))),
      b => b.toString(16).padStart(2, "0")).join("");
    if (digest !== match[1]) return new Response("Unauthorized", { status: 401 });
    const holder = request.headers.get("X-Claim-Holder") ?? "";
    if (match[2] && !hex32.test(holder)) return new Response("Invalid claim holder", { status: 400 });
    if (match[2] === "reserve" && request.headers.get("X-Claim-Protocol") !== "2") {
      return new Response("Update the game before picking up this item", { status: 428 });
    }
    // Fixed 256-way sharding prevents an untrusted caller from creating a new
    // Durable Object instance for every random token it submits.
    const id = env.CLAIMS.idFromName(digest.slice(0, 2));
    return env.CLAIMS.get(id).fetch(new Request("https://claim.internal/claim/" + digest + (match[2] ? "/" + match[2] : ""), {
      method: request.method, headers: { "X-Claim-Holder": holder },
    }));
  },
};

export class Claim extends DurableObject {
  async fetch(request) {
    if (!["POST", "GET"].includes(request.method)) return new Response("Not found", { status: 404 });
    const match = /^\/claim\/([a-f0-9]{64})(?:\/(reserve|prepare|commit|release))?$/.exec(new URL(request.url).pathname);
    const digest = match?.[1];
    if (!digest) return new Response("Not found", { status: 404 });
    const key = "claim:" + digest;
    const now = Date.now();
    const current = await this.ctx.storage.get(key);
    if (request.method === "GET") {
      const state = current === true || current?.state === "claimed" ? "claimed"
        : current?.state === "prepared" || (current?.state === "reserved" && current.expires > now) ? "reserved" : "available";
      return new Response(state, { status: state === "claimed" ? 200 : state === "reserved" ? 423 : 404,
        headers: { "Cache-Control": "no-store" } });
    }
    const operation = match[2] ?? "claim";
    if (operation !== "claim") {
      const holder = request.headers.get("X-Claim-Holder");
      const state = await this.ctx.storage.transaction(async txn => {
        const record = await txn.get(key);
        if (record === true || record?.state === "claimed") {
          return operation === "commit" && record?.holder === holder ? "committed" : "claimed";
        }
        if (operation === "reserve") {
          if (record?.state === "prepared") return "busy";
          if (record?.state === "reserved" && record.expires > now && record.holder !== holder) return "busy";
          const count = Number(await txn.get("count") ?? 0);
          if (!record && count >= 1000) return "full";
          if (!record) await txn.put("count", count + 1);
          await txn.put(key, { state: "reserved", holder, expires: now + 120000 });
          return "reserved";
        }
        if (!["reserved", "prepared"].includes(record?.state) || record.holder !== holder) return "missing";
        if (operation === "prepare") {
          if (record.state === "prepared") return "prepared";
          if (record.expires <= now) return "missing";
          await txn.put(key, { state: "prepared", holder });
          return "prepared";
        }
        if (operation === "commit") {
          if (record.state !== "prepared") return "missing";
          await txn.put(key, { state: "claimed", holder });
          return "committed";
        }
        await txn.delete(key);
        await txn.put("count", Math.max(0, Number(await txn.get("count") ?? 1) - 1));
        return "released";
      });
      const status = state === "reserved" || state === "prepared" || state === "committed" || state === "released" ? 200
        : state === "claimed" ? 409 : state === "busy" ? 423 : state === "full" ? 503 : 404;
      return new Response(state, { status, headers: { "Cache-Control": "no-store" } });
    }
    const state = await this.ctx.storage.transaction(async txn => {
      const record = await txn.get(key);
      if (record === true || record?.state === "claimed") return "claimed";
      if (record?.state === "prepared" || (record?.state === "reserved" && record.expires > now)) return "busy";
      const count = Number(await txn.get("count") ?? 0);
      if (!record && count >= 1000) return "full";
      await txn.put(key, { state: "claimed" });
      if (!record) await txn.put("count", count + 1);
      return "created";
    });
    const status = state === "created" ? 201 : state === "claimed" ? 409 : state === "busy" ? 423 : 503;
    return new Response(state, { status, headers: { "Cache-Control": "no-store" } });
  }
}
