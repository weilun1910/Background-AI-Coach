// The web walkthrough of the full-screen demo. scripts/build-web.sh renders the
// frames from the real app and writes walkthrough.json; this file only plays them.
// After a tester has tried enough students, it shows the survey in survey.json
// and sends the answers, with their card picks, to /api/submit.

const STORE_KEY = "coach-walkthrough-v2";
const CHOICES = ["accept", "later", "never"];

// Cards sit in the top right corner and the menu drops down below the menu
// bar, so slides that show either start zoomed in on it.
const ZOOMS = {
  card: { origin: "97% 3%", scale: 1.65 },
  menu: { origin: "86% 0%", scale: 1.3 },
};

const app = document.getElementById("app");
let people = [];
let survey = null;
let screen = "home";
let person = null;
let index = 0;
let zoom = null; // null, or { origin, scale }
let lastOrigin = ZOOMS.card.origin;
let saved = load(); // { picks: { personId: { slideIndex: choice } }, finished: [ids], submitted }

// MARK: Data

Promise.all([getJSON("walkthrough.json"), getJSON("survey.json")])
  .then(([walkthrough, surveyData]) => {
    people = walkthrough.personas;
    survey = surveyData;
    const fromLink = people.find((p) => "#" + p.id === location.hash);
    fromLink ? start(fromLink) : render();
  })
  .catch(() => {
    app.innerHTML = `<p class="loading">The walkthrough didn't load. Try refreshing the page.</p>`;
  });

function getJSON(path) {
  return fetch(path).then((response) => {
    if (!response.ok) throw new Error(response.status);
    return response.json();
  });
}

// A link like .../#theo opens that student's day directly.
window.addEventListener("hashchange", () => {
  const linked = people.find((p) => "#" + p.id === location.hash);
  linked ? start(linked) : goHome();
});

function load() {
  const empty = { picks: {}, finished: [], submitted: false };
  try {
    return { ...empty, ...JSON.parse(localStorage.getItem(STORE_KEY)) };
  } catch {
    return empty;
  }
}

function save() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(saved));
  } catch {
    // Private windows can refuse storage. Everything still works for this visit.
  }
}

function label(choice, card) {
  if (choice === "accept") return card.kind === "coach" ? "Show me how" : "Set it up";
  return choice === "later" ? "Later" : "Not for me";
}

function demoDid(slide, name) {
  if (slide.scripted === "never") return `${name} said Not for me`;
  return slide.card.kind === "coach" ? `${name} clicked Show me how` : `${name} set it up`;
}

function pickFor(p, i) {
  return (saved.picks[p.id] || {})[i];
}

function surveyOpen() {
  return !saved.submitted && saved.finished.length >= survey.unlockAfter;
}

function remaining() {
  return Math.max(0, survey.unlockAfter - saved.finished.length);
}

function count(n) {
  return ["no", "one", "two", "three", "four", "five"][n] ?? String(n);
}

function plural(n, word) {
  return `${count(n)} ${word}${n === 1 ? "" : "s"}`;
}

