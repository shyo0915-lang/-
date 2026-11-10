const cfg = window.APP_CONFIG || { supabaseUrl: "", supabaseAnonKey: "" };
const hasRemote = Boolean(cfg.supabaseUrl && cfg.supabaseAnonKey);
const $ = (id) => document.getElementById(id);
const app = $("app");
let tab = "customers";
let client = null;
let session = null;
let cache = null;

const defaults = () => ({
  me: { id: "c0000000-0000-4000-8000-000000000001", name: "山田 太郎", role: "admin" },
  members: [
    { id: "c0000000-0000-4000-8000-000000000001", name: "山田 太郎", role: "admin", active: true },
    { id: "c0000000-0000-4000-8000-000000000002", name: "佐藤 花子", role: "member", active: true },
  ],
  statuses: [
    { id: "a1", label: "契約中", color: "#1A73E8", shape: "check", sort_order: 0, is_default: true, hidden: false },
    { id: "a2", label: "商談中", color: "#F9AB00", shape: "diamond", sort_order: 1, is_default: true, hidden: false },
    { id: "a3", label: "見込み", color: "#12B5CB", shape: "ring", sort_order: 2, is_default: true, hidden: false },
    { id: "a4", label: "解約・失注", color: "#5F6368", shape: "cross", sort_order: 3, is_default: true, hidden: false },
  ],
  tiers: [50000, 200000],
  customers: [
    row("d1", "（サンプル）青葉工務店", "090-0000-1101", "東京都架空区みどり町1-2-3", "次回は屋根材の見積を持参。担当の佐藤さんは午前が都合よい。", "2026-04-01", 240000, "a1", "c0000000-0000-4000-8000-000000000001", 35.6895, 139.77),
    row("d2", "（サンプル）さくら歯科", "090-0000-1102", "東京都架空区さくら台4-5-6", "院長は火曜午後が空いている。", "2026-07-15", 85000, "a1", "c0000000-0000-4000-8000-000000000001", 35.692, 139.778),
    row("d3", "（サンプル）海風ベーカリー", "090-0000-1103", "東京都架空区港南2-8-1", "店舗改装のあと再提案。", "2026-09-20", 32000, "a2", "c0000000-0000-4000-8000-000000000001", 35.6805, 139.781),
    row("d4", "（サンプル）北斗運送", "090-0000-1104", "東京都架空区北原7-1-9", "車両5台。来期予算の確認が必要。", "2026-10-02", 150000, "a3", "c0000000-0000-4000-8000-000000000001", 35.686, 139.76),
    row("d5", "（サンプル）ひなた薬局", "090-0000-1105", "東京都架空区日向1-9-2", "解約理由は価格。半年後に再訪。", "2025-12-01", 45000, "a4", "c0000000-0000-4000-8000-000000000002", 35.676, 139.768),
    row("d6", "（サンプル）星野不動産", "090-0000-1106", "東京都架空区星ケ丘5-3-8", "管理物件が3棟。理事長はメール希望。", "2026-08-08", 380000, "a2", "c0000000-0000-4000-8000-000000000001", 35.674, 139.785),
  ],
  shares: [
    { customer_id: "d2", user_id: "c0000000-0000-4000-8000-000000000002", role: "viewer" },
    { customer_id: "d3", user_id: "c0000000-0000-4000-8000-000000000002", role: "editor" },
  ],
});

function row(id, name, phone, address, memo, date, price, status, owner, lat, lng) {
  return {
    id, name, phone, address, memo, contract_date: date, unit_price: price, status_id: status,
    owner_id: owner, lat, lng, version: 1, images: [],
  };
}

function loadDemo() {
  const raw = localStorage.getItem("field-sales-crm");
  if (!raw) {
    const data = defaults();
    localStorage.setItem("field-sales-crm", JSON.stringify(data));
    return data;
  }
  return JSON.parse(raw);
}
function saveDemo(data) {
  localStorage.setItem("field-sales-crm", JSON.stringify(data));
}

