const { sendTelegramMessage } = require("../lib/telegram");

function authorized(req) {
  const expected = String(process.env.TELEGRAM_WEBHOOK_SECRET || "").trim();
  if (!expected) return true;
  return String(req.headers["x-telegram-bot-api-secret-token"] || "") === expected;
}

module.exports = async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ ok: false, error: "Method not allowed" });
  if (!authorized(req)) return res.status(401).json({ ok: false, error: "Unauthorized" });

  const message = req.body?.message;
  const text = String(message?.text || "").trim();
  if (text === "/start" || text === "/status") {
    const chatId = message?.chat?.id;
    try {
      await sendTelegramMessage("Alinco Telegram connection is active.", { chatId });
    } catch (error) {
      console.error("[telegram-webhook-reply]", error.message);
      return res.status(502).json({ ok: false, error: "Telegram reply failed" });
    }
  }

  return res.status(200).json({ ok: true });
};
