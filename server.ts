import express from "express";
import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { WebSocketServer, WebSocket } from "ws";

export interface NeighborhoodNotification {
  id: string;
  type: "ronda" | "kerja_bakti" | "agenda" | "iuran" | "pengumuman";
  title: string;
  body: string;
  sender?: string;
  role?: string;
  meta?: Record<string, unknown>;
  createdAt: string;
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT || 3000);
const MAX_RECENT = 60;
const DATA_DIR = path.resolve(__dirname, "data");
const NOTIF_FILE = path.join(DATA_DIR, "notifications.json");
const INFO_WARGA_TYPES = new Set([
  "ronda",
  "kerja_bakti",
  "agenda",
  "iuran",
  "pengumuman",
]);

function loadPersistedNotifications(): NeighborhoodNotification[] {
  try {
    if (!fs.existsSync(NOTIF_FILE)) return [];
    const raw = fs.readFileSync(NOTIF_FILE, "utf-8");
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((n) => n && INFO_WARGA_TYPES.has(String(n.type || "")))
      .slice(0, MAX_RECENT);
  } catch {
    return [];
  }
}

function savePersistedNotifications(list: NeighborhoodNotification[]) {
  try {
    if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(NOTIF_FILE, JSON.stringify(list.slice(0, MAX_RECENT), null, 2), "utf-8");
  } catch {
    // Ignore read-only filesystem edge cases
  }
}

const recentNotifications: NeighborhoodNotification[] = loadPersistedNotifications();

function addAndTrimNotification(item: NeighborhoodNotification): NeighborhoodNotification {
  const exists = recentNotifications.some((n) => n.id === item.id);
  if (!exists) {
    recentNotifications.unshift(item);
    if (recentNotifications.length > MAX_RECENT) {
      recentNotifications.length = MAX_RECENT;
    }
    savePersistedNotifications(recentNotifications);
  }
  return item;
}

function normalizeNotification(raw: Partial<NeighborhoodNotification>): NeighborhoodNotification | null {
  const rawType = String(raw.type || "pengumuman");
  if (!INFO_WARGA_TYPES.has(rawType)) {
    return null;
  }
  const type = rawType as NeighborhoodNotification["type"];
  const id =
    typeof raw.id === "string" && raw.id.trim()
      ? raw.id.trim().slice(0, 80)
      : `wk-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  return {
    id,
    type,
    title: String(raw.title || "Info Warga RT 17").trim().slice(0, 140),
    body: String(raw.body || "").trim().slice(0, 600),
    sender: raw.sender ? String(raw.sender).trim().slice(0, 80) : "Pengurus RT 17",
    role: raw.role ? String(raw.role).trim().slice(0, 40) : undefined,
    meta: raw.meta && typeof raw.meta === "object" ? raw.meta : undefined,
    createdAt: raw.createdAt || new Date().toISOString(),
  };
}

async function startServer() {
  const app = express();
  app.use(express.json({ limit: "1mb" }));

  const server = http.createServer(app);
  const wss = new WebSocketServer({ server, path: "/ws" });

  function broadcastJson(payload: unknown) {
    const encoded = JSON.stringify(payload);
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(encoded);
      }
    });
  }

  function broadcastPresence() {
    let active = 0;
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) active += 1;
    });
    broadcastJson({ event: "presence:update", activeClients: active });
  }

  wss.on("connection", (ws) => {
    let active = 0;
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) active += 1;
    });
    ws.send(
      JSON.stringify({
        event: "init",
        notifications: recentNotifications,
        activeClients: active,
      })
    );
    broadcastPresence();

    ws.on("message", (raw) => {
      try {
        const msg = JSON.parse(String(raw || "{}"));
        if (msg.event === "ping") {
          ws.send(JSON.stringify({ event: "pong", ts: Date.now() }));
          return;
        }
        if (msg.event === "notification:broadcast" && msg.payload) {
          const normalized = normalizeNotification(msg.payload);
          if (!normalized) return;
          const item = addAndTrimNotification(normalized);
          broadcastJson({ event: "notification:new", notification: item });
        } else if (msg.event === "cash:approval_update" && msg.payload) {
          broadcastJson({
            event: "cash:approval_update",
            payload: msg.payload,
            ts: Date.now(),
          });
        } else if (msg.event === "data:sync") {
          broadcastJson({
            event: "data:sync",
            reason: String(msg.reason || "update").slice(0, 80),
            ts: Date.now(),
          });
        }
      } catch {
        // Ignore malformed frames
      }
    });

    ws.on("close", () => {
      broadcastPresence();
    });
  });

  app.get("/api/health", (_req, res) => {
    res.json({ ok: true, activeClients: wss.clients.size });
  });

  app.get("/api/notifications/recent", (_req, res) => {
    res.json({ notifications: recentNotifications, activeClients: wss.clients.size });
  });

  app.post("/api/notifications/broadcast", (req, res) => {
    const body = req.body || {};
    if (!body.title && !body.body) {
      res.status(400).json({ error: "Judul atau isi notifikasi wajib diisi." });
      return;
    }
    const normalized = normalizeNotification(body);
    if (!normalized) {
      res.status(200).json({ ok: true, ignored: true });
      return;
    }
    const item = addAndTrimNotification(normalized);
    broadcastJson({ event: "notification:new", notification: item });
    res.status(201).json({ ok: true, notification: item });
  });

  if (process.env.NODE_ENV !== "production") {
    const { createServer: createViteServer } = await import("vite");
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distDir = path.resolve(__dirname, "dist");
    app.use(express.static(distDir));
    app.get("*", (_req, res) => {
      res.sendFile(path.join(distDir, "index.html"));
    });
  }

  server.listen(PORT, "0.0.0.0", () => {
    console.log(`WargaKITA 17 server & WebSocket running on http://0.0.0.0:${PORT}`);
  });
}

startServer().catch((err) => {
  console.error("Failed to start WargaKITA server:", err);
  process.exit(1);
});
