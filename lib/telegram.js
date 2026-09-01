const TELEGRAM_API = "https://api.telegram.org";

async function sendTelegramMessage(text, options = {}) {
  const token = String(process.env.TELEGRAM_BOT_TOKEN || "").trim();
  const chatId = String(options.chatId || process.env.TELEGRAM_ADMIN_CHAT_ID || "").trim();
  if (!token || !chatId) {
    return { ok: false, skipped: true, reason: "telegram_not_configured" };
  }

  const response = await fetch(`${TELEGRAM_API}/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text: String(text || ""),
      parse_mode: options.parseMode || "HTML",
      disable_web_page_preview: true,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data?.ok !== true) {
    const error = new Error(data?.description || `Telegram request failed (${response.status})`);
    error.telegramResponse = data;
    throw error;
  }
  return data;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

module.exports = { sendTelegramMessage, escapeHtml };
