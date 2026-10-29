// Saves one tester's survey answers and card picks to the project's private
// Blob store, one JSON file per response under responses/. A request with
// ?test=1 goes under tests/ instead, so checks don't mix with real answers.
// BLOB_READ_WRITE_TOKEN comes from connecting the store to the project.
import { put } from "@vercel/blob";

const MAX_BYTES = 30_000;
const MAX_TEXT = 2_000;

function clean(value, depth = 0) {
  if (typeof value === "string") return value.slice(0, MAX_TEXT);
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "boolean") return value;
  if (Array.isArray(value) && depth < 3) return value.slice(0, 40).map((v) => clean(v, depth + 1));
  if (value && typeof value === "object" && depth < 3) {
    return Object.fromEntries(
      Object.entries(value).slice(0, 40).map(([k, v]) => [String(k).slice(0, 60), clean(v, depth + 1)]),
    );
  }
  return null;
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Use POST" });
  }

  const body = typeof req.body === "string" ? safeParse(req.body) : req.body;
  if (!body || typeof body !== "object") return res.status(400).json({ error: "Expected JSON" });
  if (JSON.stringify(body).length > MAX_BYTES) return res.status(413).json({ error: "Too large" });
  // Bots fill in every field, including the hidden one people never see.
  if (body.website) return res.status(200).json({ ok: true });

  const response = {
    receivedAt: new Date().toISOString(),
    students: clean(body.students) || [],
    picks: clean(body.picks) || [],
    answers: clean(body.answers) || {},
  };

  const folder = req.query && req.query.test ? "tests" : "responses";
  try {
    await put(`${folder}/${response.receivedAt}.json`, JSON.stringify(response, null, 1), {
      access: "private",
      addRandomSuffix: true,
      contentType: "application/json",
    });
    return res.status(200).json({ ok: true });
  } catch (error) {
    console.error("Saving a response failed", error);
    return res.status(500).json({ error: "Couldn't save" });
  }
}

function safeParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
