// froppii's script from github.com/froppii/playground at 01d6c09. playground
// changes: icon paths come from data attributes (Propshaft digests asset
// names), ship.exe holds the dashboard iframe,
// ?open=goal opens it, drags
// mark body.dragging so the iframe cannot swallow the mouse mid-drag, a
// press or focus anywhere in a window brings it to the front, the X in
// each header hides its window, windows stay inside the browser window, a
// drag on any side or corner of a window's frame resizes it, the rock
// walks in front of the windows and behind the taskbar, an icon never
// drags out of the desktop as a picture, Hack Club's four required links
// are icons that open their sites in a new tab, a drag by mouse, pen, or
// touch keeps a window's header and the whole rock in reach,
// armand.sponsor opens the sponsor's Slack profile, and the icons sit on a
// grid, where a click opens and selects one, a drag moves the selected
// icons, a drag on the wallpaper selects the icons it touches, an icon
// that leaves the site wears a shortcut arrow, each of a participant's pets
// is an icon that opens its page in a window of its own, a trash can
// takes icons off the desktop, and deletes a pet dragged into it, and a
// right click on an icon opens its own menu, which opens it, renames a pet,
// or moves it to the trash. The login is login.exe, a window with no icon,
// which a visitor's desktop opens beside welcome.txt, and ship.exe opens
// for a visitor.
const appsIcons = {
    file: document.getElementById("apps").dataset.fileIcon,
    exe: document.getElementById("apps").dataset.exeIcon,
    hackclub: document.getElementById("apps").dataset.hackclubIcon,
    terms: document.getElementById("apps").dataset.termsIcon,
    bounty: document.getElementById("apps").dataset.bountyIcon,
    security: document.getElementById("apps").dataset.securityIcon,
    sponsor: document.getElementById("apps").dataset.sponsorIcon,
    shortcut: document.getElementById("apps").dataset.shortcutIcon,
    trash: document.getElementById("apps").dataset.trashIcon,
    trashFull: document.getElementById("apps").dataset.trashFullIcon,
    pet: document.getElementById("apps").dataset.petIcon,
    bananaPeel: document.getElementById("apps").dataset.bananaPeelIcon
};

const apps = [
    {
        title: "welcome.txt",
        icon: appsIcons.file,
        // playground: false keeps the window at the size it opens at.
        resizable: true,
        content: `
            <p>testing</p>
        `
    },
    // playground: the guide to making a pet in Godot, its page in a frame.
    {
        title: "guide.txt",
        icon: appsIcons.file,
        resizable: true,
        content: `
            <iframe class="guide-frame" src="/guide" title="guide.txt"></iframe>
        `
    },
    // playground: its key is the name it had before, goal.exe, so an icon
    // spot, a window spot, an open window, or a trash saved then still finds it.
    {
        key: "goal.exe",
        title: "ship.exe",
        icon: appsIcons.exe,
        resizable: true,
        // playground: the real dashboard, in place of the placeholder form.
        content: `
            <iframe class="ship-frame" src="/dashboard" title="ship.exe"></iframe>
        `
    },
    // playground: the submission requirements, their page in a frame.
    {
        title: "requirements.txt",
        icon: appsIcons.file,
        resizable: true,
        content: `
            <iframe class="requirements-frame" src="/requirements" title="requirements.txt"></iframe>
        `
    },
    // playground: the login's first step, its page in a frame. It has no
    // icon: a visitor's desktop opens it with the page (see restoreWindows),
    // and ship.exe opens it for a visitor (see openWindow). It fits its page
    // and does not resize.
    {
        title: "login.exe",
        resizable: false,
        content: `
            <iframe class="login-frame" src="/login" title="login.exe"></iframe>
        `
    },
    // playground: Hack Club's required links. Each opens its site, not a window.
    { title: "Hack Club", icon: appsIcons.hackclub, url: "https://hackclub.com" },
    { title: "Terms & Privacy", icon: appsIcons.terms, url: "https://hackclub.com/privacy-and-terms" },
    // Its key is the label it first had, so a layout or trash saved then still finds it.
    { key: "Bounty", title: "Fulfillment", icon: appsIcons.bounty, url: "https://forms.hackclub.com/bounty" },
    { title: "Security", icon: appsIcons.security, url: "https://security.hackclub.com" },
    // playground: the sponsor's credit on a desktop. Its icon is his face,
    // and it opens his Slack profile, as the links above open their sites.
    { title: "armand.sponsor", icon: appsIcons.sponsor, url: document.getElementById("apps").dataset.sponsorUrl },
    // playground: the trash can. A click or a right click opens its menu.
    { title: "trash", icon: appsIcons.trash, trash: true },
    // playground: a banana peel, in every fresh trash. Put back, it is an icon
    // that opens nothing. It comes after the pets, so putting it back moves
    // no other icon.
    { title: "banana peel", icon: appsIcons.bananaPeel, order: Infinity, open: () => {} }
];

const appsContainer = document.getElementById("apps");

// playground: where each icon sits on the grid, by column and row, and the
// cells saved in this browser, by icon.
const iconCells = new Map();
const iconsStore = "playground-desktop-icons";
let savedIcons = loadIcons();

// playground: one desktop icon, kept in order on the page: the built-in
// icons first, as listed above, then the pets, oldest first. A link's icon
// is a real link, so Tab reaches it and Enter follows it. Every other icon
// is a button that Tab reaches too. Its label names it, so the picture
// needs no alt text. The label is text, so a pet's name shows as typed.
function addIcon({ key, title, picture, url, open, order }) {
    const icon = document.createElement(url ? "a" : "div");
    icon.className = "app";
    icon.dataset.key = key;
    icon.dataset.order = order;
    const image = Object.assign(document.createElement("img"), { className: "appicon", src: picture, alt: "", draggable: false });
    const label = document.createElement("p");
    setLabel(label, title);
    icon.append(image, label);
    if (url) {
        Object.assign(icon, { href: url, target: "_blank", rel: "noopener", draggable: false });
        // An icon that leaves the site wears a shortcut arrow on its
        // picture's bottom left corner, as on a classic desktop.
        if (new URL(url, location.href).origin !== location.origin) {
            icon.append(Object.assign(document.createElement("img"), { className: "shortcut", src: appsIcons.shortcut, alt: "", draggable: false }));
        }
        setUpIcon(icon);
    } else {
        icon.tabIndex = 0;
        icon.setAttribute("role", "button");
        setUpIcon(icon, open);
    }
    putBackIcon(icon);
    return icon;
}

// A label is text, so a pet's name shows as typed. A name with a dot, such
// as armand.sponsor, may break after the dot.
function setLabel(label, text) {
    label.replaceChildren(...text.split(/(?<=\.)(?=.)/).flatMap((part, i) => i ? [document.createElement("wbr"), part] : [part]));
}

// A label's longest word fits its line whole: a word too long for it takes
// a smaller font, down to 10px, so no label cuts a word short. The words
// split at spaces, and where a label has two lines, after a dot too, as the
// label breaks. A word too long even at 10px, some 14 letters, breaks onto
// the second line where there is one, and ends in an ellipsis where not.
const labelMeasure = document.createElement("canvas").getContext("2d");

function fitLabelWords(label) {
    label.style.fontSize = "";
    const style = getComputedStyle(label);
    const icon = getComputedStyle(label.parentElement);
    const line = parseFloat(icon.maxWidth) - parseFloat(icon.paddingLeft) * 2 - parseFloat(style.paddingLeft) * 2;
    labelMeasure.font = style.font;
    const words = label.textContent.split(parseInt(style.webkitLineClamp) > 1 ? /\s+|(?<=\.)/ : /\s+/);
    // A little more than the word, for the outline drawn round each letter
    // and the canvas measuring a hair short of the page.
    const widest = Math.max(...words.map(word => labelMeasure.measureText(word).width)) * 1.02 + 2;
    if (widest > line) label.style.fontSize = Math.max(10, Math.floor(parseFloat(style.fontSize) * line / widest * 10) / 10) + "px";
}

// An icon goes back on the page in its place in the order.
function putBackIcon(icon) {
    const next = [...appsContainer.children].find(other => Number(other.dataset.order) > Number(icon.dataset.order));
    appsContainer.insertBefore(icon, next ?? null);
}

apps.forEach((app, order) => {
    if (!app.icon) return;
    const icon = addIcon({ key: app.key ?? app.title, title: app.title, picture: app.icon, url: app.url, order: app.order ?? order,
        open: app.open ?? (app.trash ? () => openTrashMenu() : () => openWindow(app)) });
    // playground: on a phone the text row at the top stands in for the icons
    // that link off the site, the sponsor's included (landing.css).
    if (app.url) icon.classList.add("in-row");
});

// playground: the icons showing now, which the grid lays out and a drag on
// the wallpaper can select. On a phone the row's icons do not show.
function shownIcons() {
    return [...appsContainer.querySelectorAll(".app")].filter(icon => icon.offsetParent);
}

// playground: the icons exist now, so landing.css may hide the text copy of
// the required links. Without this script the text copy stays.
document.documentElement.classList.add("icons-ready");

const guideLink = document.getElementById("guide-link");
if (guideLink) {
    guideLink.addEventListener("click", event => {
        event.preventDefault();
        openWindowByTitle("guide.txt");
    });
}

const pet = document.getElementById("desktop-pet");
const bar = document.getElementById("bar");

// playground: a sound, played only on a press. Each file keeps one player, so
// a second press starts it again, and two files can play at once. A browser
// that cannot play it stays quiet. The files and their CC0 sources are named
// where the page links them.
const sounds = new Map();
function playSound(src) {
    if (!src) return;
    try {
        if (!sounds.has(src)) sounds.set(src, Object.assign(new Audio(src), { volume: 0.5 }));
        const sound = sounds.get(src);
        sound.currentTime = 0;
        sound.play()?.catch(() => {});
    } catch {
        // No audio in this browser.
    }
}
// playground: each word on the taskbar plays its own gulp.
bar.querySelectorAll("button[data-sound]").forEach(button => button.addEventListener("click", () => playSound(button.dataset.sound)));
const petCanvas = document.createElement("canvas");
let petDragging = false;
let petDragOffsetX = 0;
let petDragOffsetY = 0;
let petFallAnimation = null;
let petStopTimeout = null;
let petResumeTimeout = null;
let petPointer = null;
let petWalkTime = 0;
let petLandLeft = 0;

petCanvas.id = "desktop-pet-static";
petCanvas.style.display = "none";
document.body.appendChild(petCanvas);

if (pet) {
    // playground: pointer events, so a finger or a pen picks the rock up as
    // a mouse does. A stopped rock shows its still frame in place of the
    // GIF, so the frame takes a press too.
    [pet, petCanvas].forEach(el => el.addEventListener("pointerdown", petDragStart));
    pet.addEventListener("dragstart", e => e.preventDefault());
    pet.classList.add("walking");
    schedulePetStop();
}

function schedulePetStop() {
    if (!pet || petDragging || pet.classList.contains("in-trash")) return;
    clearTimeout(petStopTimeout);
    clearTimeout(petResumeTimeout);
    petStopTimeout = setTimeout(() => {
        stopPet();
    }, 2500 + Math.random() * 4000);
}

function stopPet() {
    if (!pet || petDragging) return;
    // playground: the still frame goes where the rock shows now, part way
    // along its walk, and the walk goes on from there when it resumes.
    const rect = pet.getBoundingClientRect();
    petWalkTime = pet.getAnimations()[0]?.currentTime ?? 0;
    pet.classList.remove("walking");
    pet.classList.add("stopped");
    pet.style.animation = "none";
    pet.style.animationPlayState = "paused";
    showStaticPetFrame(rect);

    const stopDuration = 1500 + Math.random() * 2200;
    petResumeTimeout = setTimeout(() => {
        if (!petDragging) {
            resumePetWalking();
        }
    }, stopDuration);
}

function resumePetWalking(landed) {
    if (!pet) return;
    pet.classList.remove("stopped");
    hideStaticPetFrame();
    pet.classList.add("walking");
    pet.style.animation = "";
    pet.style.animationPlayState = "running";
    // playground: a rock that just landed starts halfway along froppii's
    // walk, where it passes its own spot, so it walks off from where it fell.
    const walk = pet.getAnimations()[0];
    if (walk) walk.currentTime = landed ? walk.effect.getComputedTiming().duration / 2 : petWalkTime;
    schedulePetStop();
}

function showStaticPetFrame(rect) {
    if (!pet) return;
    petCanvas.width = rect.width;
    petCanvas.height = rect.height;
    const ctx = petCanvas.getContext("2d");
    ctx.clearRect(0, 0, rect.width, rect.height);
    ctx.drawImage(pet, 0, 0, rect.width, rect.height);
    petCanvas.style.left = `${rect.left}px`;
    petCanvas.style.top = `${rect.top}px`;
    petCanvas.style.width = `${rect.width}px`;
    petCanvas.style.height = `${rect.height}px`;
    petCanvas.style.bottom = "auto";
    petCanvas.style.position = "fixed";
    petCanvas.style.display = "block";
    petCanvas.classList.add("pet-dragging");
    pet.style.display = "none";
}

function hideStaticPetFrame() {
    if (!petCanvas || !pet) return;
    petCanvas.style.display = "none";
    petCanvas.classList.remove("pet-dragging");
    pet.style.display = "block";
}

function petDragStart(e) {
    if (!pet || !e.isPrimary || e.button !== 0) return;
    e.preventDefault();
    // playground: a stopped rock shows as its still frame, already in place,
    // and a rock caught as it falls stops falling.
    const stopped = pet.classList.contains("stopped");
    const rect = (stopped ? petCanvas : pet).getBoundingClientRect();
    cancelAnimationFrame(petFallAnimation);
    petDragging = true;
    document.body.classList.add("dragging");
    document.body.classList.add("pet-held"); // playground: see landing.css
    pet.classList.add("pet-dragging");
    pet.classList.remove("walking");
    pet.classList.remove("stopped");
    pet.style.animation = "none";
    pet.style.animationPlayState = "paused";
    clearTimeout(petStopTimeout);
    clearTimeout(petResumeTimeout);

    petDragOffsetX = e.clientX - rect.left;
    petDragOffsetY = e.clientY - rect.top;

    // Capture the current GIF frame to canvas and show it instead of the animated image.
    if (!stopped) {
        petCanvas.width = rect.width;
        petCanvas.height = rect.height;
        const ctx = petCanvas.getContext("2d");
        ctx.drawImage(pet, 0, 0, rect.width, rect.height);
    }
    petCanvas.style.left = `${rect.left}px`;
    petCanvas.style.top = `${rect.top}px`;
    petCanvas.style.bottom = "auto";
    petCanvas.style.position = "fixed";
    petCanvas.style.display = "block";
    petCanvas.classList.add("pet-dragging");
    pet.style.display = "none";

    pet.style.left = `${rect.left}px`;
    pet.style.top = `${rect.top}px`;
    pet.style.bottom = "auto";
    pet.style.transform = "none";

    petPointer = e.pointerId;
    document.addEventListener("pointermove", petDraggingMove);
    document.addEventListener("pointerup", petDragEnd);
    document.addEventListener("pointercancel", petDragEnd);
}

function petDraggingMove(e) {
    if (!petDragging || !pet || e.pointerId !== petPointer) return;
    e.preventDefault();
    // playground: the whole rock stays on the screen.
    const root = document.documentElement;
    const left = Math.max(0, Math.min(e.clientX - petDragOffsetX, root.clientWidth - petCanvas.offsetWidth));
    const top = Math.max(0, Math.min(e.clientY - petDragOffsetY, root.clientHeight - petCanvas.offsetHeight));

    pet.style.left = `${left}px`;
    pet.style.top = `${top}px`;
    petCanvas.style.left = `${left}px`;
    petCanvas.style.top = `${top}px`;
    // playground: held over the trash can, the can lights up as for an icon.
    trashIcon()?.classList.toggle("drop-target", rockOverTrash(e));
}

function petDragEnd(e) {
    if (!petDragging || !pet || e.pointerId !== petPointer) return;
    petDragging = false;
    document.body.classList.remove("dragging");
    document.body.classList.remove("pet-held");
    pet.classList.remove("pet-dragging");

    document.removeEventListener("pointermove", petDraggingMove);
    document.removeEventListener("pointerup", petDragEnd);
    document.removeEventListener("pointercancel", petDragEnd);

    if (petCanvas) {
        petCanvas.style.display = "none";
        petCanvas.classList.remove("pet-dragging");
        pet.style.display = "block";
    }

    // playground: let go over the trash can, the rock goes into it.
    trashIcon()?.classList.remove("drop-target");
    if (e.type === "pointerup" && rockOverTrash(e)) {
        throwRockAway();
        return;
    }

    if (!pet.classList.contains("stopped")) {
        pet.classList.add("walking");
    }

    petLandLeft = petLandingLeft(parseFloat(pet.style.left));
    if (petFallAnimation) {
        cancelAnimationFrame(petFallAnimation);
    }
    petFallAnimation = requestAnimationFrame(petFall);
}

// playground: the rock lands where it falls, in front of the windows, but
// never over the sponsor's icon, which must show: let go over it, it lands
// just beside it, with room for its walk of 20px each way. What counts is
// the part of its picture the rock is drawn in (landing.css clips the rest).
const rockDrawn = { left: 0.16, right: 0.84 };

