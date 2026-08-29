const { createClient } = require("@supabase/supabase-js");

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
);

function authorized(req) {
  const secret = String(process.env.CRON_SECRET || "").trim();
  if (!secret) return false;
  const header = String(req.headers.authorization || "");
  return header === `Bearer ${secret}`;
}

function createHandler(client = supabase) {
  return async function handler(req, res) {
  if (req.method !== "GET" && req.method !== "POST") {
    return res.status(405).json({ ok: false, error: "Method not allowed" });
  }
  if (!authorized(req)) {
    return res.status(401).json({ ok: false, error: "Unauthorized" });
  }

  try {
    const collectionDate = new Date().toISOString().slice(0, 10);
    const { data, error } = await client.rpc("collect_due_package_income", {
      p_collection_date: collectionDate,
    });
    if (error) {
      console.error("[cron-income] collection failed:", error.message);
      return res.status(500).json({ ok: false, error: error.message });
    }
    return res.status(200).json(data || { ok: true, date: collectionDate });
  } catch (error) {
    console.error("[cron-income] unexpected failure:", error);
    return res.status(500).json({ ok: false, error: error.message || "Income collection failed" });
    }
  };
}

module.exports = createHandler();
module.exports.createHandler = createHandler;