function cap(text) {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

// MARK: Moving around

function show(next) {
  screen = next;
  render();
  window.scrollTo(0, 0);
}

function start(p) {
  person = p;
  index = 0;
  screen = "walk";
  setZoom();
  history.replaceState(null, "", "#" + p.id);
  render();
}

function goHome() {
  person = null;
  history.replaceState(null, "", location.pathname + location.search);
  show("home");
}

function next() {
  const slide = person.slides[index];
  if (slide.type === "choice" && !pickFor(person, index)) return;
  if (index === person.slides.length - 1) {
    if (!saved.finished.includes(person.id)) saved.finished.push(person.id);
    save();
    return show("summary");
  }
  index += 1;
  setZoom();
  render();
}

function back() {
  if (index === 0) return goHome();
  index -= 1;
  setZoom();
  render();
}

function choose(choice) {
  saved.picks[person.id] = { ...(saved.picks[person.id] || {}), [index]: choice };
  save();
  next();
}

function setZoom() {
  const preset = person && person.slides[index].zoom;
  zoom = preset ? ZOOMS[preset] : null;
}

function toggleZoom(event) {
  if (zoom) {
    zoom = null;
  } else {
    const box = event.currentTarget.getBoundingClientRect();
    const x = ((event.clientX - box.left) / box.width) * 100;
    const y = ((event.clientY - box.top) / box.height) * 100;
    zoom = { origin: `${x.toFixed(1)}% ${y.toFixed(1)}%`, scale: ZOOMS.card.scale };
  }
  applyZoom();
}

// Zooming out keeps the last origin, so the view eases back from where it was.
function applyZoom() {
  const screenEl = app.querySelector(".screen");
  if (!screenEl) return;
  const img = screenEl.querySelector("img");
  if (zoom) lastOrigin = zoom.origin;
  img.style.transformOrigin = lastOrigin;
  img.style.setProperty("--z", zoom ? zoom.scale : 1);
  screenEl.classList.toggle("zoomed", !!zoom);
}

// MARK: Rendering

function esc(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function render() {
  if (screen === "home") renderHome();
  else if (screen === "walk") renderWalk();
  else if (screen === "summary") renderSummary();
  else if (screen === "survey") renderSurvey();
  else renderThanks();
}

function renderHome() {
  document.title = "Background AI Coach";
  const done = saved.finished.length;
  let status;
  if (saved.submitted) {
    status = `<p class="status">Thanks, your answers are in. You're welcome to keep exploring.</p>`;
  } else if (surveyOpen()) {
    status = `
      <div class="status status-ready">
        <span>You've tried ${plural(done, "student")}. Ready for a few quick questions?</span>
        <button class="btn btn-primary" id="to-survey">Answer the questions</button>
      </div>`;
  } else if (done > 0) {
    status = `<p class="status">You've tried ${plural(done, "student")}. ${cap(count(remaining()))} more and then there's a short survey.</p>`;
  } else {
    status = "";
  }

  app.innerHTML = `
    <main class="home">
      <div class="eyebrow">${sparkle()} Background AI Coach</div>
      <h1>Try a day with Background AI Coach</h1>
      <div class="intro">
        <p>Background AI Coach is a Mac app that lives in your menu bar and notices the moments where an AI tool would actually help, like a coffee chat in 15 minutes or a midterm tomorrow. If you don't have a good tool for that moment, it suggests one and sets it up. If you already have one you never open, it shows you how to use it. If you're covered, it stays quiet.</p>
        <p>Here you'll step through made-up students' days on their Mac. What the app does at each moment was decided by the real app. When a card shows up, pick what you'd actually do if you were them. Try ${plural(survey.unlockAfter, "student")}, starting with the one most like you, and then there's a short survey.</p>
      </div>
      ${status}
      <h2>${done ? "Pick another student" : "Pick the student most like you"}</h2>
      <p class="hint">Each day takes about three minutes. It's easier to read on a laptop than a phone.</p>
      <div class="people">
        ${people.map((p) => `
          <button class="person" data-id="${esc(p.id)}">
            <span class="name">${esc(p.name)}</span>
            <span class="tagline">${esc(p.tagline)}</span>
            <span class="about">${esc(p.about)}</span>
            ${saved.finished.includes(p.id) ? `<span class="done">Done</span>` : ""}
          </button>`).join("")}
      </div>
      <p class="footnote">Made by Felix Lee for ENAS 3110 at Yale. The students are made up, and each mixes patterns from several of our interviews. Nothing you click here leaves your browser until you send the survey.</p>
    </main>`;
  app.querySelectorAll(".person").forEach((el) =>
    el.addEventListener("click", () => start(people.find((p) => p.id === el.dataset.id))),
  );
  app.querySelector("#to-survey")?.addEventListener("click", () => show("survey"));
}

// The screen stays on the page between slides, so the frame swaps in place and
// zooming in or out animates instead of jumping.
function renderWalk() {
  const slide = person.slides[index];
  const total = person.slides.length;
  document.title = `${person.name}'s day | Background AI Coach`;

  let walk = app.querySelector(".walk");
  if (!walk || walk.dataset.person !== person.id) {
    app.innerHTML = `
      <div class="walk" data-person="${esc(person.id)}">
        <header class="topbar">
          <button class="btn btn-text" id="home" title="Back to all students">← All students</button>
          <div class="who"><strong>${esc(person.name)}</strong> <span>${esc(person.tagline)}</span></div>
          <div class="count"></div>
        </header>
        <div class="progress"><div></div></div>
        <div class="walk-body">
          <div class="stage">
            <div class="screen" title="Click to zoom">
              <img src="frames/${esc(slide.frame)}" alt="${esc(person.name)}'s Mac screen">
            </div>
          </div>
          <aside class="panel"></aside>
        </div>
      </div>`;
    walk = app.querySelector(".walk");
    walk.querySelector("#home").addEventListener("click", goHome);
    walk.querySelector(".screen").addEventListener("click", toggleZoom);
  }

  walk.querySelector(".count").textContent = `${index + 1} / ${total}`;
  walk.querySelector(".progress div").style.width = `${((index + 1) / total) * 100}%`;

  const panel = walk.querySelector(".panel");
  panel.innerHTML = slide.type === "choice" ? choicePanel(slide) : viewPanel(slide);
  panel.querySelectorAll("[data-choice]").forEach((el) => el.addEventListener("click", () => choose(el.dataset.choice)));
  panel.querySelector("#back")?.addEventListener("click", back);
  panel.querySelector("#next")?.addEventListener("click", next);

  const img = walk.querySelector(".screen img");
  const src = "frames/" + slide.frame;
  if (img.getAttribute("src") === src) {
    applyZoom();
  } else {
    const shown = index;
    const incoming = new Image();
    incoming.src = src;
    incoming.decode().catch(() => {}).then(() => {
      if (shown !== index || screen !== "walk") return;
      img.src = src;
      applyZoom();
    });
  }
  preload();
}

function viewPanel(slide) {
  const before = person.slides[index - 1];
  const picked = before && before.type === "choice" ? pickFor(person, index - 1) : null;
  const note = picked && picked !== before.scripted
    ? `<p class="note">You picked ${esc(label(picked, before.card))}. In the demo ${esc(demoDid(before, person.name))}, so here's what that looks like.</p>`
    : "";
  const last = index === person.slides.length - 1;
  return `
    <span class="time">${esc(slide.time)}</span>
    ${note}
    <p class="text">${esc(slide.text)}</p>
    <div class="nav">
      <button class="btn btn-secondary" id="back">Back</button>
      <button class="btn btn-primary" id="next">${last ? "Finish" : "Next"}</button>
    </div>
    <p class="keys">Arrow keys move through the day. Click the screen to zoom in or out.</p>`;
}

function choicePanel(slide) {
  const picked = pickFor(person, index);
  const button = (choice, style) => `
    <button class="btn ${style}${picked === choice ? " picked" : ""}" data-choice="${choice}">${esc(label(choice, slide.card))}</button>`;
  return `
    <span class="time">${esc(slide.time)}</span>
    ${slide.lead ? `<p class="lead">${esc(slide.lead)}</p>` : ""}
    <p class="ask">A card shows up. If you were ${esc(person.name)}, what would you do?</p>
    <div class="choices">
      ${button("accept", "btn-primary")}
      ${button("later", "btn-secondary")}
      ${button("never", "btn-text")}
    </div>
    <div class="nav">
      <button class="btn btn-secondary" id="back">Back</button>
      ${picked ? `<button class="btn btn-primary" id="next">Next</button>` : ""}
    </div>
    <p class="keys">Press 1, 2 or 3 to pick. Click the screen to zoom out.</p>`;
}

function renderSummary() {
  const cards = person.slides.map((s, i) => ({ s, i })).filter(({ s }) => s.type === "choice");
  document.title = `${person.name}'s day | Background AI Coach`;

  let actions;
  if (surveyOpen()) {
    actions = `
      <p class="sub">That's ${plural(saved.finished.length, "student")}. Time for a few quick questions.</p>
      <div class="actions">
        <button class="btn btn-primary" id="to-survey">Answer the questions</button>
        <button class="btn btn-secondary" id="again">Try another student first</button>
      </div>`;
  } else if (saved.submitted) {
    actions = `
      <div class="actions">
        <button class="btn btn-primary" id="again">Try another student</button>
      </div>`;
  } else {
    actions = `
      <p class="sub">${cap(plural(remaining(), "more student"))} and then there's a short survey.</p>
      <div class="actions">
        <button class="btn btn-primary" id="again">Pick the next student</button>
      </div>`;
  }

  app.innerHTML = `
    <main class="summary">
      <div class="eyebrow">${sparkle()} Background AI Coach</div>
      <h1>That's ${esc(person.name)}'s day</h1>
      <p class="sub">${cards.length === 1 ? "One card showed up." : `${cards.length} cards showed up.`} Here's what you picked.</p>
      <ul class="picks">
        ${cards.map(({ s, i }) => {
          const picked = pickFor(person, i);
          return `
            <li>
              <div class="moment">${esc(s.title)}</div>
              <div class="detail">${esc(s.card.kind === "coach" ? "Coached" : "Suggested")} ${esc(s.card.tool)}. You picked ${esc(picked ? label(picked, s.card) : "nothing")}.</div>
            </li>`;
        }).join("")}
      </ul>
      ${actions}
    </main>`;

  app.querySelector("#again").addEventListener("click", goHome);
  app.querySelector("#to-survey")?.addEventListener("click", () => show("survey"));
}

// MARK: Survey

function renderSurvey() {
  document.title = "A few questions | Background AI Coach";
  app.innerHTML = `
    <main class="survey">
      <div class="eyebrow">${sparkle()} Background AI Coach</div>
      <h1>A few quick questions</h1>
      <p class="sub">${esc(survey.intro)}</p>
      <form id="survey" novalidate>
        ${survey.questions.map(question).join("")}
        <div class="trap" aria-hidden="true">
          <label>Leave this empty <input name="website" tabindex="-1" autocomplete="off"></label>
        </div>
        <p class="form-error" id="form-error" role="alert"></p>
        <div class="actions">
          <button class="btn btn-primary" type="submit" id="send">Send my answers</button>
          <button class="btn btn-text" type="button" id="back-home">Back to the students</button>
        </div>
      </form>
    </main>`;

  const form = app.querySelector("#survey");
  form.addEventListener("submit", send);
  form.addEventListener("click", (event) => {
    const option = event.target.closest("[data-scale]");
    if (!option) return;
    const group = option.closest(".scale");
    group.querySelectorAll("[data-scale]").forEach((el) => el.setAttribute("aria-pressed", el === option ? "true" : "false"));
    group.dataset.value = option.dataset.scale;
    option.closest(".q").classList.remove("missing");
  });
  form.addEventListener("change", (event) => event.target.closest(".q")?.classList.remove("missing"));
  app.querySelector("#back-home").addEventListener("click", goHome);
}

function question(q) {
  const req = q.required ? `<span class="req">Required</span>` : "";
  const head = `<legend class="q-text">${esc(q.text)} ${req}</legend>`;
  let body = "";
  if (q.type === "choice" || q.type === "multi") {
    const kind = q.type === "choice" ? "radio" : "checkbox";
    body = `<div class="options">${q.options.map((o) => `
      <label class="option"><input type="${kind}" name="${esc(q.id)}" value="${esc(o)}"><span>${esc(o)}</span></label>`).join("")}</div>`;
  } else if (q.type === "scale") {
    const steps = [];
    for (let n = q.min; n <= q.max; n += 1) {
      steps.push(`<button type="button" class="scale-step" data-scale="${n}" aria-pressed="false">${n}</button>`);
    }
    body = `
      <div class="scale" data-id="${esc(q.id)}">${steps.join("")}</div>
      <div class="scale-labels"><span>${esc(q.minLabel)}</span><span>${esc(q.maxLabel)}</span></div>`;
  } else if (q.type === "text" && q.long) {
    body = `<textarea name="${esc(q.id)}" rows="3" maxlength="2000" placeholder="${esc(q.placeholder || "")}"></textarea>`;
  } else {
    const type = q.type === "email" ? "email" : "text";
    body = `<input type="${type}" name="${esc(q.id)}" maxlength="200" placeholder="${esc(q.placeholder || "")}"${type === "email" ? ' autocomplete="email"' : ""}>`;
  }
  return `<fieldset class="q" data-q="${esc(q.id)}">${head}${body}</fieldset>`;
}

function readAnswers(form) {
  const answers = {};
  for (const q of survey.questions) {
    if (q.type === "scale") {
      const value = form.querySelector(`.scale[data-id="${q.id}"]`).dataset.value;
      answers[q.id] = value ? Number(value) : null;
    } else if (q.type === "multi") {
      answers[q.id] = [...form.querySelectorAll(`input[name="${q.id}"]:checked`)].map((el) => el.value);
    } else if (q.type === "choice") {
      answers[q.id] = form.querySelector(`input[name="${q.id}"]:checked`)?.value ?? null;
    } else {
      answers[q.id] = form.querySelector(`[name="${q.id}"]`).value.trim();
    }
  }
  return answers;
}

function allPicks() {
  return people.flatMap((p) =>
    p.slides
      .map((s, i) => ({ s, i }))
      .filter(({ s, i }) => s.type === "choice" && pickFor(p, i))
      .map(({ s, i }) => ({
        student: p.id,
        moment: s.title,
        card: `${s.card.kind} ${s.card.tool}`,
        picked: label(pickFor(p, i), s.card),
        demo: s.scripted === "never" ? "Not for me" : label("accept", s.card),
      })),
  );
}

async function send(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const answers = readAnswers(form);
  const errorEl = form.querySelector("#form-error");

  const missing = survey.questions.filter((q) => q.required && (answers[q.id] === null || answers[q.id] === ""));
  form.querySelectorAll(".q").forEach((el) => el.classList.toggle("missing", missing.some((q) => q.id === el.dataset.q)));
  const emailField = form.querySelector('input[type="email"]');
  if (missing.length) {
    errorEl.textContent = missing.length === 1 ? "One question still needs an answer." : `${missing.length} questions still need an answer.`;
    form.querySelector(".q.missing").scrollIntoView({ behavior: "smooth", block: "center" });
    return;
  }
  if (emailField && emailField.value && !emailField.checkValidity()) {
    errorEl.textContent = "That email address doesn't look right.";
    emailField.focus();
    return;
  }

  const button = form.querySelector("#send");
  button.disabled = true;
  button.textContent = "Sending...";
  errorEl.textContent = "";
  // Opening the page with ?test=1 files answers under tests/, away from real ones.
  const endpoint = new URLSearchParams(location.search).has("test") ? "/api/submit?test=1" : "/api/submit";
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        students: saved.finished,
        picks: allPicks(),
        answers,
        website: form.querySelector('input[name="website"]').value,
      }),
    });
    if (!response.ok) throw new Error(response.status);
    saved.submitted = true;
    save();
    show("thanks");
  } catch {
    button.disabled = false;
    button.textContent = "Send my answers";
    errorEl.textContent = "That didn't send. Check your connection and try again.";
  }
}

