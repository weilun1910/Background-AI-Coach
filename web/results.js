// The private results page. It asks for the results key once, keeps it in this
// browser, and reads every response from /api/results. Question wording comes
// from survey.json and student names from walkthrough.json, so it stays in step
// with whatever testers saw.

const KEY_STORE = "coach-results-key";
const root = document.getElementById("results");

let survey = null;
let students = {};
let key = readKey();
let showTests = new URLSearchParams(location.search).has("test");
let data = null;
let loadedAt = null;

Promise.all([getJSON("survey.json"), getJSON("walkthrough.json")])
  .then(([surveyData, walkthrough]) => {
    survey = surveyData;
    students = Object.fromEntries(walkthrough.personas.map((p) => [p.id, p.name]));
    key ? load() : renderLock();
  })
  .catch(() => {
    root.innerHTML = `<p class="loading">This page didn't load. Try refreshing.</p>`;
  });

function getJSON(path) {
  return fetch(path).then((response) => {
    if (!response.ok) throw new Error(response.status);
    return response.json();
  });
}

function readKey() {
  try {
    return localStorage.getItem(KEY_STORE) || "";
  } catch {
    return "";
  }
}

function saveKey(value) {
  try {
    value ? localStorage.setItem(KEY_STORE, value) : localStorage.removeItem(KEY_STORE);
  } catch {
    // Without storage the key just has to be entered again next visit.
  }
}

