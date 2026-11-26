let polling = true;
let latestSnapshot = null;
let lastOptionsSignature = "";
const seenFingerprints = new Map();

function money(cents) {
  return `$${((cents || 0) / 100).toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} MXN`;
}

function shortStr(str, keep = 22) {
  if (!str) return "—";
  return str.length > keep ? `${str.slice(0, keep)}…` : str;
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = String(text ?? "");
  return div.innerHTML;
}

function checkChanged(key, obj) {
  const serialized = JSON.stringify(obj);
  const prev = seenFingerprints.get(key);
  seenFingerprints.set(key, serialized);
  return prev !== undefined && prev !== serialized;
}

function openModal(title, htmlContent) {
  document.getElementById("modalTitle").textContent = title;
  document.getElementById("modalBody").innerHTML = htmlContent;
  document.getElementById("inspectorModal").classList.remove("hidden");
}

function closeModal() {
  document.getElementById("inspectorModal").classList.add("hidden");
}

document.getElementById("closeModalBtn").addEventListener("click", closeModal);
document.getElementById("inspectorModal").addEventListener("click", (e) => {
  if (e.target.id === "inspectorModal") closeModal();
});

document.getElementById("togglePollBtn").addEventListener("click", () => {
  polling = !polling;
  const badge = document.getElementById("liveBadge");
  const text = document.getElementById("liveText");
  const btn = document.getElementById("togglePollBtn");
  if (polling) {
    badge.classList.remove("paused");
    text.textContent = "EN VIVO · 1.5s";
    btn.innerHTML = '<i class="bi bi-pause-fill"></i> Pausar';
    fetchSnapshot();
  } else {
    badge.classList.add("paused");
    text.textContent = "PAUSADO";
    btn.innerHTML = '<i class="bi bi-play-fill"></i> Reanudar';
  }
});

document.getElementById("keysBtn").addEventListener("click", () => {
  if (!latestSnapshot) return;
  const keys = latestSnapshot.keys;
  openModal("Gestión de Llaves Criptográficas (Zero-Trust)", `
    <div class="explain-box">
      Cada servicio mantiene sus llaves privadas aisladas en variables de entorno (<code>.env</code>). Las bases de datos nunca almacenan llaves privadas ni contraseñas en claro.
    </div>
    <p style="margin-top:12px;"><strong>Huella SHA-256 de Llave Simétrica AES-256-GCM (<code>DATA_ENCRYPTION_KEY</code>):</strong></p>
    <div class="detail-box">${escapeHtml(keys.aes_key_fingerprint)} (32 bytes / 256 bits)</div>

    <p><strong>Llave Pública Ed25519 de la Wallet (<code>WALLET_SIGNING_PUBLIC_KEY</code>):</strong></p>
    <div class="detail-box">${escapeHtml(keys.wallet_public_key || "No configurada")}</div>

    <p><strong>Llave Pública Ed25519 del Banco (<code>BANK_SIGNING_PUBLIC_KEY</code>):</strong></p>
    <div class="detail-box">${escapeHtml(keys.bank_public_key || "No configurada")}</div>

    <p><strong>Certificados mTLS (Tienda ↔ Banco):</strong>
      <span class="badge ${keys.mtls_configured ? "badge-green" : "badge-gold"}">
        ${keys.mtls_configured ? "CA + Certificados X.509 listos" : "Pendiente ejecutar make_certs.py"}
      </span>
    </p>
  `);
});

// ================= TABS DE LABORATORIO =================

const tabCustomBtn = document.getElementById("tabCustomBtn");
const tabPresetBtn = document.getElementById("tabPresetBtn");
const customAttackView = document.getElementById("customAttackView");
const presetAttackView = document.getElementById("presetAttackView");

tabCustomBtn.addEventListener("click", () => {
  tabCustomBtn.classList.add("active");
  tabPresetBtn.classList.remove("active");
  customAttackView.classList.remove("hidden");
  presetAttackView.classList.add("hidden");
});

tabPresetBtn.addEventListener("click", () => {
  tabPresetBtn.classList.add("active");
  tabCustomBtn.classList.remove("active");
  presetAttackView.classList.remove("hidden");
  customAttackView.classList.add("hidden");
});

// ================= CONSTRUCTOR DE ATAQUES PERSONALIZADOS =================

function buildSelectOptions(items, mapFn, emptyLabel) {
  if (!items || !items.length) {
    return `<option value="">${escapeHtml(emptyLabel)}</option>`;
  }
  return items.map(mapFn).join("");
}

