// 手書き契約のクラウドOCR。プロバイダは環境変数で差し替えます。
//
// CLOUD_OCR_URL に画像（base64）を POST し、次の JSON を期待します。
//   { "text": "...", "fields": [{ "key": "name", "value": "", "confidence": 0.9 }] }
// Authorization: Bearer ${CLOUD_OCR_KEY}
//
// Document AI などを使う場合はこの関数の中だけを置き換えます。
// アプリ側は OcrEngine インターフェース経由で呼び出します。

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const endpoint = Deno.env.get("CLOUD_OCR_URL") ?? "";
  const key = Deno.env.get("CLOUD_OCR_KEY") ?? "";
  if (!endpoint) {
    return new Response(
      JSON.stringify({
        error: "クラウドOCRが未設定です。CLOUD_OCR_URL を設定してください。",
        provider: "unconfigured",
      }),
      { status: 501, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const body = await req.json().catch(() => ({}));
  const imageBase64 = String(body.imageBase64 ?? "");
  if (!imageBase64) {
    return new Response(JSON.stringify({ error: "imageBase64 が空です" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const upstream = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(key ? { Authorization: `Bearer ${key}` } : {}),
    },
    body: JSON.stringify({
      imageBase64,
      mimeType: body.mimeType ?? "image/jpeg",
      language: "ja",
      hints: ["顧客名", "住所", "電話", "契約日", "単価"],
    }),
  });

  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