function petLandingLeft(left) {
    const sponsor = appsContainer.querySelector('[data-key="armand.sponsor"]');
    if (!sponsor?.offsetParent) return left;
    const box = sponsor.getBoundingClientRect();
    const width = pet.offsetWidth, walk = 20;
    const covers = x => x + width * rockDrawn.left - walk < box.right && x + width * rockDrawn.right + walk > box.left;
    if (box.bottom <= petFloorTop() || !covers(left)) return left;
    const root = document.documentElement;
    const spots = [box.left - width * rockDrawn.right - walk, box.right - width * rockDrawn.left + walk]
        .filter(x => x >= 0 && x <= root.clientWidth - width);
    return spots.reduce((best, x) => Math.abs(x - left) < Math.abs(best - left) ? x : best, spots[0] ?? left);
}

// The top of the rock as it sits on the floor, at froppii's bottom: -9px.
function petFloorTop() {
    return document.documentElement.clientHeight - pet.offsetHeight + 9;
}

function petFall() {
    if (!pet) return;

    const petRect = pet.getBoundingClientRect();
    // playground: the rock falls to where it sits, and on to its landing spot.
    const targetTop = petFloorTop();
    const currentTop = petRect.top;
    const distance = targetTop - currentTop;
    const across = petLandLeft - petRect.left;

    if (Math.abs(distance) < 1 && Math.abs(across) < 1) {
        pet.style.top = "";
        pet.style.bottom = "-9px";
        pet.style.left = `${petLandLeft}px`;
        pet.classList.add("walking");
        resumePetWalking(true); // playground: froppii's rock never walked again
        return;
    }

    const step = Math.min(Math.abs(distance), 20);
    pet.style.top = `${currentTop + Math.sign(distance) * step}px`;
    pet.style.left = `${petRect.left + Math.sign(across) * Math.min(Math.abs(across), 20)}px`;
    petFallAnimation = requestAnimationFrame(petFall);
}

function openWindowByTitle(title, options) {
    const app = apps.find(app => app.title.toLowerCase() === title.toLowerCase());
    if (!app) {
        console.warn(`App not found: ${title}`);
        return;
    }
    openWindow(app, options);
}

function showWelcomeWindow() {
    const welcome = document.getElementById('welcome');
    if (!welcome) return;
    welcome.style.display = 'flex';
    keepInView(welcome);
    bringToFront(welcome);
}

// playground: a window's id goes by its app's key, which a rename keeps.
function appWindowId(app) {
    return 'window-' + (app.key ?? app.title).replace(/\s+/g, '-');
}

function openWindow(app, { atLoad = false, page = null } = {}) {
    if (app.title.toLowerCase() === 'welcome.txt') {
        showWelcomeWindow();
        return;
    }
    // playground: a visitor has no dashboard, so whatever opens ship.exe, its
    // icon, its menu, ?open=goal, or a reload, opens the login instead.
    if (app.key === "goal.exe" && !signedIn) {
        openWindowByTitle("login.exe", { atLoad });
        return;
    }

    const id = appWindowId(app);

    const existing = document.getElementById(id);
    if (existing) {
        existing.style.display = 'flex';
        // playground: its page may have changed while it was closed.
        if (existing.querySelector("iframe")) fitFrame(existing);
        keepInView(existing);
        bringToFront(existing);
        return;
    }

    const win = document.createElement('div');
    win.className = 'window';
    win.id = id;
    win.style.top = '80px';
    win.style.left = '80px';

    win.innerHTML = `
        <div class="windowheader" id="${id}header">
            <h1 class="headertext">${app.title}</h1>
            <button type="button" class="windowclose" aria-label="close">X</button>
        </div>
        <div class="windowcontent">
            ${app.content}
        </div>
    `;
    // playground: ship.exe can open on another of its pages (see
    // restoreWindow and openAppAt), set before its frame starts loading.
    if (page && win.querySelector("iframe")) win.querySelector("iframe").src = page;

    document.body.appendChild(win);
    // playground: it opens where placeWindow says, once its size is known.
    if (win.querySelector("iframe")) placeOnceFitted(win, atLoad);
    else placeWindow(win, { atLoad });
    keepInView(win);
    dragElement(win);
    raiseOnPress(win);
    closeOnButton(win);
    if (app.resizable !== false) resizeOnFrame(win);
    if (win.querySelector("iframe")) fitToFrame(win);
    bringToFront(win);
}

// playground: windows keep the z-index band that starts at .window's 9 in
// landing.css. Renumbering them in stacking order, instead of counting up,
// keeps them above the icons, and below the credits, the rock, and the
// taskbar. A window come to the front says so, and the trash
// can's menu closes, so it never lies over the window.
function bringToFront(win) {
    const windows = [...document.querySelectorAll(".window")]
        .filter(other => other !== win)
        .sort((a, b) => Number(getComputedStyle(a).zIndex) - Number(getComputedStyle(b).zIndex));
    windows.push(win);
    windows.forEach((other, i) => { other.style.zIndex = 9 + i; });
    document.dispatchEvent(new CustomEvent("playground:window-front"));
}

function raiseOnPress(win) {
    const raise = () => bringToFront(win);
    ["pointerdown", "focusin"].forEach(type => win.addEventListener(type, raise, true));

    // A press inside ship.exe's dashboard fires in the frame's own window, so
    // listen there too, again after each page load in the frame.
    const frame = win.querySelector("iframe");
    if (!frame) return;
    frame.addEventListener("load", () => {
        try {
            ["pointerdown", "focusin"].forEach(type => frame.contentWindow.addEventListener(type, raise, true));
        } catch {
            // A page from another origin keeps its events to itself.
        }
    });
}

// playground: the X hides its window, and opening the window again shows it
// where it was. Hiding keeps ship.exe's dashboard on the page it was on.
function closeOnButton(win) {
    const button = win.querySelector(".windowclose");
    // The header starts a drag on any press, so a press on the X stops here.
    button.addEventListener("pointerdown", event => event.stopPropagation());
    button.addEventListener("click", () => { win.style.display = "none"; });
}

// playground: a drag on any side or corner of the frame resizes the window
// by mouse, pen, or touch, and the opposite side or corner stays put. No
// window grows taller than its content (see contentHeight), or wider than
// its content can use (see widestWidth).
// landing.css sets the smallest size and lays the hit areas on the 4px
// frame only, so the header still drags and the X still closes. The window
// stops 10px inside the browser window, the margin keepInView keeps at the
// sides, and at the top where a drag stops, below the credits.
function resizeOnFrame(win) {
    // Each hit area is named by compass point: n moves the top side, e the
    // right, s the bottom, w the left, and a corner moves both of its sides.
    ["n", "e", "s", "w", "nw", "ne", "se", "sw"].forEach(edge => {
        const area = document.createElement("div");
        area.className = `windowresize ${edge}`;
        win.appendChild(area);
        const moves = side => edge.includes(side);

        let start;
        area.addEventListener("pointerdown", event => {
            if (!event.isPrimary || event.button !== 0) return;
            event.preventDefault();
            // The capture keeps the pointer's moves and its release, even off
            // the window or outside the browser window.
            area.setPointerCapture(event.pointerId);
            // From the first press the window keeps a size of its own, so a
            // drag on one side leaves the other size where it was.
            const tallest = contentHeight(win);
            const widest = widestWidth(win);
            const box = win.getBoundingClientRect();
            win.style.width = box.width + "px";
            win.style.height = box.height + "px";
            win.classList.add("resized");
            document.body.classList.add("dragging"); // see landing.css
            const style = getComputedStyle(win);
            start = {
                x: event.clientX, y: event.clientY, box, left: parseFloat(style.left), top: parseFloat(style.top),
                min: [parseFloat(style.minWidth), parseFloat(style.minHeight)],
                max: [Math.min(parseFloat(style.maxWidth), widest), Math.min(parseFloat(style.maxHeight), tallest)]
            };
        });
        area.addEventListener("pointermove", event => {
            if (!area.hasPointerCapture(event.pointerId)) return;
            const { box, min, max } = start;
            const root = document.documentElement;
            const margin = 10;
            const dx = event.clientX - start.x;
            const dy = event.clientY - start.y;
            // A window already past the edge can shrink, but not grow, and
            // none grows past the cap in landing.css.
            const fit = (from, by, least, room, most) =>
                Math.max(least, Math.min(from + by, Math.max(from, Math.min(room, most))));
            if (moves("e")) {
                win.style.width = fit(box.width, dx, min[0], root.clientWidth - margin - box.left, max[0]) + "px";
            }
            if (moves("w")) {
                const width = fit(box.width, -dx, min[0], box.right - margin, max[0]);
                win.style.width = width + "px";
                win.style.left = start.left + box.width - width + "px";
            }
            if (moves("s")) {
                win.style.height = fit(box.height, dy, min[1], desktopBottom() - box.top, max[1]) + "px";
            }
            if (moves("n")) {
                const height = fit(box.height, -dy, min[1], box.bottom - Math.max(margin, desktopTop()), max[1]);
                win.style.height = height + "px";
                win.style.top = start.top + box.height - height + "px";
            }
            clipAtTaskbar(win);
        });
        area.addEventListener("lostpointercapture", () => {
            document.body.classList.remove("dragging");
            savePlace(win);
        });
    });
}

// playground: a window opens inside the browser window, and when the browser
// window changes size, a window that no longer fits moves back in. A window
// that still fits stays where it is. The top is the credits' bottom edge, as
// for a drag, and the bottom the taskbar's top edge. landing.css caps the
// size.
function keepInView(win) {
    if (getComputedStyle(win).display === "none") return;
    const box = win.getBoundingClientRect();
    const width = document.documentElement.clientWidth;
    const height = desktopBottom();
    const margin = 10;
    const top = desktopTop();
    if (box.left < 0 || box.right > width) {
        win.style.left = Math.max(margin, Math.min(box.left, width - margin - box.width)) + "px";
    }
    if (box.top < top || box.bottom > height) {
        win.style.top = Math.max(top, Math.min(box.top, height - box.height)) + "px";
    }
    clipAtTaskbar(win);
}

// playground: the credits lie over the windows, and in the top right corner
// they would hide a header and its X. So the desktop starts below them: no
// window goes above their bottom edge. Where the required links are icons
// the credits hold nothing, and their empty box 10px down leaves the same
// margin as at the sides. landing.css reads it too, to cap the height of a
// resized window.
function desktopTop() {
    const credits = document.getElementById("credits");
    return credits ? credits.getBoundingClientRect().bottom : 0;
}

// playground: the desktop ends at the taskbar's top edge, and the taskbar
// stays in sight, as a desktop's stays on top. Windows open, fit, resize,
// and come back above it. A drag may take a window's body under it, never
// its header, and the part under it is cut off, so the taskbar shows whole
// and takes its clicks. The rock still stands on it, over its edge.
function desktopBottom() {
    return bar ? bar.getBoundingClientRect().top : document.documentElement.clientHeight;
}

// A window that ends within a pixel of the taskbar's edge, as a fitted one
// does, is cut by nothing, so its bottom handles stay whole.
function clipAtTaskbar(win) {
    const under = Math.floor(win.getBoundingClientRect().bottom - desktopBottom());
    win.style.clipPath = under > 0 ? `inset(0 0 ${under}px 0)` : "";
}

function markDesktopTop() {
    document.documentElement.style.setProperty("--desktop-top", desktopTop() + "px");
    document.documentElement.style.setProperty("--desktop-bottom", desktopBottom() + "px");
}

// playground: where a drag leaves a window. The header, less its X, keeps at
// least 80px on the screen, or all of it in a narrower window, and all of
// its height. Past the left edge the X stays in sight too, at the header's
// right end. The window stays below the credits, and its header above the
// taskbar, which lies over the windows, so the header stays in reach.
function headerInReach(win, left, top) {
    const root = document.documentElement;
    const header = win.querySelector(".windowheader");
    const close = win.querySelector(".windowclose");
    const grip = Math.min(80, close.offsetLeft - header.offsetLeft);
    return [
        Math.max(grip - close.offsetLeft, Math.min(left, root.clientWidth - header.offsetLeft - grip)),
        Math.max(desktopTop(), Math.min(top, desktopBottom() - header.offsetTop - header.offsetHeight))
    ];
}

// playground: a rock dropped near the right edge stays on the screen when
// the browser window narrows.
function petKeepInView() {
    const most = document.documentElement.clientWidth - parseFloat(getComputedStyle(pet).width);
    [pet, petCanvas].forEach(el => {
        if (parseFloat(el.style.left) > most) el.style.left = Math.max(0, most) + "px";
    });
    if (!petDragging) petLandLeft = Math.min(petLandLeft, Math.max(0, most));
}

// playground: the desktop icons sit on a grid of equal cells from the top
// left, one cell per icon. The grid fills the desktop, the browser window
// above the taskbar, edge to edge: it has whole columns and rows, each as
// near the natural cell as fits, and they stretch to divide the desktop
// exactly, each way by its own amount. A cell is never smaller than an icon
// with its label. On a phone that is 168px wide, the widest a label grows
// before it ends in an ellipsis (landing.css), and 120px high. On a desktop
// it is 102px wide, as a desktop's icons are narrow, and 140px high, for a
// label of two lines. Naturally a cell is a little larger, for a gap
// between icons. An icon sits in the middle of its cell.
const phoneLayout = matchMedia("(max-width: 560px)");
// A phone with more icons than cells packs them closer (landing.css): first
// narrower, with two lines of label, then with one, then narrower still, so
// no two share a cell.
const iconSizes = {
    phone: { cell: { width: 168, height: 124 }, box: { width: 168, height: 120 }, pad: { x: 16, y: 16 } },
    dense: { cell: { width: 98, height: 124 }, box: { width: 96, height: 120 }, pad: { x: 4, y: 4 } },
    denser: { cell: { width: 98, height: 104 }, box: { width: 96, height: 100 }, pad: { x: 4, y: 4 } },
    densest: { cell: { width: 90, height: 104 }, box: { width: 88, height: 100 }, pad: { x: 4, y: 4 } },
    desktop: { cell: { width: 104, height: 144 }, box: { width: 102, height: 140 }, pad: { x: 1, y: 16 } }
};
let iconBox = iconSizes.desktop.box;
let cellSize = { width: iconSizes.desktop.cell.width, height: iconSizes.desktop.cell.height };
let gridSize = { cols: 1, rows: 1, pad: iconSizes.desktop.pad };
// welcome.txt's width as it opens, kept for when it is closed.
let welcomeWidth = 500;

// Every cell of the grid, in the order the layout from the top left fills
// them. Each has a rank: 0 is clear, 1 lies on the floor where the rock
// walks, which would cover an icon from time to time, 2 lies under the
// credits, which hide part of it, and 3 lies over the flag, which keeps its
// clicks. An icon moved by hand goes to rank 1 at most. What counts is what
// an icon draws there: its picture and label, inside its clear padding.
// On a phone the layout fills rows from the left, below the logo's line,
// clear cells first. On a desktop the built-in icons start in three groups (see
// cornerGroups), each in the cells desktopPlan gives it, and every other
// icon, a pet or the banana peel, fills rows of three under the top left
// group, down to the bottom left group. The rest go in columns at the right
// edge, from the right, top down to the bottom right group, clear of the
// logo and welcome.txt. Only then come everything else, the groups' cells,
// the sponsor's last, and the cells under the credits and over the flag.
// A desktop too small for the groups runs every icon in the rows of three
// under the flag instead, as before. Each cell's tier says when.
function iconGrid() {
    const root = document.documentElement;
    const room = [root.clientWidth, bar.getBoundingClientRect().top];
    const fit = (space, natural, least) => {
        const near = Math.max(1, Math.round(space / natural));
        return space / near >= least ? near : Math.max(1, Math.floor(space / least));
    };
    // On a phone the icons start below the logo's line, under the flag, the
    // text row, and the logo, and no icon ever lies over the logo or its
    // line. The line's box runs 4px below its letters, so an icon may start
    // in those 4px. The first sizes whose grid holds every icon there win.
    const icons = shownIcons().length;
    const logo = phoneLayout.matches ? logoBox() : null;
    const holds = sizes => {
        const cols = fit(room[0], sizes.cell.width, sizes.box.width), rows = fit(room[1], sizes.cell.height, sizes.box.height);
        const height = room[1] / rows;
        const clear = [...Array(rows).keys()].filter(row => row * height + (height - sizes.box.height) / 2 + sizes.pad.y >= logo.bottom - 4);
        return cols * clear.length >= icons;
    };
    const sizes = !phoneLayout.matches ? iconSizes.desktop :
        [iconSizes.phone, iconSizes.dense, iconSizes.denser].find(holds) ?? iconSizes.densest;
    const packed = [iconSizes.dense, iconSizes.denser, iconSizes.densest];
    appsContainer.classList.toggle("dense", packed.includes(sizes));
    appsContainer.classList.toggle("denser", packed.slice(1).includes(sizes));
    appsContainer.classList.toggle("densest", sizes === iconSizes.densest);
    iconBox = sizes.box;
    const cols = fit(room[0], sizes.cell.width, iconBox.width);
    const rows = fit(room[1], sizes.cell.height, iconBox.height);
    const width = room[0] / cols, height = room[1] / rows;
    cellSize = { width, height };
    gridSize = { cols, rows, pad: sizes.pad };
    appsContainer.dataset.grid = `${cols} ${rows}`;
    const flag = document.getElementById("flag-link").getBoundingClientRect();
    const credits = document.getElementById("credits").getBoundingClientRect();
    // The rock's picture is square with the rock at the bottom, and a press
    // anywhere on it takes the rock. It stands 9px into the floor (landing.css).
    // On a phone the rock stays hidden (landing.css), and leaves the floor free.
    const shown = pet && [pet, petCanvas].some(el => getComputedStyle(el).display !== "none");
    const rock = shown && pet.naturalWidth ? parseFloat(getComputedStyle(pet).width) * pet.naturalHeight / pet.naturalWidth : 0;
    const floor = rock ? root.clientHeight - rock + 9 : Infinity;
    const { x: padX, y: padY } = sizes.pad;
    const plan = desktopPlan();
    const cells = [];
    for (let col = 0; col < cols; col++) {
        for (let row = 0; row < rows; row++) {
            const centre = (col + 0.5) * width, top = row * height + (height - iconBox.height) / 2;
            const drawn = {
                left: centre - Math.min(iconBox.width, width) / 2 + padX, right: centre + Math.min(iconBox.width, width) / 2 - padX,
                top: top + padY, bottom: top + iconBox.height - padY
            };
            // A phone has no cell over the logo or its line, or above them.
            if (logo && drawn.top < logo.bottom - 4) continue;
            const rank = overlaps(drawn, flag) ? 3 : overlaps(drawn, credits) ? 2 : drawn.bottom > floor ? 1 : 0;
            // A phone's tiers go by rank alone, in rows from the left.
            const id = `${col},${row}`;
            let tier = [0, 1, 6, 7][rank], key = logo ? row * cols + col : cells.length;
            const group = plan?.groups?.get(id);
            if (group && rank < 2) {
                tier = group === "armand.sponsor" ? 5 : 4;
            } else if (plan?.groups && rank < 2) {
                const rowsCell = col < 3 && row > 1 && row < rows - 1;
                const edge = drawn.left >= plan.middle.right && row < rows - 1;
                tier = rowsCell ? 0 : edge ? 1 : 2 + rank;
                key = rowsCell ? row * cols + col : edge ? (cols - col) * rows + row : key;
            } else if (plan && rank < 2) {
                const rowsCell = col < plan.columns && row > 0, edge = drawn.left >= plan.middle.right;
                tier = rowsCell ? rank * 2 : edge ? 1 + rank * 2 : 4 + rank;
                key = rowsCell ? row * cols + col : edge ? (cols - col) * rows + row : key;
            }
            cells.push({ col, row, rank, tier, key, id, group });
        }
    }
    return cells.sort((a, b) => a.tier - b.tier || a.key - b.key);
}

