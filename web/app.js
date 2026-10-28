// The web walkthrough of the full-screen demo. scripts/build-web.sh renders the
// frames from the real app and writes walkthrough.json; this file only plays them.

// Paste the Google Form here once it exists. answersEntry is the id of the
// paragraph question that should receive the tester's picks, like
// "entry.1234567890". The form's "Get pre-filled link" shows it.
const FEEDBACK_FORM = {
  url: "",
  answersEntry: "",
};

const STORE_KEY = "coach-walkthrough-picks";
const CHOICES = ["accept", "later", "never"];

// Cards sit in the top right corner and the menu drops down below the menu
// bar, so slides that show either start zoomed in on it.
const ZOOMS = {
  card: { origin: "97% 3%", scale: 1.65 },
  menu: { origin: "86% 0%", scale: 1.3 },
};

const app = document.getElementById("app");
let people = [];
let screen = "home";
let person = null;
let index = 0;
let zoom = null; // null, or { origin, scale }
let lastOrigin = ZOOMS.card.origin;
let copied = false;
let picks = loadPicks(); // { personId: { slideIndex: "accept" | "later" | "never" } }

// MARK: Data

fetch("walkthrough.json")
  .then((response) => {
    if (!response.ok) throw new Error(response.status);
    return response.json();
  })
  .then((data) => {
    people = data.personas;
    const fromLink = people.find((p) => "#" + p.id === location.hash);
    fromLink ? start(fromLink) : render();
  })
  .catch(() => {
    app.innerHTML = `<p class="loading">The walkthrough didn't load. Try refreshing the page.</p>`;
  });

// A link like .../#theo opens that student's day directly.
window.addEventListener("hashchange", () => {
  const linked = people.find((p) => "#" + p.id === location.hash);
  linked ? start(linked) : goHome();
});

function loadPicks() {
  try {
    return JSON.parse(localStorage.getItem(STORE_KEY)) || {};
  } catch {
    return {};
  }
}

function savePicks() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(picks));
  } catch {
    // Private windows can refuse storage. Picks still work for this visit.
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
  return (picks[p.id] || {})[i];
}

// MARK: Moving around

function start(p) {
  person = p;
  index = 0;
  screen = "walk";
  setZoom();
  history.replaceState(null, "", "#" + p.id);
  render();
}

function goHome() {
  screen = "home";
  person = null;
  history.replaceState(null, "", location.pathname + location.search);
  render();
  window.scrollTo(0, 0);
}

function next() {
  const slide = person.slides[index];
  if (slide.type === "choice" && !pickFor(person, index)) return;
  if (index === person.slides.length - 1) {
    screen = "summary";
    copied = false;
    render();
    window.scrollTo(0, 0);
    return;
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
  picks[person.id] = { ...(picks[person.id] || {}), [index]: choice };
  savePicks();
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
  else renderSummary();
}

function renderHome() {
  document.title = "Background AI Coach";
  app.innerHTML = `
    <main class="home">
      <div class="eyebrow">${sparkle()} Background AI Coach</div>
      <h1>Try a day with Background AI Coach</h1>
      <div class="intro">
        <p>Background AI Coach is a Mac app that lives in your menu bar and notices the moments where an AI tool would actually help, like a coffee chat in 15 minutes or a midterm tomorrow. If you don't have a good tool for that moment, it suggests one and sets it up. If you already have one you never open, it shows you how to use it. If you're covered, it stays quiet.</p>
        <p>Here you'll step through one made-up student's day on their Mac. What the app does at each moment was decided by the real app. When a card shows up, pick what you'd actually do if you were them. There's a short form at the end.</p>
      </div>
      <h2>Pick the student most like you</h2>
      <p class="hint">Each day takes about three minutes. It's easier to read on a laptop than a phone.</p>
      <div class="people">
        ${people.map((p) => `
          <button class="person" data-id="${esc(p.id)}">
            <span class="name">${esc(p.name)}</span>
            <span class="tagline">${esc(p.tagline)}</span>
            <span class="about">${esc(p.about)}</span>
            ${picks[p.id] ? `<span class="done">You've done this one</span>` : ""}
          </button>`).join("")}
      </div>
      <p class="footnote">Made by Felix Lee for ENAS 3110 at Yale. The students are made up, and each mixes patterns from several of our interviews. Nothing you click here leaves your browser unless you send the form.</p>
    </main>`;
  app.querySelectorAll(".person").forEach((el) =>
    el.addEventListener("click", () => start(people.find((p) => p.id === el.dataset.id))),
  );
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
  const formLink = FEEDBACK_FORM.url && FEEDBACK_FORM.answersEntry
    ? `${FEEDBACK_FORM.url}${FEEDBACK_FORM.url.includes("?") ? "&" : "?"}usp=pp_url&${FEEDBACK_FORM.answersEntry}=${encodeURIComponent(answersText())}`
    : FEEDBACK_FORM.url;
  document.title = `${person.name}'s day | Background AI Coach`;

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
      <div class="actions">
        ${formLink ? `<a class="btn btn-primary" href="${esc(formLink)}" target="_blank" rel="noopener">Tell us what you think</a>` : ""}
        <button class="btn btn-secondary" id="again">Try another student</button>
        <button class="btn btn-text" id="copy">Copy my answers</button>
        ${copied ? `<span class="copied">Copied</span>` : ""}
      </div>
    </main>`;

  app.querySelector("#again").addEventListener("click", goHome);
  app.querySelector("#copy").addEventListener("click", copyAnswers);
}

// Every pick so far, one line per card, for the form.
function answersText() {
  return people.flatMap((p) =>
    p.slides
      .map((s, i) => ({ s, i }))
      .filter(({ s, i }) => s.type === "choice" && pickFor(p, i))
      .map(({ s, i }) => `${p.name} | ${s.title} | ${s.card.kind === "coach" ? "coached" : "suggested"} ${s.card.tool} | picked ${label(pickFor(p, i), s.card)}`),
  ).join("\n");
}

async function copyAnswers() {
  try {
    await navigator.clipboard.writeText(answersText());
    copied = true;
  } catch {
    window.prompt("Copy your answers:", answersText());
  }
  render();
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
