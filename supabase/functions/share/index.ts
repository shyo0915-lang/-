// 招待の作成。RLS の customer_shares 挿入と同じ条件を通します。
// プッシュ通知は未実装で、audit_log への記録（テーブルトリガー）だけ行います。
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );

  const body = await req.json().catch(() => ({}));
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "ログインが必要です" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const { error } = await supabase.from("customer_shares").insert({
    customer_id: body.customerId,
    user_id: body.userId,
    role: body.role === "editor" ? "editor" : "viewer",
    expires_at: body.expiresAt ?? null,
    invited_by: userData.user.id,
  });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({ ok: true, notification: "通知は未実装です。共有は保存されました。" }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
