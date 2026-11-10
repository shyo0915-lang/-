// 住所 → 緯度経度。GOOGLE_MAPS_API_KEY はサーバー側だけに置きます。
// 未設定のときは 501 を返し、アプリは手動ピンに切り替えます。

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST のみ対応しています" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const key = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";
  if (!key) {
    return new Response(
      JSON.stringify({ error: "GOOGLE_MAPS_API_KEY が未設定です", results: [] }),
      { status: 501, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const body = await req.json().catch(() => ({}));
  const address = String(body.address ?? "").trim();
  if (!address) {
    return new Response(JSON.stringify({ error: "address が空です", results: [] }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
  url.searchParams.set("address", address);
  url.searchParams.set("language", "ja");
  url.searchParams.set("region", "jp");
  url.searchParams.set("key", key);

  const res = await fetch(url);
  const json = await res.json();
  const results = (json.results ?? []).slice(0, 5).map((r: {
    formatted_address: string;
    geometry: { location: { lat: number; lng: number } };
  }) => ({
    formattedAddress: r.formatted_address,
    lat: r.geometry.location.lat,
    lng: r.geometry.location.lng,
  }));

  return new Response(JSON.stringify({ results, status: json.status }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