function yen(n) {
  return "¥" + Number(n || 0).toLocaleString("ja-JP");
}
function tierOf(price, boundaries) {
  const sorted = [...boundaries].sort((a, b) => a - b);
  for (let i = 0; i < sorted.length; i++) if (price < sorted[i]) return i;
  return sorted.length;
}
function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
}

async function boot() {
  document.querySelectorAll("nav button").forEach((button) => {
    button.addEventListener("click", () => {
      tab = button.dataset.tab;
      document.querySelectorAll("nav button").forEach((item) => item.classList.toggle("active", item === button));
      render();
    });
  });
  $("logout").addEventListener("click", async () => {
    if (client) await client.auth.signOut();
    session = null;
    location.reload();
  });
  if (!hasRemote) {
    cache = loadDemo();
    session = cache.me;
    $("banner").textContent = "サンプルモードです。Supabase の URL と anon key を web-admin/config.js に入れると、同じ RLS の顧客DBに接続します。";
    $("who").textContent = `${session.name}（${session.role === "admin" ? "管理者" : "担当者"}）`;
    render();
    return;
  }
  $("banner").textContent = "Supabase に接続しています。表示できる顧客は、担当分・招待された分・管理者なら会社全体です。";
  const mod = await import("https://esm.sh/@supabase/supabase-js@2");
  client = mod.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  const { data } = await client.auth.getSession();
  if (!data.session) {
    renderLogin();
    return;
  }
  await afterLogin(data.session);
}

function renderLogin() {
  $("who").textContent = "";
  app.innerHTML = `
    <form class="card" id="login">
      <h2>ログイン</h2>
      <label>メールアドレス<input name="email" type="email" required /></label>
      <label>パスワード<input name="password" type="password" required /></label>
      <button class="primary" type="submit">ログイン</button>
      <p class="muted">初回ユーザーはアプリの登録、または seed の taro@example.com / password123 を使います。</p>
      <p id="login-error" class="error"></p>
    </form>`;
  $("login").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.target);
    const { data, error } = await client.auth.signInWithPassword({
      email: form.get("email"),
      password: form.get("password"),
    });
    if (error) {
      $("login-error").textContent = "ログインできませんでした";
      return;
    }
    await afterLogin(data.session);
  });
}

async function afterLogin(authSession) {
  const { data: profile, error } = await client.from("profiles").select("id, display_name, role, org_id, active").eq("id", authSession.user.id).single();
  if (error || !profile?.active) {
    app.innerHTML = `<p class="error">プロフィールを読めません。マイグレーションとサインアップを確認してください。</p>`;
    return;
  }
  session = { id: profile.id, name: profile.display_name, role: profile.role, orgId: profile.org_id };
  $("logout").hidden = false;
  $("who").textContent = `${session.name}（${session.role === "admin" ? "管理者" : "担当者"}）`;
  await reloadRemote();
  render();
}

async function reloadRemote() {
  const [customers, statuses, members, tiers, shares] = await Promise.all([
    client.from("customers").select("id, name, phone, address, memo, lat, lng, owner_id, status_id, version, contracts(id, contract_date, unit_price, format, contract_images(storage_path, page_no))").is("deleted_at", null),
    client.from("statuses").select("id, label, color, shape, sort_order, is_default, hidden").order("sort_order"),
    client.from("profiles").select("id, display_name, role, active"),
    client.from("price_tiers").select("user_id, boundaries"),
    client.from("customer_shares").select("customer_id, user_id, role, expires_at"),
  ]);
  const personal = (tiers.data || []).find((item) => item.user_id === session.id);
  const orgTier = (tiers.data || []).find((item) => !item.user_id);
  cache = {
    me: session,
    members: (members.data || []).map((item) => ({ id: item.id, name: item.display_name, role: item.role, active: item.active })),
    statuses: statuses.data || [],
    tiers: (personal || orgTier || { boundaries: [50000, 200000] }).boundaries,
    shares: shares.data || [],
    customers: (customers.data || []).map((item) => {
      const contracts = [...(item.contracts || [])].sort((a, b) => String(b.contract_date).localeCompare(String(a.contract_date)));
      const latest = contracts[0] || {};
      const image = (latest.contract_images || [])[0];
      return {
        id: item.id,
        name: item.name,
        phone: item.phone,
        address: item.address,
        memo: item.memo || "",
        contract_date: latest.contract_date || "",
        unit_price: Number(latest.unit_price || 0),
        contract_id: latest.id || null,
        status_id: item.status_id,
        owner_id: item.owner_id,
        lat: item.lat,
        lng: item.lng,
        version: item.version,
        images: image ? [image.storage_path] : [],
      };
    }),
  };
}

