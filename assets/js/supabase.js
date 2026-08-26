/* assets/js/supabase.js
   ⚠️ PUT YOUR REAL SUPABASE CREDENTIALS BELOW
   Supabase Dashboard → Settings → API */
(function () {
  var SUPABASE_URL  = "https://aqsjnqikeeycqccrewpn.supabase.co";      // https://xxxx.supabase.co
  var SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxc2pucWlrZWV5Y3FjY3Jld3BuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2ODE2NzAsImV4cCI6MjEwMzI1NzY3MH0.l8eA4RRScwmzKkOP5Sd9bZHugB0LlkTnsa7NGJIbi1c";  // eyJhbGci...

  if (!SUPABASE_URL || SUPABASE_URL === "YOUR_SUPABASE_URL") {
    console.error("❌ ARADEL: Supabase not configured. Edit assets/js/supabase.js");
    return;
  }
  if (typeof window.supabase === "undefined") {
    console.error("❌ ARADEL: @supabase/supabase-js not loaded yet.");
    return;
  }

  window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
    auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
  });
  console.log("✅ Aradel: Supabase ready");
})();