// playground: a fresh desktop's built-in icons, in three groups, as
// Armand's screenshot has them: the files in a row under the flag, and a
// row in each bottom corner, just above the taskbar, with the sponsor in the
// bottom left and the trash in the bottom right. Each key names its icon.
const cornerGroups = [
    { keys: ["welcome.txt", "guide.txt", "goal.exe"], row: "top", side: "left" },
    { keys: ["requirements.txt"], row: "second", side: "left" },
    { keys: ["armand.sponsor", "Bounty", "Security"], row: "bottom", side: "left" },
    { keys: ["Terms & Privacy", "Hack Club", "trash"], row: "bottom", side: "right" }
];

// The first visit's desktop, on the grid iconGrid last laid out: the
// groups' cells, and welcome.txt's spot and size below the logo's line.
// welcome.txt opens 54% of the screen wide, as the wireframe draws it,
// between its own 500px and 720px, and as tall as the desktop below the
// line, 10px above the taskbar, in the middle, between the groups. Where
// that leaves it under 480px wide, it stops 10px above the bottom groups
// instead, moved right of the top group when the two would meet, and as
// wide as it likes. Past that each, down to 360px wide and 200px tall.
// The logo gives way to the groups (landing.css reads --icon-rows), and
// the middle, which the icons leave to the logo and welcome.txt, spans
// both, with 8px to spare. A desktop too small for the groups, under 7
// columns or 3 rows, keeps its icons in rows of three under the flag, as
// before (see rowsPlan). On a phone there is no plan: windows fill the
// width there.
function desktopPlan() {
    if (phoneLayout.matches) return null;
    const { cols, rows } = gridSize;
    if (cols < 7 || rows < 4) return rowsPlan(cellSize.width);
    const root = document.documentElement;
    const block = 3 * cellSize.width;
    root.style.setProperty("--icon-rows", block + "px");
    const groups = new Map();
    cornerGroups.forEach(({ keys, row, side }) => keys.forEach((key, i) =>
        groups.set(`${side === "left" ? i : cols - 3 + i},${row === "top" ? 1 : row === "second" ? 2 : rows - 1}`, key)));
    const welcome = document.getElementById("welcome");
    if (welcome.offsetWidth) welcomeWidth = openingWidth(welcome);
    const logo = document.querySelector(".background-logo").getBoundingClientRect();
    const line = document.querySelector(".background-logo-text").getBoundingClientRect();
    const wide = Math.max(welcomeWidth, Math.min(720, Math.round(root.clientWidth * 0.54)));
    const top = Math.round(Math.max(line.bottom + 12, desktopTop()));
    // Where each group row's icons draw, from the top of their pictures to
    // the foot of their labels (see iconGrid).
    const drawnTop = row => row * cellSize.height + (cellSize.height - iconBox.height) / 2 + gridSize.pad.y;
    const topGroupBottom = drawnTop(2) + iconBox.height - 2 * gridSize.pad.y;
    const spots = [
        // Down to the taskbar, between the groups.
        { bottom: desktopBottom() - 10, from: block + 10, to: root.clientWidth - block - 10 },
        // Above the bottom groups, and right of the top one if it must be.
        { bottom: Math.min(desktopBottom() - 10, Math.floor(drawnTop(rows - 1)) - 10), from: top < topGroupBottom ? block + 10 : 10, to: root.clientWidth - 10 }
    ].map(({ bottom, from, to }) => {
        const width = Math.min(wide, to - from);
        const left = Math.round(Math.max((root.clientWidth - width) / 2, from));
        return { left, top, width: Math.floor(width), height: Math.floor(bottom - top) };
    });
    const spot = [[480, 300], [360, 200]].flatMap(([width, height]) => spots.filter(spot => spot.width >= width && spot.height >= height))[0] ?? null;
    const middle = {
        left: Math.min(logo.left, spot?.left ?? Infinity) - 8,
        right: Math.max(logo.right, spot ? spot.left + spot.width : -Infinity) + 8
    };
    return { columns: 3, groups, welcome: spot, middle };
}

// A desktop too small for the groups: every icon in rows under the flag,
// in three columns, or two when welcome.txt has no room beside three, and
// welcome.txt below the logo's line, in the middle or just right of the
// columns, and narrower, down to 360px, when the screen has no room for
// all of it.
function rowsPlan(cellWidth) {
    const root = document.documentElement;
    const welcome = document.getElementById("welcome");
    if (welcome.offsetWidth) welcomeWidth = openingWidth(welcome);
    for (const columns of [3, 2]) {
        const block = columns * cellWidth;
        root.style.setProperty("--icon-rows", block + "px");
        const logo = document.querySelector(".background-logo").getBoundingClientRect();
        const line = document.querySelector(".background-logo-text").getBoundingClientRect();
        const wide = Math.max(welcomeWidth, Math.min(720, Math.round(root.clientWidth * 0.54)));
        const opens = Math.min(wide, root.clientWidth - 20);
        const left = Math.round(Math.max((root.clientWidth - opens) / 2, block + 10));
        const width = Math.min(opens, root.clientWidth - 10 - left);
        if (width < 360 && columns === 3) continue;
        const top = Math.round(Math.max(line.bottom + 12, desktopTop()));
        const spot = width >= 360 ? { left, top, width, height: Math.floor(desktopBottom() - 10 - top) } : null;
        const middle = {
            left: Math.min(logo.left, spot?.left ?? Infinity) - 8,
            right: Math.max(logo.right, spot ? spot.left + spot.width : -Infinity) + 8
        };
        return { columns, welcome: spot, middle };
    }
}

// The logo and its line, as one box.
function logoBox() {
    const [logo, line] = logoBoxes();
    return { left: Math.min(logo.left, line.left), right: Math.max(logo.right, line.right), top: Math.min(logo.top, line.top), bottom: Math.max(logo.bottom, line.bottom) };
}

// Two boxes overlap by more than a pixel's rounding.
function overlaps(a, b) {
    return a.left < b.right - 1 && b.left < a.right - 1 && a.top < b.bottom - 1 && b.top < a.bottom - 1;
}

// Saved icons keep their cells. One whose cell is gone, as after the browser
// window shrank, or taken, takes the free cell nearest it until there is
// room again. The rest fill free cells from the top left, so an icon added
// later takes a free cell and moves none of the others.
function arrangeIcons() {
    const cells = iconGrid();
    const taken = new Set();
    const icons = shownIcons();
    icons.forEach(icon => fitLabelWords(icon.querySelector("p")));
    const put = (icon, cell) => {
        taken.add(cell.id);
        iconCells.set(icon, [cell.col, cell.row]);
        placeIcon(icon, cell.col * cellSize.width, cell.row * cellSize.height);
        icon.dataset.cell = cell.id;
    };
    const saved = icons.filter(icon => savedIcons[icon.dataset.key]);
    const lost = saved.filter(icon => {
        const [col, row] = savedIcons[icon.dataset.key];
        const cell = cells.find(cell => cell.col === col && cell.row === row && cell.rank < 2);
        if (!cell || taken.has(cell.id)) return true;
        put(icon, cell);
        return false;
    });
    // No icon but the sponsor's own takes the sponsor's cell.
    const notSponsors = cells.filter(cell => cell.group !== "armand.sponsor");
    const own = icon => icon.dataset.key === "armand.sponsor" ? cells : notSponsors;
    lost.forEach(icon => {
        const [col, row] = savedIcons[icon.dataset.key];
        put(icon, nearestCell(own(icon), taken, col * cellSize.width, row * cellSize.height, 0));
    });
    const unsaved = icons.filter(icon => !savedIcons[icon.dataset.key]);
    // A built-in icon takes its group's cell, if nothing saved sits there.
    const groupCell = new Map(cells.filter(cell => cell.group && cell.rank < 2).map(cell => [cell.group, cell]));
    const rest = unsaved.filter(icon => {
        const cell = groupCell.get(icon.dataset.key);
        if (!cell || taken.has(cell.id)) return true;
        put(icon, cell);
        return false;
    });
    // Without the groups, the sponsor's icon keeps a spot in the rows under
    // the flag, where it always shows, even on a screen too short for all
    // nine there.
    if (!groupCell.size) {
        const rowSpots = cells.filter(cell => cell.tier === 0 && !taken.has(cell.id)).length;
        const sponsor = rest.findIndex(icon => icon.dataset.key === "armand.sponsor");
        if (rowSpots && sponsor >= rowSpots) rest.splice(rowSpots - 1, 0, ...rest.splice(sponsor, 1));
    }
    rest.forEach(icon => put(icon, firstCell(own(icon), taken)));
}

// The first free cell in the layout's order. With more icons than cells,
// the rest share the grid's last cell, at the bottom right.
function firstCell(cells, taken) {
    return cells.find(cell => !taken.has(cell.id)) ??
        cells.reduce((last, cell) => cell.col > last.col || (cell.col === last.col && cell.row > last.row) ? cell : last, cells[0]) ??
        { col: 0, row: 0, id: "0,0" };
}

// The free cell nearest a point, by the cells' top left corners, of rank 1
// at most, or for an icon the screen pushed out, of rank 0 if one is free.
function nearestCell(cells, taken, x, y, rank = 1) {
    const free = cells.filter(cell => cell.rank <= rank && !taken.has(cell.id));
    const away = cell => Math.hypot(cell.col * cellSize.width - x, cell.row * cellSize.height - y);
    const best = free.reduce((best, cell) => away(cell) < away(best) ? cell : best, free[0]);
    return best ?? (rank < 1 ? nearestCell(cells, taken, x, y) : firstCell(cells, taken));
}

// An icon's box sits in the middle of the cell whose top left corner is at
// (left, top), so a label of any width lines up.
function placeIcon(icon, left, top) {
    icon.style.left = left + cellSize.width / 2 + "px";
    icon.style.top = top + (cellSize.height - iconBox.height) / 2 + "px";
}

// A saved layout that no longer fits the screen, as after the browser window
// shrank between visits, gives way to the layout from the top left.
function fitSavedIcons() {
    const cells = iconGrid();
    const fits = ([col, row]) => cells.some(cell => cell.col === col && cell.row === row && cell.rank < 2);
    const icons = shownIcons();
    if (icons.every(icon => !savedIcons[icon.dataset.key] || fits(savedIcons[icon.dataset.key]))) return;
    savedIcons = {};
    try {
        localStorage.removeItem(iconsStore);
    } catch {
        // Storage blocked: the layout lasts until the page closes.
    }
}

// Each saved cell is a column and a row. Anything else in storage is ignored.
function loadIcons() {
    try {
        const saved = JSON.parse(localStorage.getItem(iconsStore));
        return Object.fromEntries(Object.entries(saved ?? {}).filter(([, cell]) =>
            Array.isArray(cell) && cell.length === 2 && cell.every(Number.isInteger)));
    } catch {
        return {};
    }
}

// After a move, every icon's cell is saved, so the ones not moved stay put
// too. Icons not on the page now keep their saved cells.
function saveIcons() {
    iconCells.forEach((cell, icon) => { savedIcons[icon.dataset.key] = cell; });
    try {
        localStorage.setItem(iconsStore, JSON.stringify(savedIcons));
    } catch {
        // Storage blocked: the layout lasts until the page closes.
    }
}

function selectIcons(icons) {
    appsContainer.querySelectorAll(".app").forEach(icon => icon.classList.toggle("selected", icons.includes(icon)));
}

function selectedIcons() {
    return [...appsContainer.querySelectorAll(".app.selected")];
}

const withToggle = event => event.shiftKey || event.metaKey || event.ctrlKey;

// A press moves further than this before it drags, in CSS pixels: 4 for a
// mouse or pen, as the drag threshold on Windows, and 10 for a finger,
// which wobbles more on a tap, close to the touch slop on Android.
const dragSlop = event => event.pointerType === "touch" ? 10 : 4;

// A finger held this long on an icon, in milliseconds, without a drag,
// opens the icon's menu, as a right click does: long enough that a tap
// never opens it.
const longPress = 500;

// The press on an icon now, and whether it became a drag. A drag's release
// ends in a click on the icon, which opens nothing.
let iconPress = null;
let iconDragged = false;

// A click opens an icon and leaves it the one selected: a window opens, and
// a link follows itself into a new tab. A double-click opens once: its
// second click shows the same window, and a link follows only the first.
// With Shift, Cmd, or Ctrl held, a click adds the icon to the selection or
// takes it out, and opens nothing. Enter opens, and the arrow keys select
// the next icon that way. A right click opens the icon's menu at the
// pointer, and the menu key or Shift+F10 opens it by the icon: a key's
// contextmenu has no pointer. A pet's field for a new name (see renamePet)
// keeps its presses and keys, and the browser's own menu.
function setUpIcon(icon, open) {
    icon.addEventListener("pointerdown", pressIcon);
    icon.addEventListener("pointermove", dragIcons);
    ["pointerup", "pointercancel"].forEach(type => icon.addEventListener(type, dropIcons));
    icon.addEventListener("contextmenu", event => {
        if (event.target.closest(".rename")) return;
        event.preventDefault();
        // A phone may send its own for a long press (see holdIcon).
        if (iconPress?.icon === icon) holdIcon(iconPress);
        else openIconMenu(icon, event.clientX || event.clientY ? [event.clientX, event.clientY] : null);
    });
    icon.addEventListener("click", event => {
        if (event.target.closest(".rename")) return;
        if (iconDragged || withToggle(event) || (!open && event.detail > 1)) {
            event.preventDefault();
            if (!iconDragged && withToggle(event)) icon.classList.toggle("selected");
            return;
        }
        selectIcons([icon]);
        if (open) open();
    });
    icon.addEventListener("keydown", event => {
        if (event.target !== icon) return;
        if (event.key === "ContextMenu" || (event.key === "F10" && event.shiftKey)) {
            event.preventDefault();
            openIconMenu(icon);
            return;
        }
        // Enter opens only here, so the same press cannot also choose in a
        // menu it opened, such as the trash can's.
        if (event.key === "Enter" && open) {
            event.preventDefault();
            selectIcons([icon]);
            open();
        }
        const step = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[event.key];
        if (!step) return;
        event.preventDefault();
        const next = iconToward(icon, step);
        if (!next) return;
        selectIcons([next]);
        next.focus();
    });
}

// A press on an icon outside the selection selects it alone, so a drag
// takes it by itself. One on a selected icon drags the whole selection.
// The capture keeps the pointer's moves and its release, even off the
// browser window.
function pressIcon(event) {
    if (!event.isPrimary || event.button !== 0 || event.target.closest(".rename")) return;
    const icon = event.currentTarget;
    if (!withToggle(event) && !icon.classList.contains("selected")) selectIcons([icon]);
    icon.setPointerCapture(event.pointerId);
    iconPress = { icon, x: event.clientX, y: event.clientY, slop: dragSlop(event), group: null };
    iconDragged = false;
    if (event.pointerType === "touch") iconPress.hold = setTimeout(holdIcon, longPress, iconPress);
}

