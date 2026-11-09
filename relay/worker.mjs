import { DurableObject } from "cloudflare:workers";

const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const maxPacket = 1024 * 1024;
const roomSize = 8;

function newCode() {
  return Array.from(crypto.getRandomValues(new Uint8Array(10)),
    byte => alphabet[byte & 31]).join("");
}

export default {
  fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/health") return new Response("LabVolt relay v1");
    if (request.method !== "GET" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket required", { status: 426 });
    }
    const joining = /^\/v1\/join\/([2-9A-HJ-NP-Z]{10})$/.exec(path);
    const hosting = path === "/v1/host";
    if (hosting && env.REQUIRE_HOST_KEY === "1" &&
        (!env.HOST_KEY || request.headers.get("Authorization") !== "Bearer " + env.HOST_KEY)) {
      return new Response("Host authorization required", { status: 401 });
    }
    if (!hosting && !joining) return new Response("Unknown endpoint", { status: 404 });
    const code = hosting ? newCode() : joining[1];
    const room = env.ROOMS.getByName(code);
    return room.fetch(new Request("https://room.internal/" + (hosting ? "host/" : "join/") + code, request));
  },
};

export class Room extends DurableObject {
  fetch(request) {
    const [, operation, code] = new URL(request.url).pathname.split("/");
    const host = this.ctx.getWebSockets("1")[0];
    const [client, server] = Object.values(new WebSocketPair());
    const response = new Response(null, { status: 101, webSocket: client });
    if (operation === "host" ? host : !host || this.ctx.getWebSockets().length >= roomSize) {
      this.ctx.acceptWebSocket(server);
      server.send(JSON.stringify({ type: "error", message: operation === "host"
        ? "Room code collision. Try hosting again."
        : host ? "This room is full." : "Room code expired or unknown." }));
      server.close(1000, "Room unavailable");
      return response;
    }

    let id = 1;
    if (operation === "join") {
      do {
        id = crypto.getRandomValues(new Uint32Array(1))[0] & 0x7fffffff;
      } while (id < 2 || this.ctx.getWebSockets(String(id)).length);
    }
    this.ctx.acceptWebSocket(server, [String(id)]);
    server.send(JSON.stringify({ type: "ready", id, code }));
    if (host) host.send(JSON.stringify({ type: "joined", id }));
    return response;
  }

  webSocketMessage(socket, message) {
    const [tag] = this.ctx.getTags(socket);
    if (!tag) return;
    const sender = Number(tag);
    if (typeof message === "string") {
      if (sender === 1 && /^kick [0-9]+$/.test(message)) {
        const target = message.slice(5);
        if (target !== "1") this.ctx.getWebSockets(target)[0]?.close(1000, "Removed by host");
      }
      return;
    }
    if (message.byteLength < 5 || message.byteLength > maxPacket + 4) {
      socket.close(1009, "Invalid game packet");
      return;
    }
    const header = new DataView(message);
    const target = header.getInt32(0, true);
    header.setInt32(0, sender, true);
    if (sender !== 1) {
      this.send(this.ctx.getWebSockets("1")[0], message);
      return;
    }
    if (target > 1) {
      this.send(this.ctx.getWebSockets(String(target))[0], message);
      return;
    }
    for (const peer of this.ctx.getWebSockets()) {
      const [peerId] = this.ctx.getTags(peer);
      if (peerId && peerId !== "1" && Number(peerId) !== -target) this.send(peer, message);
    }
  }

  send(socket, message) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(message);
  }

  webSocketClose(socket) {
    const [id] = this.ctx.getTags(socket);
    if (id === "1") {
      for (const peer of this.ctx.getWebSockets()) {
        if (peer !== socket) peer.close(1000, "Host left");
      }
    } else if (id) {
      this.send(this.ctx.getWebSockets("1")[0], JSON.stringify({ type: "left", id: Number(id) }));
    }
  }

  webSocketError(socket) {
    this.webSocketClose(socket);
  }
}
