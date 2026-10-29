// Returns every saved survey response, for the private results page.
// The caller must send the key in an X-Results-Key header. It has to match
// RESULTS_KEY, an environment variable on the Vercel project. ?test=1 returns
// the test submissions under tests/ instead of the real ones under responses/.
import { timingSafeEqual } from "node:crypto";
import { get, list } from "@vercel/blob";

function keyMatches(given) {
  const expected = process.env.RESULTS_KEY || "";
  const a = Buffer.from(String(given || ""));
  const b = Buffer.from(expected);
  return expected.length > 0 && a.length === b.length && timingSafeEqual(a, b);
}

async function read(pathname) {
  const result = await get(pathname, { access: "private", useCache: false });
  if (!result || result.statusCode !== 200) return null;
  try {
    return JSON.parse(await new Response(result.stream).text());
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Use GET" });
  }
  if (!keyMatches(req.headers["x-results-key"])) return res.status(401).json({ error: "Wrong key" });

  const prefix = req.query && req.query.test ? "tests/" : "responses/";
  try {
    const blobs = [];
    let cursor;
    do {
      const page = await list({ prefix, cursor, limit: 1000 });
      blobs.push(...page.blobs);
      cursor = page.hasMore ? page.cursor : undefined;
    } while (cursor);

    const responses = (await Promise.all(blobs.map((b) => read(b.pathname)))).filter(Boolean);
    responses.sort((x, y) => String(y.receivedAt).localeCompare(String(x.receivedAt)));
    return res.status(200).json({ folder: prefix, responses });
  } catch (error) {
    console.error("Reading responses failed", error);
    return res.status(500).json({ error: "Couldn't read responses" });
  }
}