function renderCustomFields(forceReset = false) {
  const container = document.getElementById("customDynamicFields");
  const attackType = document.getElementById("customAttackType").value;
  const users = latestSnapshot?.wallet?.users || [];
  const cards = latestSnapshot?.wallet?.cards || [];
  const tickets = latestSnapshot?.bank?.tickets || [];
  const orders = latestSnapshot?.store?.orders || [];

  const signature = JSON.stringify({
    attackType,
    u: users.map((x) => x.id),
    c: cards.map((x) => x.id),
    t: tickets.map((x) => `${x.ticket_id}:${x.status}`),
    o: orders.map((x) => `${x.order_id}:${x.status}`),
  });

  if (!forceReset && signature === lastOptionsSignature) {
    return;
  }

  // Preservar valores seleccionados si el usuario ya eligió algo
  const prevValues = {};
  container.querySelectorAll("select, input").forEach((el) => {
    prevValues[el.id] = el.value;
  });
  lastOptionsSignature = signature;

  const userOptions = buildSelectOptions(
    users,
    (u) => `<option value="${escapeHtml(u.id)}">${escapeHtml(u.email)} (${escapeHtml(u.id.slice(0, 8))}…)</option>`,
    "No hay usuarios en wallet.db (registra uno en la app)"
  );

  const cardOptions = buildSelectOptions(
    cards,
    (c) => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.brand.toUpperCase())} •••• ${escapeHtml(c.last4)} (${escapeHtml(c.holder_name)})</option>`,
    "No hay tarjetas en wallet.db (agrega una en la app)"
  );

  const ticketOptions = buildSelectOptions(
    tickets,
    (t) => `<option value="${escapeHtml(t.ticket_id)}">${escapeHtml(t.ticket_id)} · ${money(t.amount_cents)} [${escapeHtml(t.status.toUpperCase())}]</option>`,
    "No hay tickets en bank.db (compra uno en Banco)"
  );

  const orderOptions = buildSelectOptions(
    orders,
    (o) => `<option value="${escapeHtml(o.order_id)}">${escapeHtml(o.order_id)} · ${money(o.total_cents)} [${escapeHtml(o.status.toUpperCase())}]</option>`,
    "No hay órdenes en store.db (se creará una automática)"
  );

  if (attackType === "custom_ticket_tamper") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldTicketId">2. Ticket real en bank.db</label>
        <select id="fieldTicketId" class="form-control">${ticketOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldTamperedAmount">3. Monto falso inyectado (MXN)</label>
        <select id="fieldTamperedAmount" class="form-control">
          <option value="50000">$500.00 MXN (50,000 centavos)</option>
          <option value="20000">$200.00 MXN (20,000 centavos)</option>
          <option value="99900">$999.00 MXN (Denominación ilegal)</option>
        </select>
      </div>
    `;
  } else if (attackType === "custom_ticket_replay") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldTicketId">2. Ticket real a reutilizar (bank.db)</label>
        <select id="fieldTicketId" class="form-control">${ticketOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldOrderId">3. Orden destino en store.db (opcional)</label>
        <select id="fieldOrderId" class="form-control">
          <option value="">Crear orden nueva automáticamente</option>
          ${orders.length ? orderOptions : ""}
        </select>
      </div>
    `;
  } else if (attackType === "custom_aes_gcm_tamper") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldCardId">2. Tarjeta cifrada real (wallet.db)</label>
        <select id="fieldCardId" class="form-control">${cardOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldMode">3. Técnica de ataque simétrico</label>
        <select id="fieldMode" class="form-control">
          <option value="bitflip">Alterar 1 byte del ciphertext AES-256-GCM</option>
          <option value="aad_swap">Copiar registro a otro usuario (Sustitución AAD)</option>
        </select>
      </div>
      <div class="form-group">
        <label for="fieldSecondUserId">4. Usuario destino (si usas Sustitución AAD)</label>
        <select id="fieldSecondUserId" class="form-control">${userOptions}</select>
      </div>
    `;
  } else if (attackType === "custom_order_tamper") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldOrderId">2. Orden real en store.db</label>
        <select id="fieldOrderId" class="form-control">${orderOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldTamperedAmount">3. Monto alterado por el atacante (MXN)</label>
        <input id="fieldTamperedAmount" type="number" min="1" value="100" class="form-control" placeholder="Ej. 100 (= $1.00 MXN)" />
      </div>
    `;
  } else if (attackType === "custom_idor_attack") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldUserId">2. Usuario Atacante (JWT válido)</label>
        <select id="fieldUserId" class="form-control">${userOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldOrderId">3. Orden Víctima (store.db)</label>
        <select id="fieldOrderId" class="form-control">
          <option value="">-- Ninguna (usar tarjeta abajo) --</option>
          ${orders.length ? orderOptions : ""}
        </select>
      </div>
      <div class="form-group">
        <label for="fieldCardId">4. O Tarjeta Víctima (wallet.db)</label>
        <select id="fieldCardId" class="form-control">
          <option value="">-- Ninguna (usar orden) --</option>
          ${cards.length ? cardOptions : ""}
        </select>
      </div>
    `;
  } else if (attackType === "custom_bruteforce_user") {
    container.innerHTML = `
      <div class="form-group">
        <label for="fieldUserId">2. Usuario objetivo en wallet.db</label>
        <select id="fieldUserId" class="form-control">${userOptions}</select>
      </div>
      <div class="form-group">
        <label for="fieldMode">3. Intensidad del ataque</label>
        <select id="fieldMode" class="form-control">
          <option value="lockout">Ráfaga de 5 intentos fallidos (Activar bloqueo 423)</option>
          <option value="single">1 intento fallido (Registrar en bitácora SHA-256)</option>
        </select>
      </div>
    `;
  }

  Object.entries(prevValues).forEach(([id, val]) => {
    const el = document.getElementById(id);
    if (el && val) el.value = val;
  });
}

document.getElementById("customAttackType").addEventListener("change", () => renderCustomFields(true));

// ================= SUB-TABS: GUIADO vs EDITOR MANUAL =================