function statusById(id) {
  return (cache.statuses || []).find((status) => status.id === id);
}
function memberById(id) {
  return (cache.members || []).find((member) => member.id === id);
}

function render() {
  if (!cache) return;
  if (tab === "customers") renderCustomers();
  else if (tab === "statuses") renderStatuses();
  else if (tab === "tiers") renderTiers();
  else renderCsv();
}

function renderCustomers() {
  const q = (new URLSearchParams(location.hash.slice(1)).get("q")) || "";
  app.innerHTML = `
    <div class="filters">
      <input id="q" type="search" placeholder="顧客名・電話・住所・メモ" value="${esc(q)}" />
      <select id="status"></select>
      <select id="tier"></select>
      <select id="owner"></select>
    </div>
    <div class="grid-2" style="margin-top:16px">
      <div><table><thead><tr><th>顧客</th><th>ステータス</th><th>単価（1回）</th><th>担当</th><th>メモ</th></tr></thead><tbody id="rows"></tbody></table></div>
      <div id="detail" class="card"><p class="muted">行を選ぶと詳細を編集できます。</p></div>
    </div>`;
  const status = $("status");
  status.innerHTML = `<option value="">すべてのステータス</option>` + cache.statuses.map((item) => `<option value="${esc(item.id)}">${esc(item.label)}</option>`).join("");
  const tier = $("tier");
  const labels = tierLabels(cache.tiers);
  tier.innerHTML = `<option value="">すべての単価帯</option>` + labels.map((label, index) => `<option value="${index}">${esc(label)}</option>`).join("");
  const owner = $("owner");
  owner.innerHTML = `<option value="">すべての担当</option>` + cache.members.map((item) => `<option value="${esc(item.id)}">${esc(item.name)}</option>`).join("");
  const draw = () => {
    const query = $("q").value.trim().toLowerCase();
    const statusId = status.value;
    const tierIndex = tier.value;
    const ownerId = owner.value;
    const rows = cache.customers.filter((customer) => {
      const blob = `${customer.name} ${customer.phone} ${customer.address} ${customer.memo}`.toLowerCase();
      if (query && !blob.includes(query)) return false;
      if (statusId && customer.status_id !== statusId) return false;
      if (ownerId && customer.owner_id !== ownerId) return false;
      if (tierIndex !== "" && tierOf(customer.unit_price, cache.tiers) !== Number(tierIndex)) return false;
      return true;
    });
    $("rows").innerHTML = rows.map((customer) => {
      const st = statusById(customer.status_id);
      const memo = (customer.memo || "").replace(/\s+/g, " ").slice(0, 42);
      return `<tr class="clickable" data-id="${esc(customer.id)}">
        <td><strong>${esc(customer.name)}</strong><br><span class="muted">${esc(customer.address)}</span></td>
        <td><span class="pill"><i class="dot" style="background:${esc(st?.color || "#999")}"></i>${esc(st?.label || "")}</span></td>
        <td>${esc(yen(customer.unit_price))}<br><span class="muted">${esc(customer.contract_date || "")}</span></td>
        <td>${esc(memberById(customer.owner_id)?.name || "")}</td>
        <td class="memo">${esc(memo)}</td>
      </tr>`;
    }).join("");
    $("rows").querySelectorAll("tr").forEach((tr) => tr.addEventListener("click", () => showDetail(tr.dataset.id)));
  };
  ["input", "change"].forEach((name) => app.querySelector(".filters").addEventListener(name, draw));
  draw();
}