function renderThanks() {
  document.title = "Thanks | Background AI Coach";
  const left = people.length - saved.finished.length;
  app.innerHTML = `
    <main class="summary">
      <div class="eyebrow">${sparkle()} Background AI Coach</div>
      <h1>Thanks, that really helps</h1>
      <p class="sub">Your answers and card picks are in.${left ? ` If you're curious, there ${left === 1 ? "is one student" : `are ${plural(left, "student")}`} you haven't tried.` : ""}</p>
      <div class="actions">
        <button class="btn btn-secondary" id="again">Back to the students</button>
      </div>
    </main>`;
  app.querySelector("#again").addEventListener("click", goHome);
}

function preload() {
  for (const ahead of person.slides.slice(index + 1, index + 3)) {
    new Image().src = "frames/" + ahead.frame;
  }
}

function sparkle() {
  return `<svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2l1.9 6.1L20 10l-6.1 1.9L12 18l-1.9-6.1L4 10l6.1-1.9L12 2zm7 12l.9 2.6 2.6.9-2.6.9L19 21l-.9-2.6-2.6-.9 2.6-.9L19 14z"/></svg>`;
}

// MARK: Keyboard

document.addEventListener("keydown", (event) => {
  if (screen !== "walk" || event.metaKey || event.ctrlKey || event.altKey) return;
  const slide = person.slides[index];
  if (event.key === "ArrowRight" || event.key === " " || event.key === "Enter") {
    if (event.target.closest && event.target.closest("button") && event.key !== "ArrowRight") return;
    event.preventDefault();
    next();
  } else if (event.key === "ArrowLeft") {
    event.preventDefault();
    back();
  } else if (slide.type === "choice" && ["1", "2", "3"].includes(event.key)) {
    choose(CHOICES[Number(event.key) - 1]);
  } else if (event.key === "Escape" && zoom) {
    zoom = null;
    applyZoom();
  }
});