// A long press opens the icon's menu where the finger is, once, whether the
// wait or the browser's own contextmenu for it comes first. The finger then
// no longer drags the icon.
function holdIcon(press) {
    if (iconPress !== press || press.group || press.held) return;
    clearTimeout(press.hold);
    press.held = true;
    openIconMenu(press.icon, [press.x, press.y]);
}

// The browser may still end a long press in a click where the finger lifts,
// which the menu may lie under by then, so that click lands on nothing. The
// next press, or a second, ends the wait for it.
function swallowClick() {
    const swallow = event => {
        event.preventDefault();
        event.stopPropagation();
        stop();
    };
    const stop = () => {
        clearTimeout(timer);
        document.removeEventListener("click", swallow, true);
        document.removeEventListener("pointerdown", stop, true);
    };
    const timer = setTimeout(stop, 1000);
    document.addEventListener("click", swallow, true);
    document.addEventListener("pointerdown", stop, true);
}

// The selected icons follow the pointer together, all inside the browser
// window and above the taskbar.
function dragIcons(event) {
    const press = iconPress;
    if (!press || !press.icon.hasPointerCapture(event.pointerId)) return;
    const dx = event.clientX - press.x;
    const dy = event.clientY - press.y;
    if (!press.group) {
        if (press.held || Math.hypot(dx, dy) < press.slop) return;
        clearTimeout(press.hold);
        press.icon.classList.add("selected");
        press.group = selectedIcons().map(icon => {
            icon.classList.add("moving");
            const [col, row] = iconCells.get(icon);
            return { icon, left: col * cellSize.width, top: row * cellSize.height };
        });
        iconDragged = true;
        document.body.classList.add("dragging"); // see landing.css
    }
    const { width, height } = cellSize;
    const lefts = press.group.map(item => item.left);
    const tops = press.group.map(item => item.top);
    const x = Math.max(-Math.min(...lefts), Math.min(dx, document.documentElement.clientWidth - width - Math.max(...lefts)));
    const y = Math.max(-Math.min(...tops), Math.min(dy, bar.getBoundingClientRect().top - height - Math.max(...tops)));
    press.group.forEach(item => {
        item.x = item.left + x;
        item.y = item.top + y;
        placeIcon(item.icon, item.x, item.y);
    });
    trashIcon()?.classList.toggle("drop-target", overTrash(event, press.group.map(item => item.icon)));
}

// On release each icon snaps to the cell under it, or if that is taken or
// under the credits, to the free cell nearest it. None lands on another.
// Let go over the trash can, the icons go back to their cells and into it.
function dropIcons(event) {
    const press = iconPress;
    if (!press || press.icon !== event.currentTarget) return;
    iconPress = null;
    clearTimeout(press.hold);
    if (press.held && event.type === "pointerup") swallowClick();
    if (!press.group) return;
    document.body.classList.remove("dragging");
    const cells = iconGrid();
    const moving = press.group.map(item => item.icon);
    trashIcon()?.classList.remove("drop-target");
    if (event.type === "pointerup" && overTrash(event, moving)) {
        press.group.forEach(item => {
            placeIcon(item.icon, item.left, item.top);
            item.icon.classList.remove("moving");
        });
        throwAway(moving);
        setTimeout(() => { iconDragged = false; });
        return;
    }
    const taken = new Set([...iconCells]
        .filter(([icon]) => icon.isConnected && !moving.includes(icon))
        .map(([, [col, row]]) => `${col},${row}`));
    const put = (item, cell) => {
        taken.add(cell.id);
        iconCells.set(item.icon, [cell.col, cell.row]);
        placeIcon(item.icon, cell.col * cellSize.width, cell.row * cellSize.height);
        item.icon.dataset.cell = cell.id;
        item.icon.classList.remove("moving");
    };
    const unplaced = press.group.filter(item => {
        const col = Math.round(item.x / cellSize.width);
        const row = Math.round(item.y / cellSize.height);
        const cell = cells.find(cell => cell.col === col && cell.row === row && cell.rank < 2);
        if (!cell || taken.has(cell.id)) return true;
        put(item, cell);
        return false;
    });
    unplaced.forEach(item => put(item, nearestCell(cells, taken, item.x, item.y)));
    saveIcons();
    // The click that follows the release comes before this.
    setTimeout(() => { iconDragged = false; });
}

// The nearest icon in a direction on the grid, preferring one in line.
function iconToward(icon, [dcol, drow]) {
    const [col, row] = iconCells.get(icon);
    let best = null;
    let bestScore = Infinity;
    iconCells.forEach(([c, r], other) => {
        const along = (c - col) * dcol + (r - row) * drow;
        const across = Math.abs((c - col) * drow + (r - row) * dcol);
        const score = along + 2 * across;
        if (other === icon || !other.isConnected || along <= 0 || score >= bestScore) return;
        best = other;
        bestScore = score;
    });
    return best;
}

// playground: what of an icon the selection box takes: the box around its
// picture's drawn pixels, at the size the picture shows. The server
// measures each picture ahead of time (app/services/icon_bounds.rb). The
// label, the shortcut arrow, and a picture's empty corners do not count. A
// picture with no box counts whole.
const iconBounds = JSON.parse(appsContainer.dataset.iconBounds || "{}");

function drawnBox(icon) {
    const picture = icon.querySelector(".appicon");
    const shown = picture.getBoundingClientRect();
    const [left, top, right, bottom] = iconBounds[picture.getAttribute("src")] ?? [0, 0, 1, 1];
    return {
        left: shown.left + left * shown.width, top: shown.top + top * shown.height,
        right: shown.left + right * shown.width, bottom: shown.top + bottom * shown.height
    };
}

// playground: a drag across the wallpaper draws a box that selects every
// icon whose picture it touches. A press there clears the selection first,
// unless Shift, Cmd, or Ctrl is held, which adds to it. A press on a window,
// the rock, the credits, the flag, or the taskbar lands on that instead.
const selectionBox = document.createElement("div");
selectionBox.id = "selection-box";
selectionBox.hidden = true;
selectionBox.innerHTML = `<svg aria-hidden="true"><path></path><path visibility="hidden"></path></svg>`;
document.body.appendChild(selectionBox);
const boxDrawings = [...selectionBox.querySelectorAll("path")];

// The tint over a selected icon's picture (landing.css): the windows' blue at
// just under half strength, over the drawn pixels only, so a clear corner stays clear.
// A filter reads only what shows, so it works on a picture from anywhere.
document.body.insertAdjacentHTML("beforeend", `
    <svg class="icon-tint" aria-hidden="true" width="0" height="0">
        <filter id="icon-tint" color-interpolation-filters="sRGB">
            <feFlood flood-color="#3a70b8" flood-opacity="0.45"/>
            <feComposite in2="SourceAlpha" operator="in"/>
            <feBlend in2="SourceGraphic"/>
        </filter>
    </svg>
`);
const stillMotion = matchMedia("(prefers-reduced-motion: reduce)");
let boxPress = null;
let boxSides = null;
let boxBoil = null;

document.addEventListener("pointerdown", event => {
    if (!event.isPrimary || event.button !== 0) return;
    if (event.target !== document.body && event.target !== document.documentElement) return;
    if (!withToggle(event)) selectIcons([]);
    event.target.setPointerCapture(event.pointerId);
    boxPress = { id: event.pointerId, x: event.clientX, y: event.clientY, slop: dragSlop(event), kept: selectedIcons() };
    document.body.classList.add("dragging"); // see landing.css
});

document.addEventListener("pointermove", event => {
    const press = boxPress;
    if (!press || event.pointerId !== press.id) return;
    if (selectionBox.hidden && Math.hypot(event.clientX - press.x, event.clientY - press.y) < press.slop) return;
    const box = {
        left: Math.min(press.x, event.clientX), top: Math.min(press.y, event.clientY),
        right: Math.max(press.x, event.clientX), bottom: Math.max(press.y, event.clientY)
    };
    Object.assign(selectionBox.style, {
        left: box.left + "px", top: box.top + "px", width: box.right - box.left + "px", height: box.bottom - box.top + "px"
    });
    drawSelectionBox(event.clientX - press.x, event.clientY - press.y);
    if (selectionBox.hidden) startBoil();
    selectionBox.hidden = false;
    const touched = shownIcons().filter(icon => {
        const it = drawnBox(icon);
        return it.left <= box.right && box.left <= it.right && it.top <= box.bottom && box.top <= it.bottom;
    });
    selectIcons([...press.kept, ...touched]);
});

["pointerup", "pointercancel"].forEach(type => document.addEventListener(type, event => {
    if (!boxPress || event.pointerId !== boxPress.id) return;
    boxPress = null;
    selectionBox.hidden = true;
    clearInterval(boxBoil);
    document.body.classList.remove("dragging");
}));

// The box's outline is drawn twice by hand in marker, the way the meter's
// pending stripes are, and the two drawings take turns every 130ms, as an
// animator's line boils on twos. Each side is its own stroke, with its own
// uneven width and rough edges and a blunt, bumpy end, and the four meet at
// the corners without crossing: the top and bottom run out to the outer
// edges of the sides, and each side ends inside them. A side's bumps are
// fixed along its length from the corner where the drag started, so it
// keeps its shape as the box grows and only gains new line at the far end.
// With reduced motion, one drawing stays.
function startBoil() {
    boxDrawings.forEach((drawing, i) => drawing.setAttribute("visibility", i ? "hidden" : "visible"));
    clearInterval(boxBoil);
    if (stillMotion.matches) return;
    boxBoil = setInterval(() => boxDrawings.forEach(drawing =>
        drawing.setAttribute("visibility", drawing.getAttribute("visibility") === "hidden" ? "visible" : "hidden")), 130);
}

// dx and dy run from the press to the pointer. In the box's own frame the
// press is one corner and the pointer the opposite one.
function drawSelectionBox(dx, dy) {
    boxSides ??= [1, 2, 3, 4].map(markerSide);
    const w = Math.abs(dx), h = Math.abs(dy);
    const ax = dx < 0 ? w : 0, ay = dy < 0 ? h : 0;
    const fx = w - ax, fy = h - ay;
    // Each side runs from the press's end. Its across offsets point to its
    // left, which lies outside the box for the side through the press when
    // the drag runs down and right or up and left (k is 1), and inside it
    // otherwise. The far side is the other way round.
    const k = Math.sign(dx || 1) * Math.sign(dy || 1);
    const outward = ([off, left, right], near) => (k > 0) === near ? off + left : right - off;
    boxDrawings.forEach((drawing, variant) => {
        const [top, near, bottom, far] = boxSides.map(side => side[variant]);
        // The top and bottom, through the press and the pointer, run out to
        // the sides' outer edges. The sides start and end on the top and
        // bottom's middles, inside them.
        const nearEnds = [strokeShape(near, 0), strokeShape(near, h)];
        const farEnds = [strokeShape(far, 0), strokeShape(far, h)];
        const topEnds = [strokeShape(top, 0), strokeShape(top, w)];
        const bottomEnds = [strokeShape(bottom, 0), strokeShape(bottom, w)];
        drawing.setAttribute("d", [
            markerStroke(top, ax, ay, fx, ay, -outward(nearEnds[0], true), w + outward(farEnds[0], false)),
            markerStroke(near, ax, ay, ax, fy, k * topEnds[0][0], h + k * bottomEnds[0][0]),
            markerStroke(bottom, ax, fy, fx, fy, -outward(nearEnds[1], true), w + outward(farEnds[1], false)),
            markerStroke(far, fx, ay, fx, fy, k * topEnds[1][0], h + k * bottomEnds[1][0])
        ].join(""));
    });
}

// Two drawings of one side of the box. They share the side's slow sway,
// and each has its own small wobble, width, edges, and ends.
function markerSide(seed) {
    const random = seeded(seed);
    let lines = 0;
    const rough = (gapLo, gapHi, size) => roughness(seed * 64 + ++lines, gapLo, gapHi, size);
    const sway = rough(40, 90, 0.6);
    return [0, 1].map(() => ({
        sway,
        wobble: rough(12, 28, 0.3),
        edges: [0, 1].map(() => [rough(7, 18, 0.28), rough(2, 5, 0.14)]),
        width: 2.8 + random() * 0.9,
        shift: gauss(random) * 0.4,
        ends: [0, 1].map(() => ({
            bulge: 0.05 + random() * 0.15,
            bumps: [0, 1, 2, 3, 4].map(() => Math.max(-0.25, Math.min(0.25, gauss(random) * 0.12)))
        }))
    }));
}

// At a point along a side: how far its line strays from the box's edge, and
// how far each of its two edges lies from there, left then right. Points
// every 2px from the press's corner never change, so each is worked out once.
function strokeShape(side, u) {
    const shape = () => [
        side.shift + side.sway(u) + side.wobble(u),
        side.width / 2 + side.edges[0][0](u) + side.edges[0][1](u),
        side.width / 2 + side.edges[1][0](u) + side.edges[1][1](u)
    ];
    if (u < 0 || u % 2) return shape();
    side.shapes ??= [];
    return side.shapes[u / 2] ??= shape();
}

// One side as a filled outline, along the edge from (x0, y0) at the press's
// end to (x1, y1), from and to measured along it from (x0, y0).
function markerStroke(side, x0, y0, x1, y1, from, to) {
    const length = Math.hypot(x1 - x0, y1 - y0);
    const [ux, uy] = length ? [(x1 - x0) / length, (y1 - y0) / length] : [x0 === x1 ? 0 : 1, x0 === x1 ? 1 : 0];
    const [nx, ny] = [-uy, ux];
    // Every 2px from the press's corner, so the line a side has drawn stays
    // put as it grows.
    const marks = [[from, strokeShape(side, from)]];
    for (let i = Math.max(0, Math.floor(from / 2) + 1); i * 2 < to; i++) marks.push([i * 2, strokeShape(side, i * 2)]);
    marks.push([to, strokeShape(side, to)]);
    const point = (u, off) => [x0 + ux * u + nx * off, y0 + uy * u + ny * off];
    // A blunt end, across from one edge to the other: nearly flat, a little
    // rounded, and bumpy.
    const end = ([u, [off, left, right]], sign, cap) => [0.1, 0.3, 0.5, 0.7, 0.9].map((f, j) => {
        const [a, b] = sign > 0 ? [left, -right] : [-right, left];
        const [x, y] = point(u, off + a + (b - a) * f);
        const out = sign * (cap.bulge * side.width / 2 * Math.sin(Math.PI * f) ** 0.3 + cap.bumps[j]);
        return [x + ux * out, y + uy * out];
    });
    const points = [
        ...marks.map(([u, [off, left]]) => point(u, off + left)),
        ...end(marks[marks.length - 1], 1, side.ends[1]),
        ...marks.slice().reverse().map(([u, [off, , right]]) => point(u, off - right)),
        ...end(marks[0], -1, side.ends[0])
    ];
    return "M" + points.map(([x, y]) => x.toFixed(1) + " " + y.toFixed(1)).join("L") + "Z";
}

// Smooth random offsets along a line, through knots at uneven spacing, so
// the bumps never repeat. The knots go on as far as the line does, the same
// each time, since each side has its own random source for them.
function roughness(seed, gapLo, gapHi, size) {
    const random = seeded(seed);
    const knots = [];
    let next = -3 * gapHi;
    return u => {
        while (knots.length < 4 || knots[knots.length - 2][0] <= u) {
            knots.push([next, gauss(random) * size]);
            next += gapLo + random() * (gapHi - gapLo);
        }
        let lo = 1, hi = knots.length - 3;
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1;
            if (knots[mid][0] <= u) lo = mid; else hi = mid - 1;
        }
        const p0 = knots[lo - 1][1], p1 = knots[lo][1], p2 = knots[lo + 1][1], p3 = knots[lo + 2][1];
        const t = Math.min(1, Math.max(0, (u - knots[lo][0]) / (knots[lo + 1][0] - knots[lo][0])));
        // Catmull-Rom, so the bumps are round, not stepped.
        return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
    };
}