function tierLabels(boundaries) {
  const sorted = [...boundaries].map(Number).sort((a, b) => a - b);
  const labels = [];
  labels.push(`${yen(sorted[0])}未満`);
  for (let i = 0; i < sorted.length - 1; i++) labels.push(`${yen(sorted[i])}〜${yen(sorted[i + 1])}`);
  labels.push(`${yen(sorted[sorted.length - 1])}以上`);
  return labels;
}

function showDetail(id) {
  const customer = cache.customers.find((item) => item.id === id);
  if (!customer) return;
  const shares = (cache.shares || []).filter((share) => share.customer_id === id);
  $("detail").innerHTML = `
    <h2>${esc(customer.name)}</h2>
    <label>顧客名<input id="f-name" value="${esc(customer.name)}" /></label>
    <label>電話番号<input id="f-phone" value="${esc(customer.phone)}" /></label>
    <label>住所<input id="f-address" value="${esc(customer.address)}" /></label>
    <label>メモ<textarea id="f-memo">${esc(customer.memo || "")}</textarea></label>
    <label>契約日<input id="f-date" type="date" value="${esc(String(customer.contract_date).slice(0, 10))}" /></label>
    <label>単価（1回・円）<input id="f-price" inputmode="numeric" value="${esc(customer.unit_price)}" /></label>
    <label>ステータス<select id="f-status">${cache.statuses.map((status) => `<option value="${esc(status.id)}" ${status.id === customer.status_id ? "selected" : ""}>${esc(status.label)}</option>`).join("")}</select></label>
    ${session.role === "admin" ? `<label>担当<select id="f-owner">${cache.members.filter((member) => member.active !== false).map((member) => `<option value="${esc(member.id)}" ${member.id === customer.owner_id ? "selected" : ""}>${esc(member.name)}</option>`).join("")}</select></label>` : `<p>担当: ${esc(memberById(customer.owner_id)?.name || "")}</p>`}
    <div class="actions"><button class="primary" id="save">保存</button></div>
    <p id="detail-error" class="error"></p>
    <h3>契約書画像</h3>
    <div id="images"></div>
    <label>画像を追加（JPEG / PNG / PDF、10MBまで）<input id="file" type="file" accept="image/jpeg,image/png,application/pdf" /></label>
    <h3>共有</h3>
    <ul id="share-list">${shares.map((share) => `<li>${esc(memberById(share.user_id)?.name || share.user_id)}（${share.role === "editor" ? "編集者" : "閲覧者"}） <button data-revoke="${esc(share.user_id)}">解除</button></li>`).join("") || "<li>なし</li>"}</ul>
    <div class="actions">
      <select id="invite-user">${cache.members.filter((member) => member.id !== customer.owner_id && member.active !== false).map((member) => `<option value="${esc(member.id)}">${esc(member.name)}</option>`).join("")}</select>
      <select id="invite-role"><option value="viewer">閲覧者</option><option value="editor">編集者</option></select>
      <button id="invite">招待</button>
    </div>`;
  renderImages(customer);
  $("save").addEventListener("click", () => saveDetail(customer));
  $("file").addEventListener("change", (event) => uploadImage(customer, event.target.files[0]));
  $("detail").querySelectorAll("[data-revoke]").forEach((button) => button.addEventListener("click", () => revoke(customer.id, button.dataset.revoke)));
  const invite = $("invite");
  if (invite) invite.addEventListener("click", () => inviteUser(customer.id));
}