const innerTabGuided = document.getElementById("innerTabGuided");
const innerTabManual = document.getElementById("innerTabManual");
const guidedAttackView = document.getElementById("guidedAttackView");
const manualEditorView = document.getElementById("manualEditorView");

innerTabGuided.addEventListener("click", () => {
  innerTabGuided.classList.add("active");
  innerTabManual.classList.remove("active");
  guidedAttackView.classList.remove("hidden");
  manualEditorView.classList.add("hidden");
});

innerTabManual.addEventListener("click", () => {
  innerTabManual.classList.add("active");
  innerTabGuided.classList.remove("active");
  manualEditorView.classList.remove("hidden");
  guidedAttackView.classList.add("hidden");
  renderManualRecordOptions();
});

// ================= EDITOR MANUAL DE REGISTROS REALES (LEE Y ESCRIBE EN LOS .db) =================

const MANUAL_FIELD_LABELS = {
  full_name: "Nombre completo",
  password_hash: "Hash de contraseña (Argon2id)",
  failed_attempts: "Intentos fallidos",
  locked_until: "Bloqueada hasta (ISO o vacío)",
  brand: "Marca de tarjeta",
  last4: "Últimos 4 dígitos",
  holder_name: "Nombre del titular",
  pan_encrypted: "PAN cifrado (AES-256-GCM, Base64URL)",
  ticket_json: "JSON del ticket (monto, nonce, etc.)",
  signature: "Firma Ed25519 (Base64)",
  status: "Estado",
  subtotal_cents: "Subtotal (centavos)",
  discount_cents: "Descuento (centavos)",
  total_cents: "Total (centavos)",
};

let manualCurrentRecord = null; // { entity, pk, editable_fields, record }

function manualSetStatus(message, kind) {
  const el = document.getElementById("manualStatusLine");
  el.textContent = message || "";
  el.className = `manual-status-line ${kind || ""}`;
}

function manualResetEditor() {
  manualCurrentRecord = null;
  document.getElementById("manualFieldsContainer").innerHTML = "";
  document.getElementById("manualSaveBtn").disabled = true;
  document.getElementById("manualExecuteBtn").disabled = true;
  document.getElementById("manualTestPasswordWrap").classList.add("hidden");
  manualSetStatus("", "");
}

function renderManualRecordOptions() {
  const entity = document.getElementById("manualEntityType").value;
  const select = document.getElementById("manualRecordId");
  const users = latestSnapshot?.wallet?.users || [];
  const cards = latestSnapshot?.wallet?.cards || [];
  const tickets = latestSnapshot?.bank?.tickets || [];
  const orders = latestSnapshot?.store?.orders || [];

  let options = "";
  if (entity === "card") {
    options = buildSelectOptions(
      cards,
      (c) => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.brand.toUpperCase())} •••• ${escapeHtml(c.last4)} (${escapeHtml(c.holder_name)})</option>`,
      "No hay tarjetas en wallet.db"
    );
  } else if (entity === "ticket") {
    options = buildSelectOptions(
      tickets,
      (t) => `<option value="${escapeHtml(t.ticket_id)}">${escapeHtml(t.ticket_id)} · ${money(t.amount_cents)} [${escapeHtml(t.status.toUpperCase())}]</option>`,
      "No hay tickets en bank.db"
    );
  } else if (entity === "user") {
    options = buildSelectOptions(
      users,
      (u) => `<option value="${escapeHtml(u.id)}">${escapeHtml(u.email)} (${escapeHtml(u.id.slice(0, 8))}…)</option>`,
      "No hay usuarios en wallet.db"
    );
  } else if (entity === "order") {
    options = buildSelectOptions(
      orders,
      (o) => `<option value="${escapeHtml(o.order_id)}">${escapeHtml(o.order_id)} · ${money(o.total_cents)} [${escapeHtml(o.status.toUpperCase())}]</option>`,
      "No hay órdenes en store.db"
    );
  }
  select.innerHTML = options;
  manualResetEditor();
}

document.getElementById("manualEntityType").addEventListener("change", renderManualRecordOptions);

document.getElementById("manualLoadBtn").addEventListener("click", async () => {
  const entity = document.getElementById("manualEntityType").value;
  const recordId = document.getElementById("manualRecordId").value;
  if (!recordId) {
    manualSetStatus("Selecciona primero un registro real de la lista.", "error");
    return;
  }

  manualSetStatus("Cargando registro real...", "");
  try {
    const res = await fetch(`/api/record/${entity}/${encodeURIComponent(recordId)}`);
    const data = await res.json();
    if (!res.ok) {
      manualSetStatus(data.detail || "No se pudo cargar el registro.", "error");
      return;
    }

    manualCurrentRecord = data;
    const container = document.getElementById("manualFieldsContainer");
    container.innerHTML = data.editable_fields.map((field) => {
      const value = data.record[field] ?? "";
      const label = MANUAL_FIELD_LABELS[field] || field;
      const long = typeof value === "string" && value.length > 48;
      const inputEl = long
        ? `<textarea class="manual-field-input" data-field="${escapeHtml(field)}" rows="3">${escapeHtml(value)}</textarea>`
        : `<input class="manual-field-input" data-field="${escapeHtml(field)}" type="text" value="${escapeHtml(value)}" />`;
      return `
        <div class="manual-field" data-wrap="${escapeHtml(field)}">
          <label><span>${escapeHtml(label)}</span><span class="original-value">${escapeHtml(field)}</span></label>
          ${inputEl}
        </div>
      `;
    }).join("");

    container.querySelectorAll(".manual-field-input").forEach((el) => {
      const originalVal = String(data.record[el.dataset.field] ?? "");
      el.addEventListener("input", () => {
        const wrap = container.querySelector(`[data-wrap="${el.dataset.field}"]`);
        wrap.classList.toggle("dirty", el.value !== originalVal);
      });
    });

    document.getElementById("manualTestPasswordWrap").classList.toggle("hidden", entity !== "user");
    document.getElementById("manualSaveBtn").disabled = false;
    document.getElementById("manualExecuteBtn").disabled = false;
    manualSetStatus("Registro real cargado. Edita los campos y guarda, o ejecuta la prueba directamente.", "ok");
  } catch (_) {
    manualSetStatus("Error de red al cargar el registro.", "error");
  }
});

document.getElementById("manualSaveBtn").addEventListener("click", async () => {
  if (!manualCurrentRecord) return;
  const { entity, pk, record } = manualCurrentRecord;
  const recordId = record[pk];
  const container = document.getElementById("manualFieldsContainer");
  const fields = {};
  container.querySelectorAll(".manual-field-input").forEach((el) => {
    fields[el.dataset.field] = el.value;
  });

  const btn = document.getElementById("manualSaveBtn");
  const origHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<i class="bi bi-hourglass-split"></i> Escribiendo en BD real...';
  manualSetStatus("Guardando cambios directamente en el archivo .db...", "");

  try {
    const res = await fetch(`/api/record/${entity}/${encodeURIComponent(recordId)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ fields }),
    });
    const data = await res.json();
    if (!res.ok) {
      manualSetStatus(data.detail || "No se pudo guardar el registro.", "error");
      return;
    }
    manualCurrentRecord.record = data.record;
    container.querySelectorAll(".manual-field").forEach((wrap) => wrap.classList.remove("dirty"));
    manualSetStatus(`Guardado en ${manualCurrentRecord.db || "la BD"} real · campos escritos: ${data.fields_written.join(", ")}.`, "ok");
    await fetchSnapshot();
  } catch (_) {
    manualSetStatus("Error de red al guardar el registro.", "error");
  } finally {
    btn.disabled = false;
    btn.innerHTML = origHtml;
  }
});

