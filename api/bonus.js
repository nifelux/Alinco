/**
 * /api/bonus.js
 * POST ?action=daily-checkin
 * POST ?action=redeem-gift
 * GET  ?action=checkin-status&user_id=
 */
const { createClient } = require("@supabase/supabase-js");
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

module.exports = async function(req, res) {
  res.setHeader("Access-Control-Allow-Origin","*");
  res.setHeader("Access-Control-Allow-Methods","GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers","Content-Type");
  if(req.method==="OPTIONS") return res.status(200).end();

  const action = req.query.action;
  const user_id = req.method==="GET" ? req.query.user_id : req.body?.user_id;
  if(!user_id) return res.status(400).json({ error:"user_id required" });

  if(req.method==="GET") {
    if(action==="checkin-status") {
      const today = new Date().toISOString().slice(0,10);
      const [{ data: checkin }, { data: setting }] = await Promise.all([
        supabase.from("daily_checkins").select("id,date").eq("user_id",user_id).eq("date",today).maybeSingle(),
        supabase.from("site_settings").select("value").eq("key","daily_checkin_amount").maybeSingle()
      ]);
      const amount = Number(setting?.value);
      return res.json({ ok:true, claimed: !!checkin, date:today, amount: Number.isFinite(amount) ? amount : 50 });
    }
    return res.status(400).json({ error:"Unknown action" });
  }

  if(req.method!=="POST") return res.status(405).json({ error:"Method not allowed" });

  if(action==="daily-checkin") {
    const { data,error } = await supabase.rpc("claim_daily_bonus",{ p_user_id:user_id });
    if(error) return res.status(500).json({ error:error.message });
    return res.json(data);
  }

  if(action==="redeem-gift") {
    const { code } = req.body;
    if(!code) return res.status(400).json({ error:"code required" });
    const cleanCode = String(code).trim().toUpperCase();
    const { data,error } = await supabase.rpc("redeem_gift_code",{ p_user_id:user_id, p_code:cleanCode });
    if(error) return res.status(500).json({ ok:false, error:error.message });
    return res.json(data);
  }

  return res.status(400).json({ error:"Unknown action" });
};
       