async function saveDetail(customer) {
  const next = {
    ...customer,
    name: $("f-name").value.trim(),
    phone: $("f-phone").value.trim(),
    address: $("f-address").value.trim(),
    memo: $("f-memo").value,
    contract_date: $("f-date").value,
    unit_price: Number(String($("f-price").value).replace(/[^0-9]/g, "")) || 0,
    status_id: $("f-status").value,
  };
  if (!next.name || !next.phone || !next.address || next.unit_price < 1) {
    $("detail-error").textContent = "顧客名・電話番号・住所・1円以上の単価が必要です";
    return;
  }
  if (!hasRemote) {
    if (session.role === "admin" && $("f-owner")) next.owner_id = $("f-owner").value;
    const data = loadDemo();
    data.customers = data.customers.map((item) => item.id === customer.id ? next : item);
    saveDemo(data);
    cache = data;
    render();
    return;
  }
  const { error } = await client.from("customers").update({
    name: next.name,
    phone: next.phone,
    address: next.address,
    memo: next.memo || null,
    status_id: next.status_id,
    version: customer.version,
  }).eq("id", customer.id);
  if (error) {
    $("detail-error").textContent = error.message.includes("version_conflict") ? "他の人の更新と競合しました。一覧を開き直してください。" : "保存できませんでした";
    return;
  }
  if (customer.contract_id) {
    await client.from("contracts").update({ contract_date: next.contract_date, unit_price: next.unit_price }).eq("id", customer.contract_id);
  } else {
    await client.from("contracts").insert({ customer_id: customer.id, contract_date: next.contract_date, unit_price: next.unit_price, format: "template" });
  }
  if (session.role === "admin" && $("f-owner") && $("f-owner").value !== customer.owner_id) {
    const { error: reassignError } = await client.rpc("reassign_customer", { p_customer_id: customer.id, p_new_owner: $("f-owner").value });
    if (reassignError) {
      $("detail-error").textContent = "担当の変更に失敗しました";
      return;
    }
  }
  await reloadRemote();
  render();
}

async function renderImages(customer) {
  const box = $("images");
  if (!customer.images?.length) {
    box.innerHTML = `<p class="muted">画像はまだありません。</p>`;
    return;
  }
  if (!hasRemote) {
    box.innerHTML = customer.images.map((src) => `<img class="contract" alt="契約書" src="${esc(src)}" />`).join("");
    return;
  }
  box.innerHTML = "";
  for (const path of customer.images) {
    const { data } = await client.storage.from("contract-images").createSignedUrl(path, 60);
    if (data?.signedUrl) {
      const img = document.createElement("img");
      img.className = "contract";
      img.alt = "契約書";
      img.src = data.signedUrl;
      box.appendChild(img);
    }
  }
}

async function uploadImage(customer, file) {
  if (!file) return;
  if (file.size > 10 * 1024 * 1024) {
    $("detail-error").textContent = "10MBを超えています";
    return;
  }
  if (!hasRemote) {
    const data = loadDemo();
    const url = URL.createObjectURL(file);
    data.customers = data.customers.map((item) => item.id === customer.id ? { ...item, images: [...(item.images || []), url] } : item);
    saveDemo(data);
    cache = loadDemo();
    cache.customers.find((item) => item.id === customer.id).images = data.customers.find((item) => item.id === customer.id).images;
    showDetail(customer.id);
    return;
  }
  if (!customer.contract_id) {
    $("detail-error").textContent = "先に契約日と単価を保存してください";
    return;
  }
  const path = `${session.orgId}/${customer.id}/${customer.contract_id}/${Date.now()}.jpg`;
  const { error } = await client.storage.from("contract-images").upload(path, file, { upsert: false, contentType: file.type });
  if (error) {
    $("detail-error").textContent = "画像を保存できませんでした";
    return;
  }
  await client.from("contract_images").insert({ contract_id: customer.contract_id, storage_path: path, page_no: 1 });
  await reloadRemote();
  render();
  showDetail(customer.id);
}

async function inviteUser(customerId) {
  const userId = $("invite-user").value;
  const role = $("invite-role").value;
  if (!userId) return;
  if (!hasRemote) {
    const data = loadDemo();
    data.shares = data.shares.filter((share) => !(share.customer_id === customerId && share.user_id === userId));
    data.shares.push({ customer_id: customerId, user_id: userId, role });
    saveDemo(data);
    cache = data;
    showDetail(customerId);
    return;
  }
  const { error } = await client.from("customer_shares").upsert({
    customer_id: customerId,
    user_id: userId,
    role,
    invited_by: session.id,
  });
  if (error) {
    $("detail-error").textContent = "招待できませんでした。担当者または管理者だけが共有できます。";
    return;
  }
  await reloadRemote();
  showDetail(customerId);
}