document.getElementById("manualExecuteBtn").addEventListener("click", async () => {
  if (!manualCurrentRecord) return;
  const { entity, pk, record } = manualCurrentRecord;
  const recordId = record[pk];
  const testPassword = document.getElementById("manualTestPassword").value;

  const btn = document.getElementById("manualExecuteBtn");
  const origHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<i class="bi bi-hourglass-split"></i> Ejecutando sobre BD real...';

  try {
    const res = await fetch("/api/manual-execute", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ entity, record_id: recordId, test_password: testPassword || null }),
    });
    const data = await res.json();
    renderAttackResult(data, res.status);
    await fetchSnapshot();
  } catch (_) {
    renderAttackResult({ detail: "Error de red al ejecutar la prueba manual." }, 500);
  } finally {
    btn.disabled = false;
    btn.innerHTML = origHtml;
  }
});

// ================= EJECUCIÓN Y RENDERIZADO DEL RESULTADO =================

function renderAttackResult(data, statusCode) {
  const resultPanel = document.getElementById("attackResultPanel");
  resultPanel.classList.remove("hidden");

  if (statusCode >= 400 && !data.steps) {
    resultPanel.innerHTML = `
      <div class="result-banner alert">
        <span><i class="bi bi-exclamation-octagon-fill"></i> No se pudo ejecutar la prueba (HTTP ${statusCode})</span>
      </div>
      <div class="explain-box">${escapeHtml(data.detail || "Error desconocido")}</div>
    `;
    return;
  }

  const stepsHtml = (data.steps || []).map((s) => `<li>${escapeHtml(s)}</li>`).join("");
  const def = data.defense_mechanism || {};

  resultPanel.innerHTML = `
    <div class="result-banner ${data.blocked ? "blocked" : "alert"}">
      <span>
        <i class="bi ${data.blocked ? "bi-shield-fill-check" : "bi-shield-fill-x"}"></i>
        ${data.blocked ? "ATAQUE NEUTRALIZADO POR LA APP" : "RESPUESTA INESPERADA"} · ${escapeHtml(data.title)}
      </span>
      <span class="badge ${data.blocked ? "badge-green" : "badge-red"}">
        HTTP ${data.actual_status} · ${escapeHtml(data.target)}
      </span>
    </div>

    <div class="result-grid">
      <div>
        <ul class="step-list">${stepsHtml}</ul>
        <div class="defense-card">
          <div class="defense-card-header">
            <i class="bi bi-shield-check"></i>
            <span>Mecanismo Defensor: ${escapeHtml(def.name || "Control Criptográfico")}</span>
          </div>
          <div class="defense-meta">
            <span class="defense-pill">${escapeHtml(def.layer || "Seguridad")}</span>
            <span class="defense-pill">${escapeHtml(def.where || "")}</span>
          </div>
          <p>${escapeHtml(def.how || data.explanation || "")}</p>
        </div>
      </div>

      <div class="payload-stack">
        <div>
          <div class="code-label">Payload malicioso / parámetros enviados</div>
          <pre class="json-box">${escapeHtml(JSON.stringify(data.request_payload, null, 2))}</pre>
        </div>
        <div>
          <div class="code-label">Respuesta de rechazo del servidor (HTTP ${data.actual_status})</div>
          <pre class="json-box">${escapeHtml(JSON.stringify(data.server_response, null, 2))}</pre>
        </div>
      </div>
    </div>
  `;
}

