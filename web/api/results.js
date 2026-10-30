// Returns every saved survey response, for the private results page.
// The caller must send a key in an X-Results-Key header. RESULTS_KEY is Felix's
// own key. RESULTS_SHARE_KEY is the one inside the share link, and it only reads
// the real responses. Both are environment variables on the Vercel project.
// ?test=1 returns the test submissions under tests/ instead of the real ones
// under responses/, and needs RESULTS_KEY.
import { timingSafeEqual } from "node:crypto";
import { get, list } from "@vercel/blob";

function keyMatches(given, expected = "") {
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
  const given = req.headers["x-results-key"];
  const owner = keyMatches(given, process.env.RESULTS_KEY);
  const shared = !owner && keyMatches(given, process.env.RESULTS_SHARE_KEY);
  if (!owner && !shared) return res.status(401).json({ error: "Wrong key" });

  const wantsTests = Boolean(req.query && req.query.test);
  if (wantsTests && !owner) return res.status(403).json({ error: "Test answers need the results key" });
  const prefix = wantsTests ? "tests/" : "responses/";
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
