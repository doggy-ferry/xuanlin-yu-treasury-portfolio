(function () {
  "use strict";
  var app = document.getElementById("app");
  var S = { backend: false, config: {}, invoices: [], snapshot: null, view: "overview", detailId: null,
            filters: { q: "", status: "all", risk: "all", source: "all", pending: false }, evalMethod: "rules_ai" };
  var ACTIONS = [
    ["approve_normal", "Approve as normal", "good"], ["confirm_exception", "Confirm exception", "bad"],
    ["reject_ai_flag", "Reject AI flag", "alt"], ["escalate", "Escalate", "alt"]
  ];
  var ACTION_LABEL = { approve_normal: "Approved as normal", confirm_exception: "Exception confirmed",
    reject_ai_flag: "AI flag rejected", escalate: "Escalated", add_note: "Note added" };
  var OUTCOME = { approve_normal: "approved_normal", confirm_exception: "exception_confirmed",
    reject_ai_flag: "ai_flag_rejected", escalate: "escalated" };
  var STATUS_LABEL = { auto_passed: "Auto-passed (low risk)", pending_review: "Human review required",
    approved_normal: "Approved as normal", exception_confirmed: "Exception confirmed",
    ai_flag_rejected: "AI flag rejected", escalated: "Escalated" };

  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function pct(x) { return (x * 100).toFixed(1) + "%"; }
  function money(v, cur) { var n = Number(v); return isNaN(n) ? esc(v) : n.toLocaleString("en-GB", { minimumFractionDigits: cur === "JPY" ? 0 : 2, maximumFractionDigits: cur === "JPY" ? 0 : 2 }); }
  function chips(codes, cls) { // one chip per code, separated by whitespace and wrapped in a flex container
    if (!codes || !codes.length) return "";
    return '<span class="codes">' + codes.map(function (c) { return '<span class="chip ' + (cls || "") + '">' + esc(c) + "</span>"; }).join(" ") + "</span>";
  }
  function riskChip(r) { return '<span class="chip ' + ({ high: "bad", medium: "warn", low: "mute", none: "ok" }[r] || "") + '">' + esc(r) + "</span>"; }
  function statusChip(s, label) { var cls = s === "auto_passed" || s === "approved_normal" || s === "ai_flag_rejected" ? "ok" : s === "pending_review" ? "warn" : "bad"; return '<span class="chip ' + cls + '">' + esc(label) + "</span>"; }

  // ---------------- data access (backend or static snapshot) ----------------
  function getJSON(url, opts) {
    return fetch(url, opts).then(function (r) { if (!r.ok) { return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.detail || r.statusText); }); } return r.json(); });
  }
  function localReviews() { try { return JSON.parse(localStorage.getItem("pj6_reviews") || "[]"); } catch (e) { return []; } }
  function saveLocalReviews(rows) { try { localStorage.setItem("pj6_reviews", JSON.stringify(rows)); } catch (e) { /* storage unavailable */ } }
  function applyLocal(v) { // static mode: recompute final status from locally stored actions
    var d = localReviews().filter(function (r) { return r.invoice_id === v.invoice_id && OUTCOME[r.action]; }).pop();
    var out = JSON.parse(JSON.stringify(v));
    if (d) { out.final_status = OUTCOME[d.action]; out.final_label = STATUS_LABEL[out.final_status]; out.review_status = "reviewed"; }
    return out;
  }
  function loadInvoices() {
    if (S.backend) return getJSON("api/invoices").then(function (x) { S.invoices = x; });
    S.invoices = S.snapshot.invoices.map(applyLocal); return Promise.resolve();
  }
  function loadDetail(id) {
    if (S.backend) return getJSON("api/invoices/" + encodeURIComponent(id));
    var d = JSON.parse(JSON.stringify(S.snapshot.details[id]));
    d.reviews = localReviews().filter(function (r) { return r.invoice_id === id; });
    d.summary = applyLocal(d.summary); return Promise.resolve(d);
  }
  function loadEvaluation() { return S.backend ? getJSON("api/evaluation") : Promise.resolve(S.snapshot.evaluation); }
  function postReview(id, action, note) {
    if (S.backend) return getJSON("api/invoices/" + encodeURIComponent(id) + "/review", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action: action, note: note }) });
    var rows = localReviews(); rows.push({ id: rows.length + 1, invoice_id: id, action: action, note: note, actor: "demo-reviewer (browser only)", timestamp: new Date().toISOString().slice(0, 19) + "Z" });
    saveLocalReviews(rows); return Promise.resolve({});
  }

  // ---------------- chrome ----------------
  function setBanner() {
    var b = document.getElementById("ai-banner"), m = document.getElementById("modeline");
    var src = S.config.ai_results_source;
    b.innerHTML = "<strong>Demo Mode.</strong> " + "Pre-generated static simulation, not live API calls.";
    var live = S.backend ? (S.config.live_available ? "Live API mode available on this server (max " + S.config.live_max_invoices + " invoices per run)." : "Live API mode is off (no ANTHROPIC_API_KEY / ANTHROPIC_MODEL on the server).") : "Static demo: no backend, so Live API mode and server-side review storage are unavailable; review actions are kept in this browser only.";
    m.innerHTML = esc(live);
    document.getElementById("mode-pill").textContent = S.backend ? "Demo Mode · API backend" : "Demo Mode · static";
  }
  function setTabs() {
    var current = S.detailId ? "queue" : S.view;
    document.querySelectorAll(".tab").forEach(function (t) { t.setAttribute("aria-selected", String(t.getAttribute("data-view") === current)); });
  }
  function go(view) { S.view = view; S.detailId = null; render(); window.scrollTo(0, 0); }
  document.querySelectorAll(".tab").forEach(function (t) { t.addEventListener("click", function () { go(t.getAttribute("data-view")); }); });

  function render() {
    setTabs();
    if (S.detailId) return renderDetail(S.detailId);
    if (S.view === "overview") return renderOverview();
    if (S.view === "queue") return renderQueue();
    return renderEvaluation();
  }

  // ---------------- overview ----------------
  function kpi(v, l, cls) { return '<div class="kpi ' + (cls || "") + '"><div class="v">' + v + '</div><div class="l">' + l + "</div></div>"; }
  function renderOverview() {
    app.textContent = "Loading…";
    loadEvaluation().then(function (e) {
      var o = e.overview;
      app.innerHTML =
        '<div class="card"><h2>Overview</h2>' +
        '<p class="note">Every figure on this page is computed by the program from the data and the locked ground truth on each load; nothing is typed in. The numbers are grouped by when they apply, so each group reconciles on its own.</p>' +
        "<h3>1. Data set (ground truth)</h3>" +
        '<div class="grid kpis">' + kpi(o.total_invoices, "Total invoices") + kpi(o.normal_ground_truth, "Normal invoices") + kpi(o.exception_ground_truth, "Invoices with a known exception") + "</div>" +
        "<h3>2. First-pass triage: rules + AI, before any human decision</h3>" +
        '<div class="grid kpis">' + kpi(o.auto_passed, "Automatically passed (low risk)", "good") + kpi(o.sent_to_human_review, "Sent to human review") +
        kpi(o.sent_true_exceptions, "…of which true exceptions") + kpi(o.sent_false_alarms, "…of which false alarms (false positives)", "warn") +
        kpi(o.auto_passed_missed_exceptions, "Exceptions missed among auto-passed (false negatives)", "warn") +
        kpi(pct(o.first_pass.precision), "Precision") + kpi(pct(o.first_pass.recall), "Recall") + kpi(pct(o.first_pass.f1), "F1 score") +
        kpi(pct(o.review_reduction_rate), "Review reduction rate (auto-passed ÷ total)") + "</div>" +
        '<p class="note">Reconciliation: ' + o.sent_to_human_review + " sent = " + o.sent_true_exceptions + " true exceptions + " + o.sent_false_alarms + " false alarms; " + o.auto_passed + " auto-passed = " + o.auto_passed_correct + " correct + " + o.auto_passed_missed_exceptions + " missed. Exceptions in the data: " + o.exception_ground_truth + " = " + o.sent_true_exceptions + " caught + " + o.auto_passed_missed_exceptions + " missed.</p>" +
        "<h3>3. Human review: current state of this session</h3>" +
        '<div class="grid kpis">' + kpi(o.human_decisions_recorded + " / " + o.sent_to_human_review, "Queue items with a decision") + kpi(o.pending_review, "Still pending") +
        kpi(o.human_confirmed_exceptions, "Confirmed as exception") + kpi(o.human_escalated, "Escalated (still flagged)") +
        kpi(o.human_ai_flags_rejected, "AI flag rejected") + kpi(o.human_approved_normal, "Approved as normal") + "</div>" +
        '<div class="grid kpis" style="margin-top:12px">' + kpi(o.after_review.fp, "False positives after review", "warn") + kpi(o.after_review.fn, "False negatives after review", "warn") +
        kpi(pct(o.after_review.precision), "Precision after review") + kpi(pct(o.after_review.recall), "Recall after review") + kpi(pct(o.after_review.f1), "F1 after review") + "</div>" +
        '<p class="note">After review, pending items still count as flagged; escalated items count as exceptions. ' + (S.backend ? "" : "This static snapshot has the scripted demo reviewer already applied (a simulation, not a person). ") + "</p>" +
        "<h3>4. Claude API usage</h3>" +
        '<div class="grid kpis">' + kpi(o.claude_api_calls, "Live Claude API calls (this session)") + kpi("$" + Number(o.estimated_api_cost_usd).toFixed(4), "Estimated API cost (configurable rate assumption)") + "</div></div>" +
        '<div class="card"><h2>Acceptance protocol</h2><p class="note">How a team would roll this out. These are procedure steps, not results.</p><ol class="protocol">' +
        "<li><strong>Verify the first normal invoices in full.</strong> Before trusting the automation, a reviewer checks the initial batch of invoices that the system passes, line by line, against source documents.</li>" +
        "<li><strong>Then review exceptions only.</strong> Once the early batch confirms the controls behave, the reviewer works the flagged queue and the low-risk queue is not reopened individually.</li>" +
        "<li><strong>Randomly spot-check auto-passed invoices.</strong> A random sample of auto-passed invoices is still inspected on an ongoing basis, to catch misses such as the false negatives above. Sample size is a policy choice for the AP team and is not fixed here.</li>" +
        "<li><strong>Escalate exceptions with evidence.</strong> An escalation carries its reason codes and a reference to comparable past cases, so the decision-maker sees why the item was flagged and how similar ones were resolved.</li></ol></div>" +
        '<div class="card"><h2>How the triage works</h2><ol><li><strong>Deterministic rules</strong> check numbers, master data, dates and duplicates on all invoices.</li>' +
        "<li><strong>AI semantic check</strong> reviews wording conflicts, vague descriptions, conditions in notes and unreadable evidence.</li>" +
        "<li><strong>Clean invoices</strong> join the low-risk queue. Everything flagged or low-confidence goes to a <strong>human</strong>, who accepts, rejects, escalates or annotates.</li></ol>" +
        '</div>';
    }).catch(fail);
  }

  // ---------------- queue ----------------
  function filtered() {
    var f = S.filters, q = f.q.trim().toLowerCase();
    return S.invoices.filter(function (v) {
      if (q && [v.invoice_id, v.supplier_name, v.invoice_number, v.po_number, v.reason_codes.join(" ")].join(" ").toLowerCase().indexOf(q) < 0) return false;
      if (f.status === "auto" && v.in_queue) return false;
      if (f.status === "flagged" && !v.in_queue) return false;
      if (f.risk !== "all" && v.risk_level !== f.risk) return false;
      if (f.source === "rule" && v.rule_status !== "exception") return false;
      if (f.source === "ai" && v.ai_status === "pass" && !v.ai_needs_review) return false;
      if (f.pending && v.final_status !== "pending_review") return false;
      return true;
    });
  }
  function queueSummary() { // counts derived from the loaded invoices, same definitions as the Overview
    var n = S.invoices.length, q = S.invoices.filter(function (v) { return v.in_queue; }).length;
    var c = function (s) { return S.invoices.filter(function (v) { return v.final_status === s; }).length; };
    return '<p class="note"><strong>' + n + "</strong> invoices · <strong>" + (n - q) + "</strong> auto-passed · <strong>" + q + "</strong> sent to human review (" +
      c("pending_review") + " pending, " + c("exception_confirmed") + " confirmed, " + c("escalated") + " escalated, " + c("ai_flag_rejected") + " AI flag rejected, " + c("approved_normal") + " approved as normal).</p>";
  }
  function opt(val, label, cur) { return '<option value="' + val + '"' + (cur === val ? " selected" : "") + ">" + label + "</option>"; }
  function renderQueue() {
    var f = S.filters;
    app.innerHTML =
      '<div class="card"><h2>Invoice Review Queue</h2><p class="note">Review mode: ground truth is hidden.</p>' + queueSummary() +
      '<form class="filters" id="filters" onsubmit="return false">' +
      '<label>Search<input type="search" id="f-q" placeholder="Invoice, supplier, PO, code" value="' + esc(f.q) + '"></label>' +
      '<label>Queue<select id="f-status">' + opt("all", "All invoices", f.status) + opt("flagged", "Flagged for review", f.status) + opt("auto", "Auto-passed (low risk)", f.status) + "</select></label>" +
      '<label>Risk level<select id="f-risk">' + opt("all", "All", f.risk) + opt("high", "High", f.risk) + opt("medium", "Medium", f.risk) + opt("low", "Low", f.risk) + opt("none", "None", f.risk) + "</select></label>" +
      '<label>Raised by<select id="f-source">' + opt("all", "Any", f.source) + opt("rule", "Rule exception", f.source) + opt("ai", "AI flag / uncertain", f.source) + "</select></label>" +
      '<label class="check"><input type="checkbox" id="f-pending"' + (f.pending ? " checked" : "") + "> Pending human review only</label></form>" +
      '<p class="note" id="count"></p><div class="tablewrap"><table class="cards"><thead><tr><th>Invoice ID</th><th>Supplier</th><th>Invoice no.</th><th>PO</th><th>Cur.</th><th class="num">Amount</th><th>Rule</th><th>AI</th><th>Final status</th><th>Risk</th><th>Reason codes</th><th>Human review</th></tr></thead><tbody id="rows"></tbody></table></div></div>';
    ["f-q", "f-status", "f-risk", "f-source", "f-pending"].forEach(function (id) {
      var el = document.getElementById(id);
      el.addEventListener(id === "f-q" ? "input" : "change", function () {
        S.filters.q = document.getElementById("f-q").value; S.filters.status = document.getElementById("f-status").value;
        S.filters.risk = document.getElementById("f-risk").value; S.filters.source = document.getElementById("f-source").value;
        S.filters.pending = document.getElementById("f-pending").checked; fillRows();
      });
    });
    fillRows();
  }
  function fillRows() {
    var rows = filtered();
    document.getElementById("count").textContent = rows.length + " of " + S.invoices.length + " invoices";
    document.getElementById("rows").innerHTML = rows.map(function (v) {
      var ruleCell = v.rule_status === "pass" ? '<span class="chip ok">pass</span>' : '<span class="chip bad">exception</span>';
      var aiCell = '<span class="chip ' + (v.ai_status === "pass" ? "ok" : v.ai_status === "exception" ? "bad" : "warn") + '">' + esc(v.ai_status) + "</span>";
      var hr = { not_required: "Not required", pending: "Pending", reviewed: "Reviewed" }[v.review_status];
      return '<tr class="row" data-id="' + esc(v.invoice_id) + '">' +
        '<td data-label="Invoice ID"><button class="rowbtn" data-open="' + esc(v.invoice_id) + '">' + esc(v.invoice_id) + "</button></td>" +
        '<td data-label="Supplier">' + esc(v.supplier_name) + "</td>" + '<td data-label="Invoice no.">' + esc(v.invoice_number) + "</td>" +
        '<td data-label="PO">' + esc(v.po_number) + "</td>" + '<td data-label="Currency">' + esc(v.currency) + "</td>" +
        '<td data-label="Amount" class="num">' + money(v.amount, v.currency) + "</td>" +
        '<td data-label="Rule status">' + ruleCell + "</td>" + '<td data-label="AI status">' + aiCell + "</td>" +
        '<td data-label="Final status">' + statusChip(v.final_status, v.final_label) + "</td>" + '<td data-label="Risk">' + riskChip(v.risk_level) + "</td>" +
        '<td data-label="Reason codes">' + (chips(v.reason_codes) || '<span class="note">none</span>') + "</td>" + '<td data-label="Human review">' + esc(hr) + "</td></tr>";
    }).join("") || '<tr><td colspan="12">No invoices match the filters.</td></tr>';
    document.querySelectorAll("[data-open]").forEach(function (b) { b.addEventListener("click", function (e) { e.stopPropagation(); S.detailId = b.getAttribute("data-open"); render(); window.scrollTo(0, 0); }); });
    document.querySelectorAll("tr.row").forEach(function (r) { r.addEventListener("click", function () { S.detailId = r.getAttribute("data-id"); render(); window.scrollTo(0, 0); }); });
  }

  // ---------------- detail ----------------
  function kv(obj, keys) { return '<dl class="kv">' + keys.map(function (k) { return "<dt>" + esc(k[1]) + "</dt><dd>" + esc(obj ? obj[k[0]] : "—") + "</dd>"; }).join("") + "</dl>"; }
  function renderDetail(id) {
    app.textContent = "Loading…";
    loadDetail(id).then(function (d) {
      var inv = d.invoice, ai = d.ai_result, s = d.summary;
      var srcText = ai.source === "live_claude" ? "Live Claude API result (run on this server)." : ai.source === "fallback" ? "Safe fallback: the AI layer failed or returned unusable output, so this invoice is routed to a human." : "Pre-generated static simulation result.";
      var findings = d.rule_findings.length ? d.rule_findings.map(function (f) { return '<div class="finding ' + f.severity + '"><strong>' + esc(f.code) + '</strong> <span class="chip ' + (f.severity === "high" ? "bad" : "warn") + '">' + esc(f.severity) + "</span><br>" + esc(f.message) + "</div>"; }).join("") : '<div class="ok-box">All deterministic controls passed.</div>';
      var lines = (d.lines || []).map(function (l) { return "<tr><td data-label=\"#\">" + esc(l.line_no) + '</td><td data-label="Description">' + esc(l.description) + '</td><td data-label="Qty" class="num">' + esc(l.quantity) + '</td><td data-label="Unit price" class="num">' + esc(l.unit_price) + '</td><td data-label="Line amount" class="num">' + esc(l.line_amount) + "</td></tr>"; }).join("");
      var hist = (d.reviews || []).map(function (r) { return "<li><strong>" + esc(ACTION_LABEL[r.action] || r.action) + "</strong> · " + esc(r.timestamp) + " · " + esc(r.actor) + (r.note ? "<br>" + esc(r.note) : "") + "</li>"; }).join("");
      var btns = ACTIONS.map(function (a) { return '<button class="btn ' + a[2] + '" data-act="' + a[0] + '">' + a[1] + "</button>"; }).join("") + '<button class="btn alt" data-act="add_note">Add review note</button>';
      app.innerHTML =
        '<p><button class="linkbtn" id="back">← Back to queue</button></p>' +
        '<div class="card"><h2>' + esc(inv.invoice_id) + " · " + esc(s.supplier_name) + " " + statusChip(s.final_status, s.final_label) + " " + riskChip(s.risk_level) + '</h2><p class="note">Review mode: ground truth is hidden.</p>' +
        '<div class="two"><div><h3>Invoice</h3>' + kv(inv, [["invoice_number", "Invoice number"], ["supplier_id", "Supplier ID"], ["po_number", "PO number"], ["currency", "Currency"], ["subtotal", "Subtotal"], ["tax", "Tax"], ["total", "Total"], ["invoice_date", "Invoice date"], ["due_date", "Due date"], ["bank_account", "Bank account"], ["description", "Description"], ["notes", "Notes"]]) + "</div>" +
        "<div><h3>Purchase order</h3>" + (d.purchase_order ? kv(d.purchase_order, [["po_number", "PO number"], ["supplier_id", "PO supplier"], ["currency", "Currency"], ["po_date", "PO date"], ["net_amount", "Net amount"], ["tax_rate", "Tax rate"], ["description", "Description"]]) : '<p class="note">No matching PO record.</p>') +
        "<h3 style=\"margin-top:14px\">Goods receipt</h3>" + (d.goods_receipt ? kv(d.goods_receipt, [["received_date", "Received"], ["received_net_amount", "Received net"], ["status", "Status"]]) : '<p class="note">No goods receipt record.</p>') +
        "<h3 style=\"margin-top:14px\">Supplier master</h3>" + (d.supplier ? kv(d.supplier, [["supplier_name", "Name"], ["bank_account", "Bank on file"], ["status", "Status"]]) : '<p class="note">Supplier not found.</p>') + "</div></div></div>" +
        '<div class="card"><h2>Invoice lines</h2><div class="tablewrap"><table class="cards"><thead><tr><th>#</th><th>Description</th><th class="num">Qty</th><th class="num">Unit price</th><th class="num">Line amount</th></tr></thead><tbody>' + lines + "</tbody></table></div></div>" +
        '<div class="two"><div class="card"><h2>Rule engine (deterministic)</h2>' + findings + "</div>" +
        '<div class="card"><h2>AI semantic check</h2><div class="disclose">' + esc(srcText) + "</div>" +
        "<p>Status: <strong>" + esc(ai.semantic_status) + "</strong> · Confidence: <strong>" + Number(ai.confidence).toFixed(2) + "</strong> · Needs human review: <strong>" + (ai.needs_human_review ? "yes" : "no") + "</strong></p><p>" + (chips(ai.reason_codes) || '<span class="note">No reason codes</span>') + "</p><p>" + esc(ai.explanation) + "</p>" +
        (S.backend ? '<button class="btn alt" id="live">Run live Claude check (1 call)</button><p class="note" id="live-msg"></p>' : '<p class="note">Live Claude check needs the local backend and your own API key.</p>') + "</div></div>" +
        '<div class="card"><h2>Human review</h2><p class="note">Decisions are recorded with time, outcome and note. Demo storage only; there are no user accounts. The AI and rules never approve payments.</p>' +
        '<label for="note" class="note">Review note</label><textarea id="note" maxlength="1000" placeholder="Reason for the decision (required for notes)"></textarea><div class="actions">' + btns + '</div><p class="note" id="msg" role="status"></p>' +
        "<h3>History</h3>" + (hist ? '<ul class="history">' + hist + "</ul>" : '<p class="note">No actions recorded yet.</p>') + "</div>";
      document.getElementById("back").addEventListener("click", function () { S.detailId = null; S.view = "queue"; render(); });
      document.querySelectorAll("[data-act]").forEach(function (b) { b.addEventListener("click", function () {
        var note = document.getElementById("note").value;
        postReview(id, b.getAttribute("data-act"), note).then(function () { return loadInvoices(); }).then(function () { renderDetail(id); })
          .catch(function (e) { document.getElementById("msg").textContent = "Not recorded: " + e.message; });
      }); });
      var live = document.getElementById("live");
      if (live) live.addEventListener("click", function () {
        live.disabled = true;
        getJSON("api/ai/live", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ invoice_ids: [id] }) })
          .then(function () { return loadInvoices(); }).then(function () { renderDetail(id); })
          .catch(function (e) { live.disabled = false; document.getElementById("live-msg").textContent = "Live check unavailable: " + e.message; });
      });
    }).catch(fail);
  }

  // ---------------- evaluation ----------------
  function renderEvaluation() {
    app.textContent = "Loading…";
    loadEvaluation().then(function (e) {
      var order = ["manual_sampling", "rules_only", "ai_only", "rules_ai", "final_human"];
      var m = e.methods, sel = m[S.evalMethod];
      var rowsM = order.map(function (k) { var x = m[k]; return "<tr><td data-label=\"Method\"><strong>" + esc(x.label) + '</strong></td><td data-label="Invoices a human checks" class="num">' + x.flagged_for_human + '</td><td data-label="TP" class="num">' + x.tp + '</td><td data-label="FP" class="num">' + x.fp + '</td><td data-label="FN" class="num">' + x.fn + '</td><td data-label="TN" class="num">' + x.tn + '</td><td data-label="Precision" class="num">' + pct(x.precision) + '</td><td data-label="Recall" class="num">' + pct(x.recall) + '</td><td data-label="F1" class="num">' + pct(x.f1) + "</td></tr>"; }).join("");
      var rowsT = e.per_type.map(function (t) { var w = t.total ? Math.round(t.combined / t.total * 100) : 0; return '<tr><td data-label="Exception type">' + esc(t.type) + '</td><td data-label="In data" class="num">' + t.total + '</td><td data-label="Rules" class="num">' + t.rules + '</td><td data-label="AI" class="num">' + t.ai + '</td><td data-label="Combined" class="num">' + t.combined + ' <span class="bar" style="width:' + Math.max(2, w * 0.6) + 'px" aria-hidden="true"></span></td><td data-label="Missed by both">' + (esc(t.missed_by_both.join(", ")) || "—") + "</td></tr>"; }).join("");
      function errList(list) { return list.length ? '<div class="tablewrap"><table class="cards"><thead><tr><th>Invoice</th><th>Ground-truth types</th><th>Rule codes</th><th>AI status / codes</th></tr></thead><tbody>' + list.map(function (r) { return '<tr><td data-label="Invoice">' + esc(r.invoice_id) + '</td><td data-label="Ground truth">' + (chips(r.ground_truth_types, "warn") || "normal") + '</td><td data-label="Rules">' + (chips(r.rule_codes) || "—") + '</td><td data-label="AI">' + esc(r.ai_status) + " " + chips(r.ai_codes) + "</td></tr>"; }).join("") + "</tbody></table></div>" : '<p class="note">None.</p>'; }
      var btns = order.map(function (k) { return '<button class="btn ' + (k === S.evalMethod ? "" : "alt") + '" data-m="' + k + '">' + esc(m[k].label) + "</button>"; }).join("");
      app.innerHTML =
        '<div class="card"><h2>Evaluation Dashboard</h2><p class="note">Evaluation view: uses the locked ground truth. Computed by the evaluator on every load from the ground-truth file. Invoice-level: an invoice counts as flagged if any control or the AI check raised it.</p>' +
        '<div class="tablewrap"><table class="cards"><thead><tr><th>Method</th><th class="num">Invoices a human checks</th><th class="num">TP</th><th class="num">FP</th><th class="num">FN</th><th class="num">TN</th><th class="num">Precision</th><th class="num">Recall</th><th class="num">F1</th></tr></thead><tbody>' + rowsM + "</tbody></table></div>" +
        '<p class="note">Final human-reviewed: ' + (m.final_human.pending_items || 0) + " queue items still pending count as flagged. Manual sampling is an assumption model (seeded sample, perfect on inspected invoices), not a measurement.</p>" +
        (S.backend ? '<div class="actions"><button class="btn alt" id="scripted">Apply scripted demo reviewer (simulation)</button><button class="btn alt" id="reset">Reset review actions</button></div>' : '<p class="note">Static snapshot: the Final row reflects a scripted demo reviewer applied when the snapshot was exported.</p>') + "</div>" +
        '<div class="card"><h2>Confusion matrix</h2><div class="methods" role="group" aria-label="Method">' + btns + "</div>" +
        '<div class="matrix"><div class="h"></div><div class="h">Predicted exception</div><div class="h">Predicted normal</div><div class="h">Actually exception</div><div class="tp"><span class="big">' + sel.tp + '</span>TP</div><div class="fn"><span class="big">' + sel.fn + '</span>FN</div><div class="h">Actually normal</div><div class="fp"><span class="big">' + sel.fp + '</span>FP</div><div class="tn"><span class="big">' + sel.tn + "</span>TN</div></div></div>" +
        '<div class="card"><h2>Detection by exception type</h2><div class="tablewrap"><table class="cards"><thead><tr><th>Exception type</th><th class="num">In data</th><th class="num">Rules</th><th class="num">AI</th><th class="num">Combined</th><th>Missed by both</th></tr></thead><tbody>' + rowsT + "</tbody></table></div></div>" +
        '<div class="card"><h2>False positives (Rules + AI)</h2>' + errList(e.errors.rules_ai_false_positives) + "<h2 style=\"margin-top:16px\">False negatives (Rules + AI)</h2>" + errList(e.errors.rules_ai_false_negatives) + "</div>" +
        '<div class="card"><h2>Assumptions</h2><ul>' + e.assumptions.map(function (a) { return "<li>" + esc(a) + "</li>"; }).join("") + "</ul></div>";
      document.querySelectorAll("[data-m]").forEach(function (b) { b.addEventListener("click", function () { S.evalMethod = b.getAttribute("data-m"); renderEvaluation(); }); });
      var sc = document.getElementById("scripted"), rs = document.getElementById("reset");
      if (sc) sc.addEventListener("click", function () { getJSON("api/reviews/scripted-reviewer", { method: "POST" }).then(loadInvoices).then(renderEvaluation).catch(fail); });
      if (rs) rs.addEventListener("click", function () { getJSON("api/reviews/reset", { method: "POST" }).then(loadInvoices).then(renderEvaluation).catch(fail); });
    }).catch(fail);
  }

  function useEmbeddedSnapshot() {
    if (!window.PJ6_SNAPSHOT) return false;
    S.backend = false; S.snapshot = window.PJ6_SNAPSHOT; S.config = S.snapshot.config; return true;
  }
  function fail(e) {
    // Backend went away (or the page was opened without one): continue with the embedded static snapshot.
    if (S.backend && e instanceof TypeError && useEmbeddedSnapshot()) {
      return loadInvoices().then(function () { setBanner(); render(); });
    }
    app.innerHTML = '<div class="card"><h2>Something went wrong</h2><p>' + esc(e && e.message ? e.message : e) + "</p></div>"; }

  // Link back to the portfolio only when hosted on the portfolio site.
  if (/github\.io$/.test(location.hostname)) { var bl = document.getElementById("back-link"); if (bl) bl.hidden = false; }

  // ---------------- boot: backend if reachable, otherwise the static snapshot ----------------
  getJSON("api/config").then(function (c) { S.backend = true; S.config = c; })
    .catch(function () { if (useEmbeddedSnapshot()) return; return getJSON("snapshot.json").then(function (snap) { S.snapshot = snap; S.config = snap.config; }); })
    .then(loadInvoices).then(function () { setBanner(); render(); }).catch(fail);
})();