document.getElementById("runCustomAttackBtn").addEventListener("click", async () => {
  const btn = document.getElementById("runCustomAttackBtn");
  const origHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<i class="bi bi-hourglass-split"></i> Atacando BD real...';

  const payload = {
    attack_type: document.getElementById("customAttackType").value,
    user_id: document.getElementById("fieldUserId")?.value || null,
    second_user_id: document.getElementById("fieldSecondUserId")?.value || null,
    card_id: document.getElementById("fieldCardId")?.value || null,
    ticket_id: document.getElementById("fieldTicketId")?.value || null,
    order_id: document.getElementById("fieldOrderId")?.value || null,
    tampered_amount_cents: document.getElementById("fieldTamperedAmount")
      ? Number(document.getElementById("fieldTamperedAmount").value)
      : null,
    mode: document.getElementById("fieldMode")?.value || null,
  };

  try {
    const res = await fetch("/api/custom-attack", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    renderAttackResult(data, res.status);
    await fetchSnapshot();
  } catch (_) {
    renderAttackResult({ detail: "Error de red al contactar el Inspector Web." }, 500);
  } finally {
    btn.disabled = false;
    btn.innerHTML = origHtml;
  }
});

async function runPresetAttack(attackId, btnEl) {
  const allBtns = document.querySelectorAll(".btn-attack");
  allBtns.forEach((b) => { b.disabled = true; });
  const origHtml = btnEl.innerHTML;
  btnEl.innerHTML = '<i class="bi bi-hourglass-split"></i> Ejecutando...';

  try {
    const res = await fetch(`/api/attacks/${attackId}`, { method: "POST" });
    const data = await res.json();
    renderAttackResult(data, res.status);
    await fetchSnapshot();
  } catch (_) {
    renderAttackResult({ detail: "No se pudo contactar al servidor del Inspector." }, 500);
  } finally {
    allBtns.forEach((b) => { b.disabled = false; });
    btnEl.innerHTML = origHtml;
  }
}

document.querySelectorAll(".btn-attack").forEach((btn) => {
  btn.addEventListener("click", () => runPresetAttack(btn.dataset.attack, btn));
});

// ================= MODALES INSPECTORES =================

function inspectUser(u) {
  const parts = (u.password_hash || "").split("$");
  openModal("Anatomía de Hash Argon2id + 2FA TOTP", `
    <div class="explain-box">
      <strong>Argon2id</strong> combina resistencia contra ataques por GPU (memoria configurable <code>m=65536 KB</code>) y ataques de canal lateral. Cada contraseña usa una <strong>sal aleatoria única</strong>.
    </div>
    <p style="margin-top:12px;"><strong>Usuario:</strong> ${escapeHtml(u.full_name)} (${escapeHtml(u.email)})</p>
    <p style="margin-top:8px;"><strong>Hash completo almacenado en SQLite:</strong></p>
    <div class="detail-box">${escapeHtml(u.password_hash)}</div>
    <p><strong>Desglose de parámetros:</strong></p>
    <div class="detail-box">
      Algoritmo: ${escapeHtml(parts[1] || "argon2id")}<br>
      Versión: ${escapeHtml(parts[2] || "v=19")}<br>
      Parámetros: ${escapeHtml(parts[3] || "m=65536,t=3,p=4")}<br>
      Salt (Base64): ${escapeHtml(parts[4] || "—")}<br>
      Hash derivado: ${escapeHtml(parts[5] || "—")}
    </div>
    <p><strong>Estado de bloqueo:</strong> Fallos: ${u.failed_attempts} · Bloqueado hasta: ${escapeHtml(u.locked_until || "No bloqueado")}</p>
    <p style="margin-top:6px;"><strong>Segundo Factor (TOTP RFC 6238):</strong> ${u.totp_enabled ? "ACTIVO (código dinámico cada 30s)" : "Inactivo"}</p>
  `);
}

function inspectCard(c) {
  let breakdown = "No disponible";
  try {
    const b64 = c.pan_encrypted.replace(/-/g, "+").replace(/_/g, "/");
    const raw = atob(b64);
    const bytes = Array.from(raw, (ch) => ch.charCodeAt(0).toString(16).padStart(2, "0")).join("");
    const nonceHex = bytes.slice(0, 24);
    const tagHex = bytes.slice(-32);
    const cipherHex = bytes.slice(24, -32);
    breakdown = `Nonce / IV (12 bytes): ${nonceHex}\nTexto Cifrado (PAN):   ${cipherHex}\nAuth Tag GCM (16B):    ${tagHex}`;
  } catch (_) { }

  openModal("Cifrado Simétrico Autenticado AES-256-GCM + AAD", `
    <div class="explain-box">
      El número de tarjeta (PAN) se cifra antes de tocar el disco. Además, el <code>user_id</code> se usa como <strong>AAD (Associated Authenticated Data)</strong>: si alguien copia este registro a otro usuario en la BD, el descifrado falla por etiqueta inválida. <strong>El CVV jamás se almacena.</strong>
    </div>
    <p style="margin-top:12px;"><strong>Tarjeta:</strong> ${escapeHtml(c.brand.toUpperCase())} •••• ${escapeHtml(c.last4)} (${escapeHtml(c.holder_name)})</p>
    <p><strong>Token que viaja en red:</strong> <code>${escapeHtml(c.token)}</code></p>
    <p style="margin-top:8px;"><strong>Valor cifrado en <code>cards.pan_encrypted</code>:</strong></p>
    <div class="detail-box">${escapeHtml(c.pan_encrypted)}</div>
    <p><strong>Desglose binario (Hexadecimal):</strong></p>
    <pre class="detail-box">${escapeHtml(breakdown)}</pre>
  `);
}

function inspectAudit(a) {
  openModal(`Registro de Auditoría #${a.id} · Cadena SHA-256`, `
    <div class="explain-box">
      Cada registro calcula su hash como <code>SHA256(prev_hash + canonical_json(registro))</code>. Si un atacante altera un solo carácter en SQLite, todos los hashes posteriores dejan de coincidir.
    </div>
    <p style="margin-top:12px;"><strong>Evento:</strong> ${escapeHtml(a.event)} ${a.detail ? `(${escapeHtml(a.detail)})` : ""}</p>
    <p style="margin-top:8px;"><strong>Hash Anterior (<code>prev_hash</code>):</strong></p>
    <div class="detail-box">${escapeHtml(a.prev_hash)}</div>
    <p><strong>Hash Actual (<code>hash</code>):</strong></p>
    <div class="detail-box">${escapeHtml(a.hash)}</div>
  `);
}

function inspectTicket(t) {
  openModal(`Ticket Electrónico ${t.ticket_id}`, `
    <div class="explain-box">
      Emitido por el Banco en denominación fija ($50, $100, $200 o $500) y firmado con su <strong>llave privada Ed25519</strong>. La Tienda verifica esta firma antes de aceptar el pago y el Banco lo marca como <code>SPENT</code> para impedir doble gasto.
    </div>
    <p style="margin-top:12px;"><strong>Valor:</strong> ${money(t.amount_cents)} · <strong>Estado:</strong> ${escapeHtml(t.status.toUpperCase())}</p>
    <p style="margin-top:8px;"><strong>Huella SHA-256 del Ticket:</strong></p>
    <div class="detail-box">${escapeHtml(t.ticket_hash)}</div>
    <p><strong>Firma Digital Ed25519 del Banco:</strong></p>
    <div class="detail-box">${escapeHtml(t.signature)}</div>
  `);
}

function inspectOrder(o) {
  openModal(`Orden ${o.order_id} · Recibo Firmado`, `
    <div class="explain-box">
      Al aprobarse el pago, el Banco emite un recibo con <code>order_hash</code> (SHA-256) y lo firma con <strong>Ed25519</strong>, garantizando <strong>no repudio</strong> tanto para la Tienda como para la app móvil.
    </div>
    <p style="margin-top:12px;"><strong>Estado:</strong> ${escapeHtml(o.status.toUpperCase())} · <strong>Total:</strong> ${money(o.total_cents)}</p>
    <p style="margin-top:8px;"><strong>Firma Ed25519 del Recibo Bancario:</strong></p>
    <div class="detail-box">${escapeHtml(o.receipt_signature || "Pendiente de pago")}</div>
    <p><strong>Payload JSON del Recibo:</strong></p>
    <pre class="detail-box">${escapeHtml(o.receipt_json || "{}")}</pre>
  `);
}

async function triggerTamper(action) {
  const url = action === "tamper" ? "/api/demo/tamper-audit" : "/api/demo/restore-audit";
  await fetch(url, { method: "POST" });
  await fetchSnapshot();
}

function render(data) {
  latestSnapshot = data;
  renderCustomFields(false);

  const walletTotal = data.wallet.accounts.reduce((s, a) => s + (a.balance_cents || 0), 0);
  const bankTotal = data.bank.accounts.reduce((s, a) => s + (a.balance_cents || 0), 0);
  const paidOrders = data.store.orders.filter((o) => o.status === "paid").length;

  document.getElementById("walletBalancePill").textContent = money(walletTotal);
  document.getElementById("bankBalancePill").textContent = money(bankTotal);
  document.getElementById("ordersCountPill").textContent = `${data.store.orders.length} órdenes`;

  document.getElementById("metricSymmetric").textContent =
    `${data.wallet.cards.length} tarjeta(s) cifrada(s) · Sin CVV`;
  document.getElementById("metricAsymmetric").textContent =
    data.keys.mtls_configured ? "Ed25519 + mTLS X.509 activo" : "Ed25519 (Wallet + Banco)";
  document.getElementById("metricHashing").textContent =
    data.wallet.audit_chain_valid ? "Cadena SHA-256 íntegra (OK)" : "¡ALERTA! Cadena SHA-256 rota";
  document.getElementById("metricSignatures").textContent =
    `${data.bank.tickets.length} ticket(s) · ${paidOrders} recibo(s) firmado(s)`;

  // 1. Usuarios
  const usersEl = document.getElementById("usersList");
  if (!data.wallet.users.length) {
    usersEl.innerHTML = '<div class="empty-msg">Sin usuarios registrados aún.</div>';
  } else {
    usersEl.innerHTML = data.wallet.users.slice(0, 5).map((u) => {
      const flash = checkChanged(`user:${u.id}`, u) ? "flash-new" : "";
      const isLocked = Boolean(u.locked_until);
      return `
        <div class="record-item ${flash}" data-user='${escapeHtml(JSON.stringify(u))}'>
          <div class="rec-top">
            <span class="rec-title">${escapeHtml(u.email)}</span>
            <span class="badge ${isLocked ? "badge-red" : (u.totp_enabled ? "badge-green" : "badge-blue")}">
              ${isLocked ? "BLOQUEADA (423)" : (u.totp_enabled ? "2FA TOTP ON" : "Argon2id")}
            </span>
          </div>
          <div class="mono-chip">${escapeHtml(shortStr(u.password_hash, 38))}</div>
        </div>
      `;
    }).join("");
    usersEl.querySelectorAll(".record-item").forEach((el) => {
      el.addEventListener("click", () => inspectUser(JSON.parse(el.dataset.user)));
    });
  }

  // 2. Tarjetas
  const cardsEl = document.getElementById("cardsList");
  if (!data.wallet.cards.length) {
    cardsEl.innerHTML = '<div class="empty-msg">Sin tarjetas agregadas.</div>';
  } else {
    cardsEl.innerHTML = data.wallet.cards.slice(0, 5).map((c) => {
      const flash = checkChanged(`card:${c.id}`, c) ? "flash-new" : "";
      return `
        <div class="record-item ${flash}" data-card='${escapeHtml(JSON.stringify(c))}'>
          <div class="rec-top">
            <span class="rec-title">${escapeHtml(c.brand.toUpperCase())} •••• ${escapeHtml(c.last4)}</span>
            <span class="badge badge-blue">${escapeHtml(c.token)}</span>
          </div>
          <div class="rec-sub">AES-256-GCM + AAD (clic para ver Nonce y Tag):</div>
          <div class="mono-chip">${escapeHtml(shortStr(c.pan_encrypted, 40))}</div>
        </div>
      `;
    }).join("");
    cardsEl.querySelectorAll(".record-item").forEach((el) => {
      el.addEventListener("click", () => inspectCard(JSON.parse(el.dataset.card)));
    });
  }

  // 3. Bitácora SHA-256
  const chainBanner = document.getElementById("chainStatusBanner");
  const controlsEl = document.getElementById("auditControls");
  if (data.wallet.audit_chain_valid) {
    chainBanner.className = "chain-banner valid";
    chainBanner.innerHTML = '<i class="bi bi-check-circle-fill"></i> Cadena SHA-256 ÍNTEGRA: ningún registro alterado.';
    controlsEl.innerHTML = data.wallet.audit_log.length
      ? '<button class="btn btn-danger-sm" id="tamperBtn" type="button"><i class="bi bi-bug-fill"></i> Simular alteración BD</button>'
      : "";
    const btn = document.getElementById("tamperBtn");
    if (btn) btn.addEventListener("click", () => triggerTamper("tamper"));
  } else {
    chainBanner.className = "chain-banner broken";
    chainBanner.innerHTML = '<i class="bi bi-exclamation-triangle-fill"></i> ¡CADENA ROTA! Se detectó manipulación en SQLite.';
    controlsEl.innerHTML = '<button class="btn btn-success-sm" id="restoreBtn" type="button"><i class="bi bi-arrow-counterclockwise"></i> Restaurar BD</button>';
    document.getElementById("restoreBtn").addEventListener("click", () => triggerTamper("restore"));
  }

  const auditEl = document.getElementById("auditList");
  if (!data.wallet.audit_log.length) {
    auditEl.innerHTML = '<div class="empty-msg">Sin eventos en bitácora.</div>';
  } else {
    auditEl.innerHTML = data.wallet.audit_log.slice(0, 8).map((a) => {
      const flash = checkChanged(`audit:${a.id}`, a) ? "flash-new" : "";
      return `
        <div class="record-item ${flash}" data-audit='${escapeHtml(JSON.stringify(a))}'>
          <div class="rec-top">
            <span class="rec-title">#${a.id} · ${escapeHtml(a.event)}</span>
            <span class="rec-sub">${escapeHtml(a.detail || "")}</span>
          </div>
          <div class="mono-chip">prev: ${escapeHtml(shortStr(a.prev_hash, 12))} → hash: ${escapeHtml(shortStr(a.hash, 16))}</div>
        </div>
      `;
    }).join("");
    auditEl.querySelectorAll(".record-item").forEach((el) => {
      el.addEventListener("click", () => inspectAudit(JSON.parse(el.dataset.audit)));
    });
  }

  // 4. Banco - Cuentas
  const bankAccEl = document.getElementById("bankAccountsList");
  if (!data.bank.accounts.length) {
    bankAccEl.innerHTML = '<div class="empty-msg">Sin cuentas bancarias vinculadas.</div>';
  } else {
    bankAccEl.innerHTML = data.bank.accounts.slice(0, 5).map((acc) => {
      const flash = checkChanged(`bank_acc:${acc.id}`, acc) ? "flash-new" : "";
      return `
        <div class="record-item ${flash}">
          <div class="rec-top">
            <span class="rec-title">Cuenta ${escapeHtml(acc.account_masked)}</span>
            <span class="badge badge-green">${money(acc.balance_cents)}</span>
          </div>
          <div class="rec-sub">owner_ref: ${escapeHtml(shortStr(acc.owner_ref, 24))} · Estado: ${escapeHtml(acc.status)}</div>
        </div>
      `;
    }).join("");
  }

  // 5. Banco - OAuth2 PKCE
  const oauthEl = document.getElementById("oauthList");
  if (!data.bank.oauth_codes.length) {
    oauthEl.innerHTML = '<div class="empty-msg">Aún no se ha ejecutado vinculación OAuth2 + PKCE.</div>';
  } else {
    oauthEl.innerHTML = data.bank.oauth_codes.slice(0, 4).map((oc) => {
      const flash = checkChanged(`oauth:${oc.id}`, oc) ? "flash-new" : "";
      return `
        <div class="record-item ${flash}">
          <div class="rec-top">
            <span class="rec-title">Autorización PKCE #${oc.id}</span>
            <span class="badge ${oc.used ? "badge-green" : "badge-gold"}">${oc.used ? "Canjeado (1 solo uso)" : "Pendiente"}</span>
          </div>
          <div class="mono-chip">code_hash (SHA-256): ${escapeHtml(shortStr(oc.code_hash, 26))}</div>
        </div>
      `;
    }).join("");
  }

  // 6. Banco - Tickets Electrónicos
  const ticketsEl = document.getElementById("ticketsList");
  if (!data.bank.tickets.length) {
    ticketsEl.innerHTML = '<div class="empty-msg">Sin tickets adquiridos aún.</div>';
  } else {
    ticketsEl.innerHTML = data.bank.tickets.slice(0, 6).map((t) => {
      const flash = checkChanged(`tkt:${t.ticket_id}`, t) ? "flash-new" : "";
      const active = t.status === "active";
      return `
        <div class="record-item ${flash}" data-ticket='${escapeHtml(JSON.stringify(t))}'>
          <div class="rec-top">
            <span class="rec-title">${escapeHtml(t.ticket_id)} · ${money(t.amount_cents)}</span>
            <span class="badge ${active ? "badge-green" : "badge-red"}">${active ? "ACTIVO" : "GASTADO"}</span>
          </div>
          <div class="mono-chip">Ed25519: ${escapeHtml(shortStr(t.signature, 32))}</div>
        </div>
      `;
    }).join("");
    ticketsEl.querySelectorAll(".record-item").forEach((el) => {
      el.addEventListener("click", () => inspectTicket(JSON.parse(el.dataset.ticket)));
    });
  }

  // 7. Tienda - Órdenes
  const ordersEl = document.getElementById("ordersList");
  if (!data.store.orders.length) {
    ordersEl.innerHTML = '<div class="empty-msg">Sin órdenes creadas en la Tienda.</div>';
  } else {
    ordersEl.innerHTML = data.store.orders.slice(0, 5).map((o) => {
      const flash = checkChanged(`ord:${o.order_id}`, o) ? "flash-new" : "";
      const paid = o.status === "paid";
      return `
        <div class="record-item ${flash}" data-order='${escapeHtml(JSON.stringify(o))}'>
          <div class="rec-top">
            <span class="rec-title">${escapeHtml(o.order_id)} · ${money(o.total_cents)}</span>
            <span class="badge ${paid ? "badge-green" : "badge-gold"}">${escapeHtml(o.status.toUpperCase())}</span>
          </div>
          <div class="mono-chip">Recibo Ed25519: ${escapeHtml(shortStr(o.receipt_signature, 30))}</div>
        </div>
      `;
    }).join("");
    ordersEl.querySelectorAll(".record-item").forEach((el) => {
      el.addEventListener("click", () => inspectOrder(JSON.parse(el.dataset.order)));
    });
  }

  // 8. Tienda - Tickets Gastados
  const spentEl = document.getElementById("spentTicketsList");
  if (!data.store.spent_tickets.length) {
    spentEl.innerHTML = '<div class="empty-msg">Ningún ticket canjeado en tienda aún.</div>';
  } else {
    spentEl.innerHTML = data.store.spent_tickets.slice(0, 5).map((st) => {
      const flash = checkChanged(`spent:${st.ticket_id}`, st) ? "flash-new" : "";
      return `
        <div class="record-item ${flash}">
          <div class="rec-top">
            <span class="rec-title">${escapeHtml(st.ticket_id)} (${money(st.amount_cents)})</span>
            <span class="badge badge-red">BLOQUEADO</span>
          </div>
          <div class="rec-sub">Orden: ${escapeHtml(st.order_id)} · SHA-256: ${escapeHtml(shortStr(st.ticket_hash, 18))}</div>
        </div>
      `;
    }).join("");
  }
}

async function fetchSnapshot() {
  try {
    const res = await fetch("/api/snapshot");
    if (!res.ok) return;
    const data = await res.json();
    render(data);
  } catch (_) { }
}

fetchSnapshot();
setInterval(() => {
  if (polling) fetchSnapshot();
}, 1500);