async function revoke(customerId, userId) {
  if (!hasRemote) {
    const data = loadDemo();
    data.shares = data.shares.filter((share) => !(share.customer_id === customerId && share.user_id === userId));
    saveDemo(data);
    cache = data;
    showDetail(customerId);
    return;
  }
  await client.from("customer_shares").delete().eq("customer_id", customerId).eq("user_id", userId);
  await reloadRemote();
  showDetail(customerId);
}

function renderStatuses() {
  app.innerHTML = `
    <div class="card">
      <h2>ステータス</h2>
      <p class="muted">初期ステータスは削除できません。追加は合計10個まで、色と形の組み合わせは重複できません。</p>
      <div id="status-list"></div>
      <h3>追加</h3>
      <div class="actions">
        <input id="new-label" placeholder="名前" />
        <input id="new-color" type="color" value="#e37400" />
        <select id="new-shape">
          <option value="star">星</option><option value="square">四角</option><option value="check">チェック</option>
          <option value="diamond">ひし形</option><option value="ring">リング</option><option value="cross">バツ</option>
        </select>
        <button id="add-status" class="primary">追加</button>
      </div>
      <p id="status-error" class="error"></p>
    </div>`;
  $("status-list").innerHTML = cache.statuses.map((status) => `<p><i class="dot" style="background:${esc(status.color)}"></i> ${esc(status.label)} ${status.is_default ? "（初期）" : ""} ${status.hidden ? "非表示" : ""}</p>`).join("");
  $("add-status").addEventListener("click", async () => {
    const label = $("new-label").value.trim();
    const color = $("new-color").value;
    const shape = $("new-shape").value;
    if (!label) return;
    if (cache.statuses.length >= 10) {
      $("status-error").textContent = "ステータスは10個までです";
      return;
    }
    if (cache.statuses.some((status) => status.color.toLowerCase() === color.toLowerCase() && status.shape === shape)) {
      $("status-error").textContent = "同じ色と形の組み合わせは使えません";
      return;
    }
    if (!hasRemote) {
      const data = loadDemo();
      data.statuses.push({ id: crypto.randomUUID(), label, color, shape, sort_order: data.statuses.length, is_default: false, hidden: false });
      saveDemo(data);
      cache = data;
      render();
      return;
    }
    const { error } = await client.from("statuses").insert({
      org_id: session.orgId,
      label,
      color,
      shape,
      sort_order: cache.statuses.length,
      is_default: false,
      hidden: false,
    });
    $("status-error").textContent = error ? "追加できませんでした" : "";
    if (!error) {
      await reloadRemote();
      render();
    }
  });
}

function renderTiers() {
  app.innerHTML = `
    <form class="card" id="tiers">
      <h2>単価帯</h2>
      <p class="muted">契約1件あたりの1回の金額です。境界は小さい順、2〜5段階です。自分用の表示設定として保存します。</p>
      <label>境界（カンマ区切りの円）<input name="bounds" value="${esc(cache.tiers.join(","))}" /></label>
      <button class="primary">保存</button>
      <p id="tier-error" class="error"></p>
    </form>`;
  $("tiers").addEventListener("submit", async (event) => {
    event.preventDefault();
    const boundaries = new FormData(event.target).get("bounds").split(",").map((part) => Number(part.trim())).filter((n) => Number.isFinite(n));
    if (boundaries.length < 1 || boundaries.length > 4 || boundaries.some((value, index) => value < 1 || (index > 0 && value <= boundaries[index - 1]))) {
      $("tier-error").textContent = "境界は1円以上で、小さい順に1〜4個にしてください";
      return;
    }
    if (!hasRemote) {
      const data = loadDemo();
      data.tiers = boundaries;
      saveDemo(data);
      cache = data;
      $("tier-error").textContent = "保存しました";
      return;
    }
    const existing = await client.from("price_tiers").select("id").eq("user_id", session.id).maybeSingle();
    const query = existing.data
      ? client.from("price_tiers").update({ boundaries }).eq("id", existing.data.id)
      : client.from("price_tiers").insert({ org_id: session.orgId, user_id: session.id, boundaries });
    const { error } = await query;
    $("tier-error").textContent = error ? "保存できませんでした" : "保存しました";
    if (!error) await reloadRemote();
  });
}