// A small seeded random source (mulberry32), so each side draws the same
// way every time.
function seeded(seed) {
    let a = seed * 0x9e3779b9;
    return () => {
        a = (a + 0x6d2b79f5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

function gauss(random) {
    return Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());
}

// playground: a signed-in participant's pets, each an icon on the desktop
// that opens its pet page in a window of its own, as ship.exe showed it. The
// page says who is signed in. The icons follow the pets: after any page in a
// desktop window loads, the desktop asks again, so a pet made, renamed, or
// deleted in a window shows at once.
const signedIn = "pets" in appsContainer.dataset;
const petIcons = new Map();
let petRefresh = null;
const petsRefreshed = [];
let petToOpen = null;

function setUpPets() {
    if (!signedIn) return;
    syncPets(JSON.parse(appsContainer.dataset.pets));
    document.addEventListener("load", event => {
        const frame = event.target;
        if (frame.tagName !== "IFRAME" || !frame.closest(".window")) return;
        refreshPets();
        try {
            frame.contentDocument.addEventListener("turbo:load", refreshPets);
        } catch {
            // A page from another origin keeps its events to itself.
        }
    }, true);
}

// A pet made a moment ago has no icon until the desktop asks again.
function openPetWindowSoon(id, url) {
    if (petIcons.has(id)) return openPetWindow(id, url);
    petToOpen = { id, url };
    refreshPets();
}

// The pets again, a moment after the last ask. It answers once they are in.
function refreshPets() {
    clearTimeout(petRefresh);
    petRefresh = setTimeout(async () => {
        try {
            const response = await fetch("/projects", { headers: { Accept: "application/json" } });
            if (response.ok) syncPets(await response.json());
        } catch {
            // Offline or signed out: the icons stay as they are.
        }
        petsRefreshed.splice(0).forEach(done => done());
    }, 150);
    return new Promise(done => petsRefreshed.push(done));
}

// Every pet wears the same file icon. A pet waiting in the trash for its
// delete popups stays out of the way. An icon keeps its pet's saved name,
// which its label shows except while a rename from its menu saves.
function syncPets(pets) {
    const ids = new Set(pets.map(pet => pet.id));
    petIcons.forEach((icon, id) => { if (!ids.has(id)) forgetPet(id); });
    let renamed = false;
    pets.forEach(pet => {
        let icon = petIcons.get(pet.id);
        if (icon && icon.dataset.name !== pet.name) renamed = true;
        if (!icon) {
            icon = addIcon({ key: `pet-${pet.id}`, title: pet.name, picture: appsIcons.pet, order: 1000 + pet.id,
                open: () => openPetWindow(pet.id) });
            icon.classList.add("pet");
            icon.dataset.pet = pet.id;
            petIcons.set(pet.id, icon);
            if (deleting?.id === pet.id || deleteQueue.some(item => item.id === pet.id)) icon.remove();
        }
        icon.dataset.name = pet.name;
        setLabel(icon.querySelector("p"), pet.name);
        const win = document.getElementById(`window-pet-${pet.id}`);
        if (win) win.querySelector(".headertext").textContent = win.querySelector("iframe").title = pet.name;
        const ship = document.getElementById(`window-ship-${pet.id}`);
        if (ship) ship.querySelector(".headertext").textContent = ship.querySelector("iframe").title = `${pet.name}.ship`;
    });
    arrangeIcons();
    // ship.exe's list names the pets too.
    const goal = document.querySelector("#window-goal\\.exe iframe");
    if (renamed && goal?.contentWindow.location.pathname === "/dashboard") goal.contentWindow.location.reload();
    // A pet asked for before its icon came opens now.
    if (petToOpen && petIcons.has(petToOpen.id)) {
        openPetWindow(petToOpen.id, petToOpen.url);
        petToOpen = null;
    }
}

// A deleted pet leaves the desktop with its windows.
function forgetPet(id) {
    petIcons.get(id)?.remove();
    iconCells.delete(petIcons.get(id));
    petIcons.delete(id);
    document.getElementById(`window-pet-${id}`)?.remove();
    document.getElementById(`window-ship-${id}`)?.remove();
}

// Each pet has one window. It opens where placeWindow says, and on a phone a
// step down and right of the pet windows open. It opens on the pet's page, or
// on the page asked for, such as its edit page.
function openPetWindow(id, url, { atLoad = false } = {}) {
    const icon = petIcons.get(id);
    if (!icon) return;
    const name = icon.querySelector("p").textContent;
    const winId = `window-pet-${id}`;
    let win = document.getElementById(winId);
    if (!win) {
        const open = document.querySelectorAll(".pet-window:not([style*='display: none'])").length;
        win = document.createElement("div");
        win.className = "window pet-window";
        win.id = winId;
        win.style.left = win.style.top = 80 + 30 * open + "px";
        win.innerHTML = `
            <div class="windowheader" id="${winId}header">
                <h1 class="headertext"></h1>
                <button type="button" class="windowclose" aria-label="close">X</button>
            </div>
            <div class="windowcontent">
                <iframe class="pet-frame"></iframe>
            </div>
        `;
        win.querySelector("iframe").src = url || `/projects/${id}`;
        document.body.appendChild(win);
        dragElement(win);
        raiseOnPress(win);
        closeOnButton(win);
        resizeOnFrame(win);
        fitToFrame(win);
        placeOnceFitted(win, atLoad);
    } else if (url) {
        const view = win.querySelector("iframe").contentWindow;
        if (view.location.pathname + view.location.search !== url) view.location.href = url;
    }
    // The pet's name is the participant's own text, so it goes in as text.
    win.querySelector(".headertext").textContent = win.querySelector("iframe").title = name;
    win.style.display = "flex";
    // Its page may have changed while it was closed.
    fitFrame(win);
    keepInView(win);
    bringToFront(win);
}

// playground: the trash can. An icon dragged onto it leaves the desktop, and
// the can looks full. A click or a right click on the can opens a menu that
// puts icons back. The built-in icons are never deleted, only put away, and
// the sponsor's credit stays on the desktop. The rock let go over the can
// goes in too, and comes back out onto the floor. A pet dragged onto it asks
// with the delete popups, laid over the desktop in a clear frame: a yes to
// all three deletes it, as on its edit page, and anything else puts it back.
// What is in the trash follows a signed-in participant's account, and stays
// in this browser for a visitor.
const trashStore = "playground-desktop-trash";
const trashed = new Map();
const trashMenu = Object.assign(document.createElement("div"), { id: "trash-menu", hidden: true });
trashMenu.setAttribute("role", "menu");
trashMenu.setAttribute("aria-label", "trash");
document.body.appendChild(trashMenu);
const deleteFrame = Object.assign(document.createElement("iframe"), { className: "delete-frame", title: "delete.exe", hidden: true });
document.body.appendChild(deleteFrame);
const deleteQueue = [];
let deleting = null;

const trashIcon = () => appsContainer.querySelector('[data-key="trash"]');
// The rock goes into the trash too, under this key, and out of sight.
const rockKey = "rock";
const bananaPeelKey = "banana peel";
// This browser's record that its visitor took the banana peel out. An
// account keeps that record on the server instead.
const peelOutStore = "playground-banana-peel-out";
const trashName = icon => icon === pet ? "rock" : icon.querySelector("p").textContent;
const keptOut = icon => icon.dataset.key === "trash" || icon.dataset.key === "armand.sponsor";

// The banana peel is in the trash unless this visitor or account took it
// out themselves: in a fresh trash, and in one saved without it before it
// came. An account's trash comes with it already (User#desktop_trash_with_peel).
// The rest of a saved trash stays as it was saved.
function setUpTrashContents() {
    let keys = [bananaPeelKey];
    let peelOut = false;
    try {
        const saved = signedIn ? appsContainer.dataset.trash : localStorage.getItem(trashStore);
        if (saved !== null) keys = JSON.parse(saved) ?? [];
        peelOut = !signedIn && localStorage.getItem(peelOutStore) !== null;
    } catch {
        // Storage blocked, or nothing readable saved: the trash starts fresh.
    }
    if (!signedIn && Array.isArray(keys) && !keys.includes(bananaPeelKey) && !peelOut) keys = [bananaPeelKey, ...keys];
    [...appsContainer.querySelectorAll(".app")]
        .filter(icon => Array.isArray(keys) && keys.includes(icon.dataset.key) && !icon.dataset.pet && !keptOut(icon))
        .forEach(icon => { icon.remove(); trashed.set(icon.dataset.key, icon); });
    if (pet && Array.isArray(keys) && keys.includes(rockKey)) {
        hideRock();
        trashed.set(rockKey, pet);
    }
    showTrash();
}

// The rock in the trash stops walking and shows nowhere, still frame and all.
function hideRock() {
    clearTimeout(petStopTimeout);
    clearTimeout(petResumeTimeout);
    cancelAnimationFrame(petFallAnimation);
    pet.classList.remove("walking", "stopped");
    [pet, petCanvas].forEach(el => el.classList.add("in-trash"));
}

// The can counts under the rock only where it shows, so a rock let go on a
// window over the can lands beside the window as before.
function rockOverTrash(event) {
    const under = document.elementsFromPoint(event.clientX, event.clientY).find(el => el !== pet && el !== petCanvas);
    return Boolean(under && trashIcon()?.contains(under));
}

// Only this drop plays the rock's grumble, not a reload or a restore.
function throwRockAway() {
    hideRock();
    playSound(pet.dataset.trashedSound);
    trashed.set(rockKey, pet);
    saveTrash();
}

// Put back, the rock lands on the floor under where it went in, clear of
// the windows, and walks on as after a drop.
function putRockBack() {
    [pet, petCanvas].forEach(el => el.classList.remove("in-trash"));
    petCanvas.style.display = "none";
    pet.style.display = "block";
    pet.style.top = "";
    pet.style.bottom = "-9px";
    pet.style.left = `${petLandingLeft(parseFloat(getComputedStyle(pet).left) || 0)}px`;
    pet.classList.add("walking");
    resumePetWalking(true);
}

// The can's picture alone shows whether it is full.
function showTrash() {
    trashIcon().querySelector(".appicon").src = trashed.size ? appsIcons.trashFull : appsIcons.trash;
}

// peelOut is true when the banana peel just came out, false when it just
// went in, and left out when it did not move.
function saveTrash(peelOut) {
    showTrash();
    const icons = [...trashed.keys()];
    if (!signedIn) {
        try {
            localStorage.setItem(trashStore, JSON.stringify(icons));
            if (peelOut === true) localStorage.setItem(peelOutStore, "1");
            if (peelOut === false) localStorage.removeItem(peelOutStore);
        } catch {
            // Storage blocked: the trash lasts until the page closes.
        }
        return;
    }
    const token = document.querySelector("meta[name='csrf-token']")?.content;
    fetch("/trash", {
        method: "PATCH", body: JSON.stringify(peelOut === undefined ? { icons } : { icons, banana_peel_out: peelOut }),
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
    }).catch(() => {
        // Offline: this page still shows the trash as it is.
    });
}

// Whether the pointer lets go over the can, and the can is not on the move.
function overTrash(event, moving) {
    const can = trashIcon();
    if (!can?.isConnected || moving.includes(can)) return false;
    const box = can.getBoundingClientRect();
    return event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom;
}

// Every icon keeps its cell first, so none moves up into the space left.
function throwAway(icons) {
    saveIcons();
    const put = icons.filter(icon => !icon.dataset.pet && !keptOut(icon));
    put.forEach(icon => {
        icon.classList.remove("selected");
        icon.remove();
        trashed.set(icon.dataset.key, icon);
        // Its window, if one is open, goes with it, as its X would close it.
        const win = document.getElementById(icon.dataset.key === "welcome.txt" ? "welcome" : `window-${icon.dataset.key.replace(/\s+/g, "-")}`);
        if (win && getComputedStyle(win).display !== "none") win.querySelector(".windowclose").click();
    });
    if (put.length) saveTrash(put.some(icon => icon.dataset.key === bananaPeelKey) ? false : undefined);
    icons.filter(icon => icon.dataset.pet).forEach(icon => {
        icon.classList.remove("selected");
        icon.remove();
        deleteQueue.push({ id: Number(icon.dataset.pet), icon });
    });
    nextDelete();
}

function restore(keys) {
    keys.forEach(key => {
        if (key === rockKey) putRockBack();
        else putBackIcon(trashed.get(key));
        trashed.delete(key);
    });
    saveTrash(keys.includes(bananaPeelKey) ? true : undefined);
    arrangeIcons();
}

// The menu lists what is in the trash, each to put back, and all at once
// when there are several. It opens at the pointer, or under the can.
function openTrashMenu(at) {
    const items = [...trashed].map(([key, icon]) => [`restore ${trashName(icon)}`, [key]]);
    if (items.length > 1) items.push(["restore all", [...trashed.keys()]]);
    const can = trashIcon().getBoundingClientRect();
    openMenu(trashMenu, items.length ? items.map(([text, keys]) => menuItem(text, () => {
        restore(keys);
        trashIcon().focus();
    })) : [Object.assign(document.createElement("p"), { textContent: "the trash is empty" })], at ?? [can.left + 16, can.bottom - 16]);
}

// One pet's delete popups at a time. The frame's page opens them at once,
// and tells the desktop how they ended.
function nextDelete() {
    if (deleting || !deleteQueue.length) return;
    deleting = deleteQueue.shift();
    deleteFrame.src = `/projects/${deleting.id}/trash`;
    deleteFrame.hidden = false;
}

deleteFrame.addEventListener("load", () => {
    if (!deleting) return;
    try {
        if (!deleteFrame.contentDocument.querySelector("[data-controller~='delete-confirm']")) return endDelete("kept");
    } catch {
        return endDelete("kept");
    }
    deleteFrame.focus();
});

window.addEventListener("message", event => {
    if (event.origin !== location.origin || event.source !== deleteFrame.contentWindow || event.data?.type !== "playground:trash") return;
    if (deleting && event.data.project === deleting.id) endDelete(event.data.action);
});

// ship.exe's list goes by the pets too, so it reloads. The focus goes back
// to the pet's icon, or to the can when the pet is gone.
function endDelete(action) {
    const { id, icon } = deleting;
    deleting = null;
    deleteFrame.hidden = true;
    deleteFrame.src = "about:blank";
    if (action === "deleted") {
        forgetPet(id);
        document.querySelector("#window-goal\\.exe iframe")?.contentWindow.location.reload();
        trashIcon().focus();
    } else if (petIcons.get(id) === icon) {
        putBackIcon(icon);
        arrangeIcons();
        icon.focus();
    }
    nextDelete();
}

// playground: every other icon has a menu too, at the pointer on a right
// click or a long press, and by the icon from the menu key or Shift+F10. It
// is for that icon alone, which it selects, as the can's is. "open" does
// what a click does. "rename" is only on the participant's own pets.
// "move to trash" is only where a drag into the trash takes the icon, and
// does what that drop does (see throwAway): a pet asks with its delete
// popups, and the sponsor's credit never goes in.
const iconMenu = Object.assign(document.createElement("div"), { id: "icon-menu", hidden: true });
iconMenu.setAttribute("role", "menu");
document.body.appendChild(iconMenu);
let menuIcon = null;

function openIconMenu(icon, at) {
    selectIcons([icon]);
    if (icon === trashIcon()) return openTrashMenu(at);
    menuIcon = icon;
    iconMenu.setAttribute("aria-label", icon.querySelector("p").textContent);
    const items = [menuItem("open", () => {
        icon.click();
        icon.focus();
    })];
    if (icon.dataset.pet) items.push(menuItem("rename", () => renamePet(icon)));
    if (!keptOut(icon)) {
        items.push(menuItem("move to trash", () => {
            throwAway([icon]);
            trashIcon().focus();
        }));
    }
    const box = icon.getBoundingClientRect();
    openMenu(iconMenu, items, at ?? [box.left + 16, box.bottom - 16]);
}

// A pet's label turns into a field holding its name, all of it selected.
// Enter or a press elsewhere saves the name, and Escape keeps the old one.
// Either way the focus goes back to the icon.
function renamePet(icon) {
    const label = icon.querySelector("p");
    const field = Object.assign(document.createElement("input"), {
        type: "text", className: "rename", value: label.textContent, maxLength: 80, spellcheck: false, enterKeyHint: "done"
    });
    field.setAttribute("aria-label", "name");
    icon.classList.add("renaming");
    label.after(field);
    field.focus();
    field.select();
    let done = false;
    const finish = save => {
        if (done) return;
        done = true;
        field.remove();
        icon.classList.remove("renaming");
        if (save && field.value !== label.textContent) savePetName(icon, field.value);
    };
    field.addEventListener("keydown", event => {
        if ((event.key !== "Enter" && event.key !== "Escape") || event.isComposing) return;
        event.preventDefault();
        finish(event.key === "Enter");
        icon.focus();
    });
    field.addEventListener("blur", () => finish(true));
}

// The name saves as the edit page saves it, and the label shows it at once.
// Once it is in, the desktop asks for the pets again, and the pet's window,
// its ship window, and ship.exe's list follow (see syncPets). The pet's own
// page reloads in its window, but not its edit page, where a reload would
// lose what was typed. A name the edit page would refuse, or no answer,
// puts the old name back, with the reason beside the label.
async function savePetName(icon, name) {
    const id = Number(icon.dataset.pet);
    const label = icon.querySelector("p");
    setLabel(label, name);
    fitLabelWords(label);
    const token = document.querySelector("meta[name='csrf-token']")?.content;
    const response = await fetch(`/projects/${id}`, {
        method: "PATCH", body: JSON.stringify({ project: { name } }),
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
    }).catch(() => null);
    if (response?.ok) {
        const view = document.querySelector(`#window-pet-${id} iframe`)?.contentWindow;
        if (view?.location.pathname === `/projects/${id}`) view.location.reload();
        refreshPets();
        return;
    }
    const answer = await response?.json().catch(() => null);
    if (!icon.isConnected) return;
    setLabel(label, icon.dataset.name);
    fitLabelWords(label);
    showRenameError(icon, answer?.error ?? "could not save the name. try again.");
}

// The reason lies beside the label, to its right, or to its left where the
// screen has no room, in the menus' look, until the next press or focus
// anywhere, or Escape.
const renameError = Object.assign(document.createElement("div"), { id: "rename-error", hidden: true });
renameError.setAttribute("role", "alert");
document.body.appendChild(renameError);

function showRenameError(icon, text) {
    closeMenus();
    renameError.replaceChildren(Object.assign(document.createElement("p"), { textContent: text }));
    const label = icon.querySelector("p").getBoundingClientRect();
    showInView(renameError, [label.right + 8, label.top - 4]);
    const width = renameError.getBoundingClientRect().width;
    if (label.right + 8 + width > document.documentElement.clientWidth) showInView(renameError, [label.left - 8 - width, label.top - 4]);
}

// The desktop's menus, the can's and every other icon's, and a rename's
// reason, which closes as they do.
const desktopMenus = [trashMenu, iconMenu, renameError];

function closeMenus() {
    desktopMenus.forEach(menu => { menu.hidden = true; });
}

// A menu's item closes the menu first, then does its job.
function menuItem(text, choose) {
    const item = Object.assign(document.createElement("button"), { type: "button", textContent: text });
    item.setAttribute("role", "menuitem");
    item.addEventListener("click", () => {
        closeMenus();
        choose();
    });
    return item;
}

// One menu shows at a time, with the focus on its first item.
function openMenu(menu, items, at) {
    closeMenus();
    menu.replaceChildren(...items);
    showInView(menu, at);
    menu.querySelector("button")?.focus();
}

// A menu lies at (x, y), or as near as it fits whole inside the screen and
// above the taskbar. It measures at the left edge, where it has the whole
// width to fill.
function showInView(menu, [x, y]) {
    menu.style.left = "0px";
    menu.hidden = false;
    const root = document.documentElement;
    // Its size rounded up, so at the right edge no line wraps for want of a
    // fraction of a pixel.
    const size = menu.getBoundingClientRect();
    menu.style.left = Math.max(0, Math.min(x, root.clientWidth - Math.ceil(size.width))) + "px";
    menu.style.top = Math.max(0, Math.min(y, desktopBottom() - Math.ceil(size.height))) + "px";
}

// A press or a focus outside a menu, Escape, or a resize closes it, and so
// does a window come to the front, as one opens or takes a press. A press
// or a focus inside a window's frame reaches the desktop only as its own
// window losing focus, so that closes it too. The arrow keys move between
// its items, and Escape gives the focus back to its icon. A right click on
// a menu, or a key's contextmenu that lands on it, shows no other menu.
document.addEventListener("pointerdown", event => {
    desktopMenus.forEach(menu => { if (!menu.hidden && !menu.contains(event.target)) menu.hidden = true; });
}, true);
document.addEventListener("focusin", event => {
    desktopMenus.forEach(menu => { if (!menu.hidden && !menu.contains(event.target)) menu.hidden = true; });
});
window.addEventListener("resize", closeMenus);
window.addEventListener("blur", closeMenus);
document.addEventListener("playground:window-front", closeMenus);
desktopMenus.forEach(menu => menu.addEventListener("contextmenu", event => event.preventDefault()));
document.addEventListener("keydown", event => {
    if (event.key === "Escape") renameError.hidden = true;
    const menu = [trashMenu, iconMenu].find(menu => !menu.hidden);
    if (!menu) return;
    const items = [...menu.querySelectorAll("button")];
    const at = items.indexOf(document.activeElement);
    if (event.key === "Escape") {
        closeMenus();
        (menu === trashMenu ? trashIcon() : menuIcon).focus();
    } else if ((event.key === "ArrowDown" || event.key === "ArrowUp") && items.length) {
        event.preventDefault();
        event.stopPropagation();
        items[(at + (event.key === "ArrowDown" ? 1 : items.length - 1)) % items.length].focus();
    }
}, true);

// playground: each desktop window has one job, and each page of the site
// belongs to one window (app/services/desktop_windows.rb lists them).
// ship.exe shows the dashboard, login.exe the login, a pet's window its page
// and its edit page, and a ship window its checks. A link, a save, or a
// redirect that would load another window's page in a window's frame opens
// or raises that window on the page instead. After a link the frame stays where it is, and after a
// save or a redirect it goes back to its own page.
const windowPages = JSON.parse(appsContainer.dataset.windowPages || "[]").map(({ kind, path }) => ({
    kind,
    pattern: new RegExp("^" + path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/:id\b/g, "(\\d+)").replace(/:\w+/g, "[^/]+") + "$")
}));

// The kinds of window: which windows are of the kind, the page one goes back
// to when a save sends its page elsewhere, and how one opens on a page. A
// kind with no page to go back to closes instead. A new kind, such as a
// redeem window, is one more entry here and its pages in the table on the
// server.
const windowKinds = {
    goal: {
        owns: win => win.id === "window-goal.exe",
        home: () => "/dashboard",
        open: page => openAppAt("ship.exe", page.url)
    },
    // Signed out, a page behind the login lands on the login's page, so the
    // login opens with the message that says why.
    login: {
        owns: win => win.id === "window-login.exe",
        home: () => "/login",
        open: page => openAppAt("login.exe", page.url)
    },
    pet: {
        owns: win => win.classList.contains("pet-window"),
        idOf: win => Number(win.id.replace("window-pet-", "")),
        home: id => `/projects/${id}`,
        open: page => openPetWindowSoon(page.id, page.url)
    },
    ship: {
        owns: win => win.classList.contains("ship-window"),
        idOf: win => Number(win.id.replace("window-ship-", "")),
        home: id => `/projects/${id}/checks?window=1`,
        open: (page, frame) => openShipWindow(frame, page.id, petIcons.get(page.id)?.querySelector("p").textContent ?? "")
    },
    guide: {
        owns: win => win.id === "window-guide.txt",
        home: () => "/guide",
        open: page => openAppAt("guide.txt", page.url)
    },
    requirements: {
        owns: win => win.id === "window-requirements.txt",
        home: () => "/requirements",
        open: page => openAppAt("requirements.txt", page.url)
    },
    // A redeem window has no page to go back to, so a redeem or a cancel
    // closes it.
    redeem: {
        owns: win => win.classList.contains("redeem-window"),
        open: page => openRedeemWindow(page.url)
    }
};

// The window a URL's page belongs in, and the pet it is for, if any. A page
// of another site, or one no window shows, belongs nowhere.
function pageOf(url) {
    const page = new URL(url, location.href);
    if (page.origin !== location.origin) return null;
    for (const { kind, pattern } of windowPages) {
        const match = page.pathname.match(pattern);
        if (match) return { kind, id: match[1] ? Number(match[1]) : null, url: page.pathname + page.search };
    }
    return null;
}

// The kind of window a frame sits in, and the pet it is for, if any.
function frameOwner(frame) {
    const win = frame.closest(".window");
    const kind = win && Object.keys(windowKinds).find(name => windowKinds[name].owns(win));
    return kind ? { kind, id: windowKinds[kind].idOf?.(win) ?? null } : null;
}

const belongsIn = (page, owner) => page.kind === owner.kind && (page.id == null || page.id === owner.id);

function setUpRouting() {
    document.addEventListener("load", event => {
        const frame = event.target;
        if (frame.tagName !== "IFRAME" || !frame.closest(".window")) return;
        try {
            routeFrame(frame);
        } catch {
            // A page from another origin keeps its events to itself.
        }
    }, true);
}

// Turbo announces each visit, a link's or a save's, before it happens, so
// the page never shows in the wrong window. A page that lands anyway, by a
// link that redirects, the back button, or a full load, is sent on once it
// shows.
function routeFrame(frame) {
    const owner = frameOwner(frame);
    if (!owner) return;
    const view = frame.contentWindow;
    let saving = false;
    view.document.addEventListener("turbo:submit-start", () => { saving = true; });
    view.document.addEventListener("turbo:submit-end", event => {
        const response = event.detail.fetchResponse;
        saving = !!response?.redirected;
        const page = saving && pageOf(response.location.href);
        if (page && !belongsIn(page, owner)) {
            carryMessages(page, response.responseHTML.then(html => messagesIn(new DOMParser().parseFromString(html ?? "", "text/html"))));
        }
    });
    view.document.addEventListener("turbo:before-visit", event => {
        const page = pageOf(event.detail.url);
        const saved = saving;
        saving = false;
        if (!page || belongsIn(page, owner)) return;
        event.preventDefault();
        windowKinds[page.kind].open(page, frame);
        // A window with no page to go back to closes on any way out.
        if (saved || !windowKinds[owner.kind].home) goHome(frame, owner);
    });
    view.document.addEventListener("turbo:load", () => landed(frame, owner));
    // A link to the desktop with ship.exe open, as the guide's ship link,
    // opens ship.exe here, instead of loading the desktop again.
    view.document.addEventListener("click", event => {
        const link = event.target.closest?.("a[href]");
        const url = link && new URL(link.href, view.location.href);
        if (!url || url.origin !== location.origin || url.pathname !== "/" || !["goal", "ship"].includes(url.searchParams.get("open"))) return;
        event.preventDefault();
        openWindowByTitle("ship.exe");
    });
    landed(frame, owner);
}

function landed(frame, owner) {
    const page = pageOf(frame.contentWindow.location.href);
    if (!page || belongsIn(page, owner)) {
        delete frame.dataset.sentHome;
        if (page) {
            // The window's page, for a reload (see saveWindowState).
            frame.closest(".window").dataset.page = page.url;
            showCarried(frame);
        }
        return;
    }
    carryMessages(page, messagesIn(frame.contentDocument));
    windowKinds[page.kind].open(page, frame);
    goHome(frame, owner);
}

// A notice or an alert comes on the page a redirect lands on, such as "you
// need 3 approved hours" on the dashboard. The frame that followed the
// redirect used it up, and the window the page belongs in loads the page
// afresh, without it. So the desktop carries the messages over, and they
// show at the top of that page when it next loads in its window. They are
// the site's own text, and go in as text. Messages no window shows within
// half a minute are dropped.
const carried = [];

function carryMessages(page, messages) {
    carried.push({ path: new URL(page.url, location.href).pathname, messages, until: Date.now() + 30000 });
}

function messagesIn(doc) {
    return [...doc.querySelectorAll("body > .flash")].map(flash => ({ alert: flash.classList.contains("alert"), text: flash.textContent }));
}

function showCarried(frame) {
    const doc = frame.contentDocument;
    const path = frame.contentWindow.location.pathname;
    const now = Date.now();
    const due = carried.filter(entry => entry.path === path && entry.until > now);
    carried.splice(0, carried.length, ...carried.filter(entry => entry.path !== path && entry.until > now));
    if (!due.length) return;
    Promise.all(due.map(entry => entry.messages)).then(lists => {
        if (frame.contentDocument !== doc) return;
        // A message carried twice, as when a window's own page sends it away
        // again before the first load ends, shows once.
        const shown = new Set(messagesIn(doc).map(message => message.text));
        const fresh = [];
        lists.flat().forEach(message => {
            if (shown.has(message.text)) return;
            shown.add(message.text);
            fresh.push(message);
        });
        doc.body.prepend(...fresh.map(({ alert, text }) =>
            Object.assign(doc.createElement("p"), { className: `flash ${alert ? "alert" : "notice"}`, textContent: text })));
    });
}

// A pet deleted in a window takes its windows with it, so the desktop asks
// for the pets again before a frame goes back. A window whose own page sends
// it elsewhere again, as when signed out, goes, so it never goes round, and
// opens fresh next time.
function goHome(frame, owner) {
    const win = frame.closest(".window");
    const home = windowKinds[owner.kind].home?.(owner.id);
    if (frame.dataset.sentHome) return win.remove();
    if (!home) return win.querySelector(".windowclose").click();
    refreshPets().then(() => {
        if (!frame.isConnected) return;
        frame.dataset.sentHome = "1";
        frame.contentWindow.location.replace(home);
    });
}

// ship.exe, login.exe, or guide.txt opens on the page, or raises with it.
// A visitor's ship.exe opens the login instead, on its own page.
function openAppAt(title, url) {
    const frame = document.getElementById(appWindowId(apps.find(app => app.title === title)))?.querySelector("iframe");
    openWindowByTitle(title, { page: url });
    if (frame) frame.contentWindow.location.replace(url);
}

markDesktopTop();
setUpRouting();
setUpPets();
setUpTrashContents();
fitSavedIcons();
arrangeIcons();
// The rock's picture sets the floor it walks on, which the layout keeps clear.
if (pet && !pet.complete) pet.addEventListener("load", arrangeIcons, { once: true });
// The labels' font sets how wide their words run (see fitLabelWords).
document.fonts?.ready.then(arrangeIcons);
window.addEventListener("resize", () => {
    markDesktopTop();
    document.querySelectorAll(".window").forEach(keepInView);
    if (pet) petKeepInView();
    arrangeIcons();
});

dragElement(document.getElementById("welcome"));
raiseOnPress(document.getElementById("welcome"));
closeOnButton(document.getElementById("welcome"));
// welcome.txt's window comes with the page, and its entry in apps says
// whether it resizes, as for the other windows.
if (apps.find(app => app.title === "welcome.txt").resizable !== false) resizeOnFrame(document.getElementById("welcome"));
sizeWelcome(document.getElementById("welcome"));
placeWindow(document.getElementById("welcome"), { atLoad: true });
keepInView(document.getElementById("welcome"));

// playground: after login or linking Hackatime, Rails redirects to
// /?open=goal. froppii's ?open=ship still works.
const openedGoal = ["goal", "ship"].includes(new URLSearchParams(location.search).get("open"));
if (openedGoal) {
    openWindowByTitle("ship.exe", { atLoad: true });
    history.replaceState(null, "", location.pathname);
}

// playground: froppii's drag by the header, now by mouse, pen, or touch.
// The window follows the pointer as far as headerInReach lets it, and
// catches up when the pointer comes back.
function dragElement(elmnt) {
    var grabX = 0, grabY = 0, pointer = null;
    document.getElementById(elmnt.id + "header").onpointerdown = dragMouseDown;

    function dragMouseDown(e) {
        if (!e.isPrimary || e.button !== 0) return;
        e.preventDefault();
        pointer = e.pointerId;
        grabX = e.clientX - elmnt.offsetLeft;
        grabY = e.clientY - elmnt.offsetTop;
        document.body.classList.add("dragging"); // playground: see landing.css
        document.onpointerup = closeDragElement;
        document.onpointercancel = closeDragElement;
        document.onpointermove = elementDrag;
    }

    function elementDrag(e) {
        if (e.pointerId !== pointer) return;
        e.preventDefault();
        const [left, top] = headerInReach(elmnt, e.clientX - grabX, e.clientY - grabY);
        elmnt.style.top = top + "px";
        elmnt.style.left = left + "px";
        clipAtTaskbar(elmnt);
    }

    function closeDragElement(e) {
        if (e.pointerId !== pointer) return;
        document.body.classList.remove("dragging");
        document.onpointerup = null;
        document.onpointercancel = null;
        document.onpointermove = null;
        savePlace(elmnt); // playground: it reopens here
    }
}

// playground: a pet page's ship button, in ship.exe's frame or the pet's own
// window, asks the desktop for that pet's ship window with a message, and
// the desktop takes messages only from this site's own frames. Each pet has
// one ship window. It holds the pet's ship list in a frame, as ship.exe holds
// the dashboard, and drags, raises, closes, resizes, and stays in view like
// the other windows.
// The list reports each save, and the pet page that asked reloads when the
// window closes after a change, or at once when the pet ships.
const shipWindows = new WeakMap();
window.addEventListener("message", shipWindowMessage);

function shipWindowMessage(event) {
    if (event.origin !== location.origin || event.data?.type !== "playground:ship") return;
    const frame = [...document.querySelectorAll(".window iframe")].find(frame => frame.contentWindow === event.source);
    if (!frame) return;
    if (event.data.action === "open") {
        openShipWindow(frame, event.data.project, String(event.data.name ?? ""));
        return;
    }
    const win = frame.closest(".ship-window");
    const state = win && shipWindows.get(win);
    if (!state) return;
    if (event.data.action === "saving") state.pending++;
    if (event.data.action === "saved") state.pending = Math.max(0, state.pending - 1);
    if (["saved", "changed", "shipped"].includes(event.data.action) && event.data.ok !== false) state.changed = true;
    if (event.data.action === "shipped") win.style.display = "none";
    reloadShipOpener(win);
}

function openShipWindow(opener, project, name, { atLoad = false } = {}) {
    if (!Number.isInteger(project) || project <= 0) return;
    const id = `window-ship-${project}`;
    let win = document.getElementById(id);
    if (!win) {
        win = document.createElement("div");
        win.className = "window ship-window";
        win.id = id;
        win.style.display = "none";
        win.innerHTML = `
            <div class="windowheader" id="${id}header">
                <h1 class="headertext"></h1>
                <button type="button" class="windowclose" aria-label="close">X</button>
            </div>
            <div class="windowcontent">
                <iframe class="ship-window-frame"></iframe>
            </div>
        `;
        document.body.appendChild(win);
        dragElement(win);
        raiseOnPress(win);
        closeOnButton(win);
        resizeOnFrame(win);
        fitToFrame(win);
        win.querySelector(".windowclose").addEventListener("click", () => closeShipWindow(win));
        shipWindows.set(win, { pending: 0, changed: false });
        placeOnceFitted(win, atLoad);
    }
    const state = shipWindows.get(win);
    const frame = win.querySelector("iframe");
    state.opener = opener;
    // The pet's name is the participant's own text, so it goes in as text.
    win.querySelector(".headertext").textContent = frame.title = `${name}.ship`;
    if (win.style.display === "none") {
        // A closed window opens on a fresh list. On a phone it opens a step
        // down and right of the window that asked, and of each other ship
        // window open. Elsewhere it opens where it was left, or where
        // placeOnceFitted puts it the first time. One the page reopens may
        // have no window that asked, and steps from the top left.
        const open = [...document.querySelectorAll(".ship-window")].filter(other => other !== win && other.style.display !== "none");
        const from = opener?.closest(".window")?.getBoundingClientRect() ?? { left: 0, top: 0 };
        const step = 40 + 30 * open.length;
        frame.src = `/projects/${project}/checks?window=1`;
        state.pending = 0;
        win.style.display = "flex";
        if (!win.style.left || fillsWidth(win)) {
            win.style.left = from.left + step + "px";
            win.style.top = from.top + step + "px";
        }
    }
    keepInView(win);
    bringToFront(win);
}

// The X hides the window, and the list lets go of a field still being typed
// in, so its change saves before the pet page reloads.
function closeShipWindow(win) {
    win.querySelector("iframe").contentWindow.postMessage({ type: "playground:ship", action: "close" }, location.origin);
    reloadShipOpener(win);
}

function reloadShipOpener(win) {
    const state = shipWindows.get(win);
    if (win.style.display !== "none" || !state.changed || state.pending > 0) return;
    state.changed = false;
    if (state.opener?.isConnected) state.opener.contentWindow.location.reload();
}

// playground: a window holding a frame, ship.exe, a pet's window, or a ship
// window, is as tall as the page in its frame, and follows it as the frame
// moves to another page or the page changes. Past what the screen can hold
// below the credits, it stops, and the page scrolls inside it. A window sized
// by hand keeps its size, but never grows taller than its page. The frame's
// pages come from this site, so the desktop can measure them.
function fitToFrame(win) {
    const frame = win.querySelector("iframe");
    frame.addEventListener("load", () => {
        let view;
        try {
            view = frame.contentWindow;
            if (!view.document.body) return;
        } catch {
            return;
        }
        // One measure per frame drawn, after the page has settled.
        const fit = () => view.requestAnimationFrame(() => fitFrame(win));
        const watch = new view.ResizeObserver(fit);
        // Turbo swaps the page's body on each visit, so the watch moves to the new one.
        const follow = () => {
            watch.disconnect();
            watch.observe(view.document.body);
            fit();
        };
        view.addEventListener("turbo:load", follow);
        follow();
    });
}

function fitFrame(win) {
    const frame = win.querySelector("iframe");
    const page = framePageHeight(frame);
    if (page == null || getComputedStyle(win).display === "none") return;
    const chrome = win.offsetHeight - frame.offsetHeight;
    if (win.classList.contains("resized")) {
        if (win.offsetHeight > chrome + page) win.style.height = chrome + page + "px";
        // A new page that can use less width takes the window in, from the right.
        const widest = widestWidth(win);
        if (win.offsetWidth > widest) win.style.width = widest + "px";
        return;
    }
    const room = desktopBottom() - desktopTop();
    const most = Math.min(parseFloat(getComputedStyle(win).maxHeight), room) - chrome;
    frame.style.setProperty("--page-height", Math.max(0, Math.min(page, most)) + "px");
    if (frameLoaded(frame)) finishPlacing(win);
    keepInView(win);
}

// Whether a frame shows its page yet, and not the blank one it starts on.
function frameLoaded(frame) {
    try {
        const page = frame.contentDocument;
        return !!page && page.URL !== "about:blank" && page.readyState !== "loading";
    } catch {
        return false;
    }
}

// The height of the page in a frame, or null while it can't be measured.
function framePageHeight(frame) {
    try {
        const body = frame.contentDocument?.body;
        return body ? Math.ceil(body.getBoundingClientRect().height) : null;
    } catch {
        return null;
    }
}

// The height a window's content asks for: its frame's page, or its own
// content, plus the header and the frame around it.
function contentHeight(win) {
    const frame = win.querySelector("iframe");
    const page = frame && framePageHeight(frame);
    if (page != null) return win.offsetHeight - frame.offsetHeight + page;
    const content = win.querySelector(".windowcontent");
    return win.offsetHeight - content.clientHeight + content.scrollHeight;
}

window.addEventListener("resize", () => {
    document.querySelectorAll(".window").forEach(win => { if (win.querySelector("iframe")) fitFrame(win); });
});

// playground: where a window opens. It reopens where it was last left in
// this browser, moved or resized, if that spot still fits the screen. The
// first time, it opens where it covers the least of the icons and the other
// open windows, nearest the top, then nearest the right, away from the icons,
// inside the screen and below the credits. When every spot covers more than a sliver, it cascades
// 30px down and right of the last window placed. When that would leave the
// screen, the cascade starts again at the top left of the desktop the icons
// leave clear. A window that opens with the page never covers the
// sponsor's icon, which must show, nor, where the text row of the required
// links is hidden, Hack Club's four link icons (see keptInSight). Too tall
// to open clear of them, it stops above them (see loadSpot). A window
// opened by a click whose free spot covers some icon, and a cascaded one
// that would run down over icons, stop above the icons too when that leaves
// them clear of every icon (see openSpot and cascadeClear).
// welcome.txt's first time is its own: below the logo (see welcomeSpot).
// login.exe opening with the page goes beside welcome.txt (see
// besideWelcomeSpot). On a phone, where windows fill the width, windows
// open as they always did, but for welcome.txt and login.exe opening with
// the page, which open below the logo (see phoneSpot).
// welcome.txt is placed while the page loads, before this point runs, so
// the state here is hoisted: a function for the store's key, and a var.
function placesStore() {
    return "playground-window-places";
}
var lastPlaced; // no initializer: it would undo the placing done during load

function fillsWidth(win) {
    return win.offsetWidth >= document.documentElement.clientWidth - 40;
}

function placeWindow(win, { atLoad = false } = {}) {
    if (fillsWidth(win)) {
        if (atLoad) phoneSpot(win);
        return;
    }
    const spot = restoredSpot(win, atLoad) ?? savedSpot(win, atLoad) ??
        (atLoad ? welcomeSpot(win) ?? besideWelcomeSpot(win) ?? loadSpot(win) : openSpot(win)) ?? cascadeClear(win, cascadeSpot(win));
    win.style.left = spot.left + "px";
    win.style.top = spot.top + "px";
    lastPlaced = win;
}

// A window with a frame waits, unseen, for its page, so it is placed at the
// height it fits (see fitFrame). A page that never loads places it anyway.
function placeOnceFitted(win, atLoad = false) {
    win.dataset.placing = atLoad ? "load" : "open";
    win.style.visibility = "hidden";
    setTimeout(() => finishPlacing(win), 2000);
}

function finishPlacing(win) {
    if (!win.dataset.placing) return;
    const atLoad = win.dataset.placing === "load";
    delete win.dataset.placing;
    win.style.visibility = "";
    placeWindow(win, { atLoad });
    keepInView(win);
}

function loadPlaces() {
    try {
        const places = JSON.parse(localStorage.getItem(placesStore()));
        return places && typeof places === "object" ? places : {};
    } catch {
        return {};
    }
}

function savePlace(win) {
    if (fillsWidth(win)) return;
    const places = loadPlaces();
    places[win.id] = { left: win.offsetLeft, top: win.offsetTop };
    if (win.classList.contains("resized")) Object.assign(places[win.id], { width: win.offsetWidth, height: win.offsetHeight });
    try {
        localStorage.setItem(placesStore(), JSON.stringify(places));
    } catch {
        // Private windows and full storage keep nothing, and windows open anew.
    }
}

// The saved spot, and size if it was resized, when the window fits there
// whole: inside the screen, below the credits, and above the taskbar, and
// clear of the icons kept in sight when it opens with the page. A spot that runs
// under the taskbar moves up, and a saved height taller than the desktop
// shrinks to it. A reload's spot for the window is checked the same way
// (see restoredSpot).
function savedSpot(win, atLoad, place = loadPlaces()[win.id]) {
    if (!place || ![place.left, place.top].every(Number.isFinite)) return null;
    const sized = [place.width, place.height].every(Number.isFinite);
    // A saved width past what the content can use shrinks to it, from the right.
    const width = sized ? Math.min(place.width, widestWidth(win)) : win.offsetWidth;
    const bottom = desktopBottom();
    const height = sized ? Math.min(place.height, bottom - desktopTop()) : win.offsetHeight;
    const box = { left: place.left, top: place.top > bottom - height ? bottom - height : place.top, width, height };
    const root = document.documentElement;
    const fits = box.left >= 0 && box.top >= desktopTop() && box.left + box.width <= root.clientWidth && box.top + box.height <= bottom;
    if (!fits || (atLoad && keptInSight().some(icon => overlapArea(box, icon) > 0))) return null;
    if (sized) {
        Object.assign(win.style, { width: width + "px", height: height + "px" });
        win.classList.add("resized");
    }
    return { left: box.left, top: box.top };
}

// The spot, on a 10px grid, that covers the least of the icons, their drawn
// pictures (see drawnBox) and their labels, and of the open windows, or of
// the icons alone. More than 2% of the window covered counts as nothing
// free, except for a window that opens with the page, which takes the best
// spot clear of the icons kept in sight. login.exe opening with the page
// keeps clear of every icon too, where any spot is, and then of the logo
// and its line: short, it would otherwise lie on the icons rather than over
// welcome.txt. With clearOfIcons, only spots that cover no icon at all
// count. The spot says how much of the icons it covers.
function freeSpot(win, { atLoad = false, iconsOnly = false, clearOfIcons = false } = {}) {
    const root = document.documentElement;
    const margin = 10;
    const width = win.offsetWidth, height = win.offsetHeight;
    const icons = iconBoxes();
    const windows = iconsOnly ? [] : [...document.querySelectorAll(".window")]
        .filter(other => other !== win && getComputedStyle(other).display !== "none" && other.style.visibility !== "hidden")
        .map(other => other.getBoundingClientRect());
    const kept = keptInSight();
    const login = atLoad && win.id === "window-login.exe";
    const logo = login ? logoBoxes() : [];
    const steps = (from, to) => {
        if (to <= from) return [from];
        const values = [];
        for (let value = from; value < to; value += 10) values.push(value);
        return values.concat(to);
    };
    let best = null;
    for (const top of steps(desktopTop(), desktopBottom() - height)) {
        // A cascade's start, over the icons only, goes left, so it has room to step right.
        const lefts = steps(margin, root.clientWidth - margin - width);
        for (const left of iconsOnly ? lefts : lefts.reverse()) {
            const box = { left, top, width, height };
            // The sponsor's credit and the required links must show: any of
            // them covered weighs 50 times.
            const onKept = kept.reduce((sum, icon) => sum + overlapArea(box, icon), 0);
            if (atLoad && onKept > 0) continue;
            const onIcons = icons.reduce((sum, icon) => sum + overlapArea(box, icon), 0);
            if (clearOfIcons && onIcons > 0) continue;
            const covered = windows.reduce((sum, other) => sum + overlapArea(box, other), onIcons + 50 * onKept);
            const rank = login ? (onIcons > 0 ? 2 : 0) + (logo.some(part => overlapArea(box, part) > 0) ? 1 : 0) : 0;
            if (!best || (rank !== best.rank ? rank < best.rank : covered < best.covered)) best = { left, top, covered, onIcons, rank };
        }
    }
    if (!best || (!atLoad && best.covered > 0.02 * width * height)) return null;
    return best;
}

// What each icon on the desktop draws: its picture and its label.
function iconBoxes() {
    return [...appsContainer.querySelectorAll(".app")].filter(icon => icon.offsetParent)
        .flatMap(icon => [drawnBox(icon), icon.querySelector("p").getBoundingClientRect()])
        .map(box => ({ left: box.left, top: box.top, width: box.right - box.left, height: box.bottom - box.top }));
}

// welcome.txt, the first time, opens 12px below the logo's line, where
// desktopPlan puts it, at the size sizeWelcome gave it,
// as long as it fits there whole, 10px above the taskbar, and covers no
// icon. Anywhere else it opens at its own smaller size.
function welcomeSpot(win) {
    const spot = win.id === "welcome" && desktopPlan()?.welcome;
    if (!spot) return null;
    sizeWelcome(win);
    const box = { left: spot.left, top: spot.top, width: win.offsetWidth, height: win.offsetHeight };
    if (box.top + box.height <= desktopBottom() - 10 && iconBoxes().every(icon => overlapArea(box, icon) === 0)) return box;
    sizeWelcome(win, false);
    return null;
}

// login.exe opens with the page beside welcome.txt, as two windows sit side
// by side: at its right, 10px off, and level with its top. welcome.txt keeps
// its place. Where the screen has no room there, login.exe slides left, over
// welcome.txt and in front of it, until it fits and covers no icon, the
// icons kept in sight, the logo, or its line. Too tall to fit there, it
// stops 10px above what lies below that line, as tall as leaves it such a
// spot, its page scrolling inside. With welcome.txt closed, it goes beside
// where welcome.txt opens. Where no spot on that line will do, even at
// 160px tall, it opens as other windows do.
function besideWelcomeSpot(win) {
    if (win.id !== "window-login.exe") return null;
    const welcome = document.getElementById("welcome");
    const beside = getComputedStyle(welcome).display !== "none" ? welcome.getBoundingClientRect() : desktopPlan()?.welcome;
    if (!beside) return null;
    const kept = [...iconBoxes(), ...keptInSight(), ...logoBoxes()];
    const slide = () => {
        const width = win.offsetWidth, height = win.offsetHeight;
        const top = Math.max(desktopTop(), Math.min(Math.round(beside.top), desktopBottom() - height));
        for (let left = Math.min(Math.round(beside.left + beside.width) + 10, document.documentElement.clientWidth - 10 - width); left >= 10; left -= 10) {
            const box = { left, top, width, height };
            if (kept.every(other => overlapArea(box, other) === 0)) return box;
        }
        return null;
    };
    const spot = slide();
    if (spot) return spot;
    const top = Math.max(desktopTop(), Math.round(beside.top));
    const caps = [...new Set(kept.filter(box => box.top > top).map(box => Math.floor(box.top - 10 - top)))]
        .filter(most => most >= 160 && most < win.offsetHeight).sort((a, b) => b - a);
    const before = win.style.getPropertyValue("--window-max-height");
    for (const most of caps) {
        capHeight(win, most + "px");
        const capped = slide();
        if (capped) return capped;
    }
    capHeight(win, before);
    return null;
}

// The logo and its line, which login.exe keeps clear of where it can.
function logoBoxes() {
    return [".background-logo", ".background-logo-text"].map(selector => document.querySelector(selector).getBoundingClientRect());
}

// On a phone welcome.txt and login.exe, opening with the page, open as wide
// as the screen, 12px below the logo's line, and no taller than they would
// be or the desktop below it, so the flag, the text row with the sponsor's
// name, the logo and its line all show. They may cover the icons below them
// until they close. login.exe lies in front.
function phoneSpot(win) {
    if (win.id !== "welcome" && win.id !== "window-login.exe") return;
    const top = Math.round(Math.max(logoBox().bottom + 12, desktopTop()));
    const room = Math.floor(desktopBottom() - 10 - top);
    if (room < 160) return;
    win.style.top = top + "px";
    if (room < win.offsetHeight) capHeight(win, room + "px");
}

// welcome.txt's opening size on a desktop (see desktopPlan), each time the
// page opens it, wherever it sits, unless the participant sized it. Its
// text runs far longer, so it takes the whole height, and scrolls inside.
function sizeWelcome(win, large = true) {
    const spot = large && !win.classList.contains("resized") && desktopPlan()?.welcome;
    win.style.width = spot ? spot.width + "px" : "";
    if (spot) win.style.setProperty("--window-max-height", spot.height + "px");
    else win.style.removeProperty("--window-max-height");
}

function cascadeSpot(win) {
    const root = document.documentElement;
    const margin = 10;
    const from = lastPlaced && lastPlaced !== win && getComputedStyle(lastPlaced).display !== "none" ? lastPlaced : null;
    if (from) {
        const spot = { left: from.offsetLeft + 30, top: from.offsetTop + 30 };
        if (spot.left + win.offsetWidth <= root.clientWidth - margin && spot.top + win.offsetHeight <= desktopBottom()) return spot;
    }
    // With no window to step from, or no room past it, the cascade starts
    // over. A window already at the start moves the start on a step, so no
    // window hides another exactly.
    const start = freeSpot(win, { iconsOnly: true }) ?? { left: margin, top: desktopTop() };
    const taken = [...document.querySelectorAll(".window")]
        .filter(other => other !== win && getComputedStyle(other).display !== "none")
        .map(other => `${other.offsetLeft},${other.offsetTop}`);
    let left = start.left, top = start.top;
    while (taken.includes(`${left},${top}`) && left + 30 + win.offsetWidth <= root.clientWidth - margin && top + 30 + win.offsetHeight <= desktopBottom()) {
        left += 30;
        top += 30;
    }
    return { left, top };
}

// The link icons a window that opens with the page leaves in sight: the
// sponsor's always, and where the text row of the required links is hidden
// (landing.css), Hack Club's four too, so they stay easy to find. A phone
// hides them all, for the text row. welcome.txt is placed while the page
// loads, before this point runs, so the list lives in the function.
function keptInSight() {
    const row = document.getElementById("credit-links");
    const links = ["Hack Club", "Terms & Privacy", "Bounty", "Security"];
    const keys = ["armand.sponsor", ...(row && getComputedStyle(row).display === "none" ? links : [])];
    return keys.map(key => appsContainer.querySelector(`[data-key="${key}"]`))
        .filter(icon => icon?.offsetParent).map(icon => icon.getBoundingClientRect());
}

// Where a window that opens with the page goes when it has no spot of its
// own: the free spot clear of the icons kept in sight (see freeSpot). One
// taller than the desktop above the kept icons in the bottom half of the
// screen may instead stop 10px above them, its page scrolling inside, when
// that covers less, or for login.exe, lies on less of what it keeps clear
// of (see freeSpot). ship.exe after a login is one: in the top right, it
// would run down over the bottom right group.
function loadSpot(win) {
    const full = freeSpot(win, { atLoad: true });
    const top = desktopTop();
    const low = keptInSight().filter(icon => icon.top > (top + desktopBottom()) / 2).map(icon => icon.top);
    const most = low.length ? Math.floor(Math.min(...low) - 10 - top) : Infinity;
    if (most < 160 || win.offsetHeight <= most || win.classList.contains("resized")) return full;
    const before = win.style.getPropertyValue("--window-max-height");
    capHeight(win, most + "px");
    const capped = freeSpot(win, { atLoad: true });
    if (capped && (!full || (capped.rank !== full.rank ? capped.rank < full.rank : capped.covered < full.covered))) return capped;
    capHeight(win, before);
    return full;
}

// Where a window opened by a click goes: the free spot (see freeSpot). One
// that covers some icon, as a tall window's may, a pet say, instead stops
// above the icons in the bottom half of the screen, as tall as leaves it a
// spot clear of every icon, its page scrolling inside (see cappedClear).
// guide.txt, opened by a click at 1440px, then leaves a pet beside it in
// sight rather than running down over it.
function openSpot(win) {
    const full = freeSpot(win);
    if (full && !full.onIcons) return full;
    return cappedClear(win) ?? full;
}

// The tallest a window may be, stopping 10px above one of the rows of icons
// in the bottom half of the screen, with a spot clear of every icon, and
// that spot. Nothing, and the window as it was, if no such height leaves a
// spot, or it would be under 160px, or the participant sized the window.
function cappedClear(win) {
    if (win.classList.contains("resized")) return null;
    const top = desktopTop();
    const middle = (top + desktopBottom()) / 2;
    const caps = [...new Set(iconBoxes().filter(icon => icon.top > middle).map(icon => Math.floor(icon.top - 10 - top)))]
        .filter(most => most >= 160 && most < win.offsetHeight).sort((a, b) => b - a);
    const before = win.style.getPropertyValue("--window-max-height");
    for (const most of caps) {
        capHeight(win, most + "px");
        const spot = freeSpot(win, { clearOfIcons: true });
        if (spot) return spot;
    }
    capHeight(win, before);
    return null;
}

// A cascaded window that would run down over icons at its full height stops
// 10px above the highest of them instead, its page scrolling inside, when
// that leaves it clear of every icon, as a window that opens with the page
// does (see loadSpot). ship.exe, opened by a click and cascaded over a large
// welcome.txt at 1024px, then ends above the bottom groups. A window sized by
// hand keeps its size.
function cascadeClear(win, spot) {
    const box = () => ({ left: spot.left, top: spot.top, width: win.offsetWidth, height: win.offsetHeight });
    const under = iconBoxes().filter(icon => overlapArea(box(), icon) > 0);
    if (!under.length || win.classList.contains("resized")) return spot;
    const most = Math.floor(Math.min(...under.map(icon => icon.top)) - 10 - spot.top);
    if (most < 160 || most >= win.offsetHeight) return spot;
    const before = win.style.getPropertyValue("--window-max-height");
    capHeight(win, most + "px");
    if (iconBoxes().some(icon => overlapArea(box(), icon) > 0)) capHeight(win, before);
    return spot;
}

// A cap on a window's height, or none, and its frame's page fitted to it.
function capHeight(win, height) {
    if (height) win.style.setProperty("--window-max-height", height);
    else win.style.removeProperty("--window-max-height");
    if (win.querySelector("iframe")) fitFrame(win);
}

function overlapArea(a, b) {
    const width = Math.min(a.left + a.width, b.left + b.width) - Math.max(a.left, b.left);
    const height = Math.min(a.top + a.height, b.top + b.height) - Math.max(a.top, b.top);
    return width > 0 && height > 0 ? width * height : 0;
}

// playground: how wide a window may get. Its content can use the width at
// which its longest line and its widest picture fit without wrapping, plus
// the window's frame, and no more than 720px, about 75 characters, a width
// that still reads well. It may always be as wide as it opens, and the screen
// caps it too (landing.css). For a window with a frame, the frame's page is
// its content. A page not loaded yet leaves the window as wide as it opens.
function widestWidth(win) {
    const content = contentWidth(win);
    return Math.max(openingWidth(win), Math.min(720, content ?? 0));
}

// The width the content asks for, laid out once at its widest and put back
// before anything is drawn.
function contentWidth(win) {
    const frame = win.querySelector("iframe");
    let page = win.querySelector(".windowcontent");
    if (frame) {
        try {
            page = frameLoaded(frame) ? frame.contentDocument.body : null;
        } catch {
            page = null;
        }
        if (!page) return null;
    }
    const around = win.offsetWidth - (frame ?? page).offsetWidth;
    const width = page.style.width;
    page.style.width = "max-content";
    const widest = page.getBoundingClientRect().width;
    page.style.width = width;
    return Math.ceil(widest + around);
}

// The width the window opens at, whatever it was resized to since.
function openingWidth(win) {
    const width = win.style.width;
    win.style.width = "";
    const opens = win.offsetWidth;
    win.style.width = width;
    return opens;
}

// playground: a goal's redeem button in ship.exe opens that goal's redeem
// window, with the shipping form in a frame, as a pet's ship window holds its
// list. Each goal has one. It drags, raises, closes, resizes, fits its form,
// and opens where placeWindow says. A second press raises the open one, and
// what was typed stays. A closed one opens on a fresh form. A redeem, a
// cancel, or a refusal, such as a goal redeemed since ship.exe loaded, sends
// its page to ship.exe, and the window closes (see routeFrame). ship.exe
// shows the redeem's notice or the refusal's alert (see carryMessages).
function openRedeemWindow(url, { atLoad = false } = {}) {
    const goal = new URL(url, location.href).searchParams.get("goal_key");
    if (!/^[a-z0-9_-]+$/.test(goal ?? "")) return;
    const id = `window-redeem-${goal}`;
    let win = document.getElementById(id);
    if (!win) {
        win = document.createElement("div");
        win.className = "window redeem-window";
        win.id = id;
        win.style.display = "none";
        win.style.left = win.style.top = "80px";
        win.innerHTML = `
            <div class="windowheader" id="${id}header">
                <h1 class="headertext"></h1>
                <button type="button" class="windowclose" aria-label="close">X</button>
            </div>
            <div class="windowcontent">
                <iframe class="redeem-frame"></iframe>
            </div>
        `;
        win.querySelector(".headertext").textContent = win.querySelector("iframe").title = `${goal}.redeem`;
        document.body.appendChild(win);
        dragElement(win);
        raiseOnPress(win);
        closeOnButton(win);
        resizeOnFrame(win);
        fitToFrame(win);
        placeOnceFitted(win, atLoad);
    }
    if (win.style.display === "none") {
        win.querySelector("iframe").src = url;
        win.style.display = "flex";
    }
    keepInView(win);
    bringToFront(win);
}

// playground: a reload brings back the open windows, in this browser: which
// ones are open, from the back to the front, the one with focus, where each
// sits and its size if resized, the page each framed one shows, and the
// trash menu if it is open. A spot that no longer fits gives way to the
// usual placing, and a window the page opens never covers the sponsor's
// icon. The state belongs to the account signed
// in, or to no account, so a login never reopens another account's windows.
// A window comes back only when its kind is known and its page belongs in
// it, by the table routeFrame goes by, and a pet's windows only while the
// pet is there. A framed window whose page comes back as an error closes.
// A first visit, with nothing saved, opens welcome.txt as ever. A visitor's
// desktop opens login.exe too, on every load and in front, whatever was
// saved, and a close hides it until the next. An account's never shows it. A
// login opens ship.exe on its dashboard, and the rest come back once that
// page is in, so a message the login left shows there only. On a phone, where
// windows fill the width, only the front window comes back. The state is
// saved as it changes, and a window that closes or fails to open leaves it.
const windowStateStore = `playground-window-state:${appsContainer.dataset.account ?? "visitor"}`;
// A desktop that lands in one of its own frames, as a redirect can land it,
// leaves for the whole window at once (the landing layout). It keeps no
// state: its copy, laid out in the frame, would take the real one's place.
const framedDesktop = window.top !== window.self;
const phoneScreen = matchMedia("(max-width: 560px)");
let windowStateReady = false;
let windowStateSave = null;
let windowStateSaved = null;

function loadWindowState() {
    try {
        const state = JSON.parse(localStorage.getItem(windowStateStore));
        return Array.isArray(state) ? state.filter(entry => entry && typeof entry === "object") : null;
    } catch {
        return null;
    }
}

function saveWindowState() {
    clearTimeout(windowStateSave);
    windowStateSave = null;
    if (!windowStateReady || framedDesktop) return;
    const state = JSON.stringify(openWindowsNow());
    if (state === windowStateSaved) return;
    try {
        localStorage.setItem(windowStateStore, state);
        windowStateSaved = state;
    } catch {
        // Private windows and full storage keep nothing, and a reload starts afresh.
    }
}

function noteWindows() {
    if (windowStateReady && !windowStateSave) windowStateSave = setTimeout(saveWindowState, 50);
}

// The open windows from the back to the front, and the trash menu, which
// lies over them all while it is open.
function openWindowsNow() {
    const focused = document.activeElement?.closest?.(".window");
    const open = [...document.querySelectorAll(".window")]
        .filter(win => getComputedStyle(win).display !== "none")
        .sort((a, b) => Number(getComputedStyle(a).zIndex) - Number(getComputedStyle(b).zIndex))
        .map(win => Object.assign(windowEntry(win) ?? {}, win === focused ? { focused: true } : {}))
        // login.exe opens with a visitor's every load, so it is not saved.
        .filter(entry => entry.kind && entry.kind !== "login");
    if (!trashMenu.hidden) open.push({ kind: "trash", at: [parseFloat(trashMenu.style.left), parseFloat(trashMenu.style.top)] });
    return open;
}

function windowEntry(win) {
    const kind = Object.keys(windowKinds).find(name => windowKinds[name].owns(win));
    const app = win.id === "welcome" ? apps.find(app => app.title === "welcome.txt")
        : apps.find(app => app.content && appWindowId(app) === win.id);
    const entry = kind ? { kind, id: windowKinds[kind].idOf?.(win) ?? null, page: win.dataset.page ?? null }
        : app ? { kind: "app", id: app.key ?? app.title } : null;
    // Where it sits now, and its size if resized, unless it is still being placed.
    if (entry && !win.dataset.placing) {
        entry.place = { left: win.offsetLeft, top: win.offsetTop };
        if (win.classList.contains("resized")) Object.assign(entry.place, { width: win.offsetWidth, height: win.offsetHeight });
    }
    return entry;
}

// The spot a reload gives a window, used once, if it still fits (see
// savedSpot). A var: welcome.txt is placed before this point runs.
var restoredPlaces;

function restoredSpot(win, atLoad) {
    const place = restoredPlaces?.get(win.id);
    if (!place) return null;
    restoredPlaces.delete(win.id);
    return savedSpot(win, atLoad, place);
}

// One saved window, opened as its icon or its page would open it, if it
// passes, at its spot from before the reload. It returns the window, or
// nothing when it does not open.
function restoreWindow(entry) {
    const page = typeof entry.page === "string" ? pageOf(entry.page) : null;
    // A saved page must be one of the window's own. A window saved before
    // its first page came in opens on its usual page.
    const ownPage = owner => entry.page == null || (page && belongsIn(page, owner));
    const pet = Number.isInteger(entry.id) && petIcons.has(entry.id) ? entry.id : null;
    const app = entry.kind === "app" && apps.find(app => app.content && (app.key ?? app.title) === entry.id && !["ship.exe", "login.exe"].includes(app.title));
    const goal = entry.kind === "redeem" && page?.kind === "redeem" && new URL(page.url, location.href).searchParams.get("goal_key");
    const [id, open] = {
        app: () => app && [app.title === "welcome.txt" ? "welcome" : appWindowId(app),
            () => openWindowByTitle(app.title, { atLoad: true })],
        goal: () => ownPage({ kind: "goal", id: null }) && ["window-goal.exe",
            () => openWindowByTitle("ship.exe", { atLoad: true, page: page?.url })],
        guide: () => ownPage({ kind: "guide", id: null }) && ["window-guide.txt",
            () => openWindowByTitle("guide.txt", { atLoad: true, page: page?.url })],
        requirements: () => ownPage({ kind: "requirements", id: null }) && ["window-requirements.txt",
            () => openWindowByTitle("requirements.txt", { atLoad: true, page: page?.url })],
        pet: () => pet != null && ownPage({ kind: "pet", id: pet }) && [`window-pet-${pet}`,
            () => openPetWindow(pet, page?.url, { atLoad: true })],
        ship: () => pet != null && [`window-ship-${pet}`,
            () => openShipWindow(document.querySelector(`#window-pet-${pet} iframe`), pet, petIcons.get(pet).querySelector("p").textContent, { atLoad: true })],
        redeem: () => goal && [`window-redeem-${goal}`, () => openRedeemWindow(page.url, { atLoad: true })]
    }[entry.kind]?.() || [];
    if (entry.kind === "trash") {
        openTrashMenu(Array.isArray(entry.at) && entry.at.length === 2 && entry.at.every(Number.isFinite) ? entry.at : null);
        return null;
    }
    if (!open) return null;
    const place = entry.place;
    if (place && [place.left, place.top].every(Number.isFinite)) restoredPlaces.set(id, place);
    open();
    const win = document.getElementById(id);
    // welcome.txt came with the page, placed already.
    if (win?.id === "welcome") {
        const spot = restoredSpot(win, true);
        if (spot) Object.assign(win.style, { left: spot.left + "px", top: spot.top + "px" });
    }
    // A framed window takes its spot once it fits its page.
    if (!win?.dataset.placing) restoredPlaces.delete(id);
    return win && getComputedStyle(win).display !== "none" ? win : null;
}

function restoreWindows() {
    restoredPlaces = new Map();
    if (framedDesktop) return;
    const saved = loadWindowState();
    // A visitor's login.exe opens with the page, after the rest, in front.
    const done = () => {
        if (!signedIn) openWindowByTitle("login.exe", { atLoad: true });
        windowStateReady = true;
        saveWindowState();
    };
    if (!saved) return done();
    let entries = saved.filter(entry => entry.kind !== "trash" || entry === saved[saved.length - 1]);
    if (phoneScreen.matches) entries = entries.filter(entry => entry.kind !== "trash").slice(-1);
    // welcome.txt comes with the page, and shows only if it was open.
    const welcome = document.getElementById("welcome");
    if (!entries.some(entry => entry.kind === "app" && entry.id === "welcome.txt")) welcome.style.display = "none";
    const reopen = list => {
        let focused = null;
        list.forEach(entry => {
            const win = restoreWindow(entry);
            if (!win) return;
            if (win.querySelector("iframe")) win.dataset.restored = "";
            if (entry.focused) focused = win;
        });
        if (focused) bringToFront(focused);
    };
    if (!openedGoal) {
        reopen(entries);
        return done();
    }
    // The login's ship.exe loads first and takes any message the login left.
    // Then the rest come back behind it. A visitor gets login.exe instead.
    const goal = document.querySelector("#window-goal\\.exe") ?? document.querySelector("#window-login\\.exe");
    const frame = goal?.querySelector("iframe");
    let started = false;
    const rest = () => {
        if (started) return;
        started = true;
        reopen(entries.filter(entry => entry.kind !== "goal"));
        if (goal && goal.style.display !== "none") bringToFront(goal);
        done();
    };
    frame?.addEventListener("load", rest, { once: true });
    setTimeout(rest, frame ? 3000 : 0);
}

// A restored framed window whose page comes back as anything but one of the
// site's own pages, such as an error page, closes.
document.addEventListener("load", event => {
    const frame = event.target;
    const win = frame.tagName === "IFRAME" && frame.closest(".window");
    if (!win || !("restored" in win.dataset)) return;
    delete win.dataset.restored;
    let own = false;
    try {
        own = frame.contentDocument.body.classList.contains("app");
    } catch {
        // A page from another origin is no page of the site's.
    }
    if (!own) win.querySelector(".windowclose").click();
}, true);

// Windows open, close, move to the front, and change page, and the trash
// menu opens and closes, all by their attributes.
new MutationObserver(records => {
    const windows = node => node.classList?.contains("window");
    if (records.some(record => record.type === "childList"
        ? [...record.addedNodes, ...record.removedNodes].some(windows)
        : record.target === trashMenu || windows(record.target))) noteWindows();
}).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "hidden", "data-page"] });
window.addEventListener("pagehide", saveWindowState);
restoreWindows();