function esc(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

// MARK: Lock

function renderLock(message = "") {
  document.title = "Survey Results";
  root.innerHTML = `
    <main class="lock">
      <div class="eyebrow">${sparkle()} Coachmark</div>
      <h1>Survey results</h1>
      <p class="sub">Enter the results key to see what testers said.</p>
      <form id="lock">
        <input type="password" id="key" autocomplete="current-password" placeholder="Results key" aria-label="Results key">
        <button class="btn btn-primary" type="submit">Open</button>
      </form>
      <p class="form-error" role="alert">${esc(message)}</p>
    </main>`;
  const input = root.querySelector("#key");
  input.focus();
  root.querySelector("#lock").addEventListener("submit", (event) => {
    event.preventDefault();
    key = input.value.trim();
    if (!key) return;
    saveKey(key);
    load();
  });
}

// MARK: Loading

async function load() {
  const refresh = root.querySelector("#refresh");
  if (refresh) {
    refresh.disabled = true;
    refresh.textContent = "Refreshing...";
  }
  try {
    const response = await fetch(`/api/results${showTests ? "?test=1" : ""}`, {
      headers: { "X-Results-Key": key },
      cache: "no-store",
    });
    if (response.status === 401) {
      key = "";
      saveKey("");
      return renderLock("That key didn't work.");
    }
    if (!response.ok) throw new Error(response.status);
    data = await response.json();
    loadedAt = new Date();
    render();
  } catch {
    if (data) {
      render("Couldn't refresh. Showing what loaded last time.");
    } else {
      root.innerHTML = `<main class="report"><p class="form-error">Couldn't load the responses. Check your connection and refresh.</p></main>`;
    }
  }
}

// MARK: Report

function render(warning = "") {
  const responses = data.responses;
  const n = responses.length;
  document.title = `Survey Results (${n})`;
  const time = loadedAt.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

  root.innerHTML = `
    <main class="report">
      <div class="eyebrow">${sparkle()} Coachmark</div>
      <div class="report-head">
        <div>
          <h1>Survey results${showTests ? ` <span class="test-tag">Test answers</span>` : ""}</h1>
          <p class="sub">${n === 1 ? "1 response" : `${n} responses`}. Updated at ${esc(time)}.</p>
        </div>
        <div class="report-actions">
          <button class="btn btn-primary" id="refresh">Refresh</button>
          <button class="btn btn-secondary" id="csv"${n ? "" : " disabled"}>Download CSV</button>
          <label class="toggle"><input type="checkbox" id="tests"${showTests ? " checked" : ""}> Show test answers</label>
          <button class="btn btn-text" id="forget">Lock</button>
        </div>
      </div>
      ${warning ? `<p class="note">${esc(warning)}</p>` : ""}
      ${n ? report(responses) : `<p class="empty">No responses yet. They show up here as soon as someone sends the survey.</p>`}
    </main>`;

  root.querySelector("#refresh").addEventListener("click", load);
  root.querySelector("#csv").addEventListener("click", () => downloadCSV(responses));
  root.querySelector("#tests").addEventListener("change", (event) => {
    showTests = event.target.checked;
    load();
  });
  root.querySelector("#forget").addEventListener("click", () => {
    key = "";
    saveKey("");
    data = null;
    renderLock();
  });
}

function report(responses) {
  const n = responses.length;
  const answers = responses.map((r) => r.answers || {});
  const scaleQ = survey.questions.find((q) => q.type === "scale");
  const ratings = scaleQ ? answers.map((a) => a[scaleQ.id]).filter((v) => typeof v === "number") : [];
  const average = ratings.length ? (ratings.reduce((s, v) => s + v, 0) / ratings.length).toFixed(1) : "-";
  const install = answers.filter((a) => a.install === "Yes" || a.install === "Probably").length;
  const tryApp = answers.filter((a) => a.try_app === "Yes").length;

  const charted = survey.questions.filter((q) => ["choice", "multi", "scale"].includes(q.type));
  const written = survey.questions.filter((q) => q.type === "text" && q.id !== "name" && q.id !== "use_case_other");
  const other = answers.filter((a) => a.use_case_other);

  return `
    <section class="tiles">
      ${tile("Responses", String(n))}
      ${tile("Average usefulness", `${average}<span class="tile-unit"> / 5</span>`, `From ${ratings.length} ${ratings.length === 1 ? "rating" : "ratings"}`)}
      ${tile("Would install it", `${install}<span class="tile-unit"> of ${n}</span>`, "Answered Yes or Probably")}
      ${tile("Want the real app", `${tryApp}<span class="tile-unit"> of ${n}</span>`)}
    </section>

    <section class="block">
      <h2>Answers</h2>
      <div class="charts">
        ${charted.map((q) => chart(q, answers, n)).join("")}
        ${chartFrom("Students they tried", Object.entries(students).map(([id, name]) => [name, responses.filter((r) => (r.students || []).includes(id)).length]), n)}
      </div>
      ${other.length ? `<p class="aside">"Something else" use cases: ${other.map((a) => `${esc(a.use_case_other)} (${esc(a.name || "no name")})`).join("; ")}</p>` : ""}
    </section>

    <section class="block">
      <h2>What they picked at each card</h2>
      ${picksTable(responses)}
    </section>

    <section class="block">
      <h2>In their words</h2>
      ${written.map((q) => quotes(q, responses)).join("")}
    </section>

    <section class="block">
      <h2>Every response</h2>
      ${responses.map(single).join("")}
    </section>`;
}

function tile(label, value, hint = "") {
  return `<div class="tile"${hint ? ` title="${esc(hint)}"` : ""}><div class="tile-label">${esc(label)}</div><div class="tile-value">${value}</div></div>`;
}

function chart(q, answers, n) {
  let rows;
  if (q.type === "scale") {
    rows = [];
    for (let v = q.min; v <= q.max; v += 1) {
      const label = v === q.min ? `${v} (${q.minLabel})` : v === q.max ? `${v} (${q.maxLabel})` : String(v);
      rows.push([label, answers.filter((a) => a[q.id] === v).length]);
    }
  } else {
    rows = q.options.map((o) => [o, answers.filter((a) => (Array.isArray(a[q.id]) ? a[q.id].includes(o) : a[q.id] === o)).length]);
  }
  return chartFrom(q.text, rows, n);
}

// One horizontal bar per option, in one color, with the count written beside it.
function chartFrom(title, rows, n) {
  const max = Math.max(1, ...rows.map(([, c]) => c));
  return `
    <figure class="chart">
      <figcaption>${esc(title)}</figcaption>
      ${rows.map(([label, count]) => `
        <div class="bar-row" title="${esc(`${label}: ${count} of ${n}`)}">
          <span class="bar-label">${esc(label)}</span>
          <span class="bar-track"><span class="bar" style="width:${count ? `max(3px, ${(count / max) * 100}%)` : "0"}"></span></span>
          <span class="bar-count">${count}</span>
        </div>`).join("")}
    </figure>`;
}

function picksTable(responses) {
  const cards = new Map();
  for (const r of responses) {
    for (const p of r.picks || []) {
      const id = `${p.student}|${p.moment}`;
      if (!cards.has(id)) cards.set(id, { student: p.student, moment: p.moment, card: p.card, demo: p.demo, counts: {} });
      const entry = cards.get(id);
      entry.counts[p.picked] = (entry.counts[p.picked] || 0) + 1;
    }
  }
  if (!cards.size) return `<p class="empty">No card picks yet.</p>`;
  const order = Object.keys(students);
  const rows = [...cards.values()].sort((a, b) => order.indexOf(a.student) - order.indexOf(b.student));
  return `
    <div class="table-wrap">
      <table class="picks-table">
        <thead><tr><th>Student</th><th>Moment</th><th>Card</th><th title="Picked Set it up or Show me how">Accepted</th><th>Later</th><th>Not for me</th><th>Demo did</th></tr></thead>
        <tbody>
          ${rows.map((c) => {
            const accept = (c.counts["Set it up"] || 0) + (c.counts["Show me how"] || 0);
            return `<tr>
              <td>${esc(students[c.student] || c.student)}</td>
              <td>${esc(c.moment)}</td>
              <td>${esc(cardLabel(c.card))}</td>
              <td class="num">${accept}</td>
              <td class="num">${c.counts.Later || 0}</td>
              <td class="num">${c.counts["Not for me"] || 0}</td>
              <td>${esc(c.demo)}</td>
            </tr>`;
          }).join("")}
        </tbody>
      </table>
    </div>`;
}

function cardLabel(card) {
  const [kind, ...tool] = String(card || "").split(" ");
  return `${kind === "coach" ? "Coached" : "Suggested"} ${tool.join(" ")}`;
}

function quotes(q, responses) {
  const said = responses.filter((r) => r.answers && r.answers[q.id]);
  return `
    <div class="quotes">
      <h3>${esc(q.text)}</h3>
      ${said.length
        ? said.map((r) => `<blockquote><p>${esc(r.answers[q.id])}</p><cite>${esc(r.answers.name || "No name")}${q.id === "install_why" && r.answers.install ? `, who answered ${esc(r.answers.install)}` : ""}</cite></blockquote>`).join("")
        : `<p class="empty">Nobody answered this yet.</p>`}
    </div>`;
}

function single(r) {
  const a = r.answers || {};
  const when = new Date(r.receivedAt).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  const tried = (r.students || []).map((id) => students[id] || id).join(", ");
  return `
    <details class="response">
      <summary><strong>${esc(a.name || "No name")}</strong> <span>${esc(when)}${tried ? `, tried ${esc(tried)}` : ""}</span></summary>
      <dl>
        ${survey.questions.filter((q) => q.id !== "name").map((q) => {
          const value = Array.isArray(a[q.id]) ? a[q.id].join(", ") : a[q.id];
          return value === undefined || value === null || value === "" ? "" : `<dt>${esc(q.text)}</dt><dd>${esc(value)}</dd>`;
        }).join("")}
      </dl>
      ${(r.picks || []).length ? `<ul class="pick-list">${r.picks.map((p) => `<li>${esc(students[p.student] || p.student)}, ${esc(p.moment)}: ${esc(cardLabel(p.card))}. Picked ${esc(p.picked)}.</li>`).join("")}</ul>` : ""}
    </details>`;
}

// MARK: CSV

function downloadCSV(responses) {
  const ids = survey.questions.map((q) => q.id);
  const cell = (value) => {
    const text = Array.isArray(value) ? value.join("; ") : value ?? "";
    return /[",\n]/.test(String(text)) ? `"${String(text).replace(/"/g, '""')}"` : String(text);
  };
  const lines = [["receivedAt", "students", ...ids, "picks"].join(",")];
  for (const r of responses) {
    const a = r.answers || {};
    const picks = (r.picks || []).map((p) => `${p.student}: ${p.moment} -> ${p.picked}`).join("; ");
    lines.push([r.receivedAt, (r.students || []).join(", "), ...ids.map((id) => a[id]), picks].map(cell).join(","));
  }
  const url = URL.createObjectURL(new Blob([lines.join("\n")], { type: "text/csv" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `survey-responses${showTests ? "-tests" : ""}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function sparkle() {
  return `<svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2l1.9 6.1L20 10l-6.1 1.9L12 18l-1.9-6.1L4 10l6.1-1.9L12 2zm7 12l.9 2.6 2.6.9-2.6.9L19 21l-.9-2.6-2.6-.9 2.6-.9L19 14z"/></svg>`;
}