function renderCsv() {
  app.innerHTML = `
    <div class="card">
      <h2>CSV</h2>
      <p class="muted">列: id, name, phone, address, memo, contract_date, unit_price, status, owner_name, lat, lng。メモのカンマと改行も書き出せます。</p>
      <div class="actions"><button id="export" class="primary">書き出す</button></div>
      <label>読み込む<textarea id="import-text" placeholder="ここにCSVを貼り付け"></textarea></label>
      <button id="import">取り込み</button>
      <p id="csv-msg"></p>
    </div>`;
  $("export").addEventListener("click", () => {
    const header = ["id", "name", "phone", "address", "memo", "contract_date", "unit_price", "status", "owner_name", "lat", "lng"];
    const lines = [header.join(",")];
    for (const customer of cache.customers) {
      lines.push([
        customer.id, customer.name, customer.phone, customer.address, customer.memo || "", customer.contract_date || "",
        customer.unit_price, statusById(customer.status_id)?.label || "", memberById(customer.owner_id)?.name || "",
        customer.lat ?? "", customer.lng ?? "",
      ].map(csvEscape).join(","));
    }
    const blob = new Blob([lines.join("\n") + "\n"], { type: "text/csv;charset=utf-8" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "customers.csv";
    link.click();
  });
  $("import").addEventListener("click", importCsv);
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n\r]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  const src = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') { cell += '"'; i++; } else quoted = false;
      } else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else cell += ch;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

async function importCsv() {
  const table = parseCsv($("import-text").value);
  if (table.length < 2) {
    $("csv-msg").textContent = "CSVが空です";
    return;
  }
  const header = table[0].map((cell) => cell.trim());
  const index = Object.fromEntries(header.map((name, i) => [name, i]));
  let count = 0;
  for (const line of table.slice(1)) {
    const cell = (key) => (index[key] == null ? "" : (line[index[key]] || "").trim());
    if (!cell("name") || !cell("phone") || !cell("address")) continue;
    const price = Number(cell("unit_price").replace(/,/g, "")) || 0;
    if (price < 1) continue;
    const status = cache.statuses.find((item) => item.label === cell("status")) || cache.statuses[0];
    if (!hasRemote) {
      const data = loadDemo();
      data.customers.push(row(crypto.randomUUID(), cell("name"), cell("phone"), cell("address"), cell("memo"), cell("contract_date") || new Date().toISOString().slice(0, 10), price, status.id, session.id, Number(cell("lat")) || null, Number(cell("lng")) || null));
      saveDemo(data);
      cache = data;
      count++;
      continue;
    }
    const id = crypto.randomUUID();
    const { error } = await client.from("customers").insert({
      id,
      org_id: session.orgId,
      owner_id: session.id,
      name: cell("name"),
      phone: cell("phone"),
      address: cell("address"),
      memo: cell("memo") || null,
      lat: cell("lat") ? Number(cell("lat")) : null,
      lng: cell("lng") ? Number(cell("lng")) : null,
      location_source: cell("lat") ? "manual" : "pending",
      status_id: status.id,
    });
    if (error) {
      $("csv-msg").textContent = "取り込みを中断しました";
      return;
    }
    await client.from("contracts").insert({
      customer_id: id,
      contract_date: cell("contract_date") || new Date().toISOString().slice(0, 10),
      unit_price: price,
      format: "template",
    });
    count++;
  }
  if (hasRemote) await reloadRemote();
  $("csv-msg").textContent = `${count}件取り込みました`;
  render();
}

boot();
