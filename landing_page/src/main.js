import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import "./app-simulator.js";
gsap.registerPlugin(ScrollTrigger);

const mobileMenu = document.querySelector("#mobile-menu");
const menuButton = document.querySelector(".menu-button");

function closeMenu({ restoreFocus = false } = {}) {
  mobileMenu.hidden = true;
  menuButton.setAttribute("aria-expanded", "false");
  menuButton.setAttribute("aria-label", "Open menu");
  if (restoreFocus) menuButton.focus();
}
menuButton.addEventListener("click", () => {
  const open = menuButton.getAttribute("aria-expanded") !== "true";
  mobileMenu.hidden = !open;
  menuButton.setAttribute("aria-expanded", String(open));
  menuButton.setAttribute("aria-label", open ? "Close menu" : "Open menu");
});
mobileMenu.addEventListener("click", (event) => {
  if (event.target.closest("a")) closeMenu();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !mobileMenu.hidden)
    closeMenu({ restoreFocus: true });
});
document.addEventListener("click", (event) => {
  if (!event.target.closest(".site-header") && !mobileMenu.hidden) closeMenu();
});
window.matchMedia("(min-width: 651px)").addEventListener("change", (event) => {
  if (event.matches) closeMenu();
});

const stages = {
  sky: {
    status: "Satellite position available",
    title: "Start with a reliable point of reference.",
    description:
      "With a clear view of the sky, satellite fixes establish your position. The phone’s motion sensors contribute to the estimate as you drive.",
  },
  tunnel: {
    status: "Motion sensors take over",
    title: "The signal fades. Motion still tells a story.",
    description:
      "Your phone senses acceleration and turns. GatiSaarth uses that motion to estimate your position, while showing how uncertain the estimate becomes.",
  },
  return: {
    status: "Satellite position reacquired",
    title: "Back under the sky. Back in alignment.",
    description:
      "The engine checks returning satellite fixes before using them. Reliable measurements help correct the position estimate and reduce accumulated uncertainty.",
  },
};
const stageElement = document.querySelector(".signal-stage");
const stageButtons = [...document.querySelectorAll(".signal-controls button")];
function setSignalStage(key) {
  if (stageElement.dataset.signal === key) return;
  const stage = stages[key];
  stageElement.dataset.signal = key;
  stageButtons.forEach((button) =>
    button.setAttribute("aria-pressed", String(button.dataset.signal === key)),
  );
  document.querySelector("#signal-status").textContent = stage.status;
  document.querySelector("#signal-title").textContent = stage.title;
  document.querySelector("#signal-description").textContent = stage.description;
}
stageButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setSignalStage(button.dataset.signal);
  });
});

const capabilityBoard = document.querySelector(".capability-board");
const receptionButtons = [
  ...document.querySelectorAll(".reception-controls button"),
];
function setReception(reception) {
  if (capabilityBoard.dataset.reception === reception) return;
  const lost = reception === "lost";
  capabilityBoard.dataset.reception = reception;
  receptionButtons.forEach((other) =>
    other.setAttribute(
      "aria-pressed",
      String(other.dataset.reception === reception),
    ),
  );
  document.querySelector("#map-result").textContent = lost
    ? "The map stays. A new position needs more."
    : "A satellite fix places you on the map.";
  document.querySelector("#motion-result").textContent = lost
    ? "Motion carries the estimate forward."
    : "Satellite fixes anchor the motion estimate.";
  document.querySelector("#comparison-note").textContent = lost
    ? "The expanding ring represents uncertainty. Error grows during an outage."
    : "Both views begin with a satellite fix. Switch the signal off to see the difference.";
}
receptionButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setReception(button.dataset.reception);
  });
});

// Real app captures only; no generated interface is placed inside a device.
const screenshotDialog = document.querySelector("#screenshot-dialog");
const enlargedScreenshot = document.querySelector("#enlarged-screenshot");
const screenshotTitle = document.querySelector("#screenshot-title");
const captures = {
  map: {
    src: "./screenshots/map.png",
    title: "A journey through Mumbai, Maharashtra",
    alt: "Actual GatiSaarth navigation during a simulated 45 km/h drive in Mumbai, with turn guidance and a route to the Gateway of India",
    caption: "Actual app · Simulated Mumbai drive · v5.2",
  },
  home: {
    src: "./screenshots/home.png",
    title: "Your journey starts here",
    alt: "Actual GatiSaarth home screen with location status and destination selection",
    caption: "Actual app capture · Android emulator · v5.2",
  },
};
let previousBodyOverflow = "";
document.querySelectorAll("[data-screenshot]").forEach((button) => {
  button.addEventListener("click", () => {
    const capture = captures[button.dataset.screenshot];
    enlargedScreenshot.src = capture.src;
    enlargedScreenshot.alt = capture.alt;
    screenshotTitle.textContent = capture.title;
    document.querySelector(".dialog-caption").textContent = capture.caption;
    previousBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    screenshotDialog.showModal();
  });
});
document
  .querySelector(".dialog-close")
  .addEventListener("click", () => screenshotDialog.close());
screenshotDialog.addEventListener("click", (event) => {
  if (event.target !== screenshotDialog) return;
  const rect = screenshotDialog.getBoundingClientRect();
  if (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  )
    screenshotDialog.close();
});
screenshotDialog.addEventListener("close", () => {
  document.body.style.overflow = previousBodyOverflow;
});

// Assign the source only after an explicit request, keeping the 36 MB film
// out of the initial page load. Native controls provide seek and fullscreen.
const demoDialog = document.querySelector("#demo-dialog");
const demoVideo = document.querySelector("#demo-video");
let demoBodyOverflow = "";
let filmSession = 0;
let filmOrientationLocked = false;
const mobileFilm = window.matchMedia(
  "(max-width: 650px), (pointer: coarse) and (max-height: 650px)",
);
function releaseFilmOrientation() {
  if (filmOrientationLocked) {
    screen.orientation?.unlock?.();
    filmOrientationLocked = false;
  }
}
async function openLandscapeFilm() {
  const session = filmSession;
  const hint = document.querySelector("#rotate-hint");
  hint.hidden = false;
  try {
    if (demoVideo.requestFullscreen && document.fullscreenEnabled) {
      await demoVideo.requestFullscreen();
      if (!demoDialog.open || session !== filmSession) {
        if (document.fullscreenElement === demoVideo)
          await document.exitFullscreen();
        return;
      }
      if (screen.orientation?.lock) {
        await screen.orientation.lock("landscape");
        filmOrientationLocked = true;
        if (
          !demoDialog.open ||
          session !== filmSession ||
          document.fullscreenElement !== demoVideo
        ) {
          releaseFilmOrientation();
          return;
        }
        hint.hidden = true;
      }
    } else if (demoVideo.webkitEnterFullscreen) {
      // iPhone's native movie player controls rotation according to OS settings.
      demoVideo.webkitEnterFullscreen();
    }
  } catch {
    // Fullscreen/orientation can be denied by the browser or device settings.
    // Keep the inline player, native controls and a manual fullscreen retry.
  }
}
document
  .querySelector("#film-fullscreen")
  .addEventListener("click", openLandscapeFilm);
document.addEventListener("fullscreenchange", () => {
  if (document.fullscreenElement !== demoVideo) releaseFilmOrientation();
});
document.querySelectorAll("[data-demo]").forEach((button) => {
  button.addEventListener("click", () => {
    filmSession += 1;
    demoBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    demoDialog.showModal();
    if (!demoVideo.hasAttribute("src")) {
      demoVideo.src = "./media/gatisaarth-launch-v1.mp4";
    }
    demoVideo.play().catch(() => {
      // A browser may require its native Play control; leave it available.
    });
    document.querySelector("#rotate-hint").hidden = true;
    if (mobileFilm.matches) void openLandscapeFilm();
  });
});
document
  .querySelector("[data-close-demo]")
  .addEventListener("click", () => demoDialog.close());
demoDialog.addEventListener("click", (event) => {
  if (event.target !== demoDialog) return;
  const rect = demoDialog.getBoundingClientRect();
  if (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  )
    demoDialog.close();
});
demoDialog.addEventListener("close", () => {
  filmSession += 1;
  releaseFilmOrientation();
  if (document.fullscreenElement === demoVideo) {
    document.exitFullscreen().catch(() => {});
  }
  if (demoVideo.webkitDisplayingFullscreen) demoVideo.webkitExitFullscreen?.();
  demoVideo.pause();
  demoVideo.currentTime = 0;
  document.body.style.overflow = demoBodyOverflow;
});
demoVideo.addEventListener("error", () => {
  document.querySelector("#film-error").hidden = false;
});

document.querySelector("#copy-hash").addEventListener("click", async () => {
  const hash = document.querySelector("#apk-hash").textContent.trim();
  const status = document.querySelector("#copy-status");
  try {
    await navigator.clipboard.writeText(hash);
    status.textContent = "Checksum copied";
  } catch {
    status.textContent = "Select the checksum above to copy it.";
    const range = document.createRange();
    range.selectNodeContents(document.querySelector("#apk-hash"));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }
});
document
  .querySelector('a[href="#technical-details"]')
  .addEventListener("click", () => {
    document.querySelector("#technical-details details").open = true;
  });

// Native scrolling stays in charge; GSAP animates scenes as they enter the view.
// matchMedia reverts every tween and ScrollTrigger when reduced motion is enabled.
const motion = gsap.matchMedia();
motion.add("(prefers-reduced-motion: no-preference)", () => {
  if (window.scrollY < 120) {
    gsap.from(".hero-copy > *", {
      y: 24,
      opacity: 0,
      duration: 0.85,
      stagger: 0.12,
      ease: "power3.out",
      clearProps: "transform,opacity",
    });
    gsap.from(".hero-device", {
      opacity: 0,
      duration: 1.1,
      delay: 0.25,
      clearProps: "opacity",
    });
  }

  gsap.utils.toArray("[data-parallax-scene]").forEach((scene) => {
    gsap.fromTo(
      scene,
      { "--scroll-shift": -1 },
      {
        "--scroll-shift": 1,
        ease: "none",
        scrollTrigger: {
          trigger: scene,
          start: "top bottom",
          end: "bottom top",
          scrub: 0.6,
        },
      },
    );
  });

  gsap.utils
    .toArray(
      ".signal-intro, .difference-heading, .journey-copy > h2, .features-heading, .intelligence-copy, .faq-section > h2",
    )
    .forEach((element) => {
      gsap.from(element, {
        y: 28,
        opacity: 0,
        duration: 0.85,
        ease: "power3.out",
        clearProps: "transform,opacity",
        scrollTrigger: { trigger: element, start: "top 91%", once: true },
      });
    });

  gsap.from(".signal-stage", {
    y: 35,
    opacity: 0,
    duration: 1,
    ease: "power3.out",
    clearProps: "transform,opacity",
    scrollTrigger: { trigger: ".signal-stage", start: "top 91%", once: true },
  });
  // Only crossing a scroll boundary changes the scene. A manual choice stays
  // selected within the current segment, then scrolling resumes in either direction.
  let lastSignalSegment;
  const syncSignalToScroll = ({ progress }) => {
    const segment =
      progress < 0.3 ? "sky" : progress < 0.8 ? "tunnel" : "return";
    if (segment !== lastSignalSegment) {
      lastSignalSegment = segment;
      setSignalStage(segment);
    }
  };
  ScrollTrigger.create({
    trigger: ".signal-stage",
    start: "top 78%",
    end: "bottom 45%",
    onUpdate: syncSignalToScroll,
    onRefresh: syncSignalToScroll,
  });

  gsap.from(".capability-track", {
    y: 22,
    opacity: 0,
    duration: 0.8,
    stagger: 0.18,
    ease: "power3.out",
    clearProps: "transform,opacity",
    scrollTrigger: {
      trigger: ".capability-board",
      start: "top 87%",
      once: true,
    },
  });
  let lastReceptionSegment;
  const syncReceptionToScroll = ({ progress }) => {
    const segment = progress < 0.4 ? "available" : "lost";
    if (segment !== lastReceptionSegment) {
      lastReceptionSegment = segment;
      setReception(segment);
    }
  };
  ScrollTrigger.create({
    trigger: ".capability-board",
    start: "top 85%",
    end: "bottom 55%",
    onUpdate: syncReceptionToScroll,
    onRefresh: syncReceptionToScroll,
  });
  gsap.utils.toArray(".journey-steps li").forEach((step) => {
    gsap.fromTo(
      step,
      { "--step-progress": 0 },
      {
        "--step-progress": 1,
        ease: "none",
        scrollTrigger: {
          trigger: step,
          start: "top 82%",
          end: "bottom 48%",
          scrub: 0.5,
        },
      },
    );
  });
  gsap.from(".confidence-ring", {
    scale: 0.45,
    opacity: 0,
    stagger: 0.2,
    duration: 1.2,
    ease: "power2.out",
    clearProps: "transform,opacity",
    scrollTrigger: {
      trigger: ".confidence-ring",
      start: "top 88%",
      once: true,
    },
  });
  gsap.utils.toArray(".faq-list details").forEach((detail) => {
    gsap.from(detail, {
      y: 16,
      opacity: 0,
      duration: 0.65,
      ease: "power2.out",
      clearProps: "transform,opacity",
      scrollTrigger: { trigger: detail, start: "top 96%", once: true },
    });
  });
  gsap.from(".advantage-strip article", {
    y: 22,
    opacity: 0,
    duration: 0.7,
    stagger: 0.12,
    ease: "power3.out",
    clearProps: "transform,opacity",
    scrollTrigger: {
      trigger: ".advantage-strip",
      start: "top 90%",
      once: true,
    },
  });

  gsap.utils.toArray(".journey-steps li, .feature").forEach((element) => {
    gsap.from(element, {
      y: 30,
      opacity: 0,
      duration: 0.8,
      ease: "power3.out",
      clearProps: "transform,opacity",
      scrollTrigger: {
        trigger: element,
        start: "top 90%",
        once: true,
        onEnter: () => element.classList.add("is-seen"),
      },
    });
  });

  // Draw the original illustrations without changing either real app capture.
  gsap.utils
    .toArray(".map-art svg > path, .sensor-art path")
    .forEach((path) => {
      const length = path.getTotalLength();
      gsap.fromTo(
        path,
        { strokeDasharray: length, strokeDashoffset: length },
        {
          strokeDashoffset: 0,
          duration: 1.5,
          ease: "power2.inOut",
          scrollTrigger: {
            trigger: path.closest(".feature"),
            start: "top 83%",
            once: true,
          },
        },
      );
    });

  const fusion = gsap.timeline({
    scrollTrigger: { trigger: ".fusion-visual", start: "top 84%", once: true },
  });
  fusion
    .from(".fusion-inputs > span", {
      y: 18,
      opacity: 0,
      duration: 0.6,
      stagger: 0.12,
      clearProps: "transform,opacity",
    })
    .from(
      ".fusion-core",
      { y: 15, opacity: 0, duration: 0.6, clearProps: "transform,opacity" },
      "-=.2",
    )
    .from(
      ".fusion-output",
      { y: 12, opacity: 0, duration: 0.5, clearProps: "transform,opacity" },
      "-=.15",
    );
  gsap.from(".download-inner > h2, .download-inner > p, .download-inner > a", {
    y: 24,
    opacity: 0,
    stagger: 0.12,
    duration: 0.8,
    ease: "power3.out",
    clearProps: "transform,opacity",
    scrollTrigger: {
      trigger: ".download-inner",
      start: "top 82%",
      once: true,
    },
  });
});

// FAQ Accordion: Smooth expansion and desktop hover disclosure
const faqDetails = Array.from(document.querySelectorAll(".faq-list details"));
const canHover = () =>
  window.matchMedia("(hover: hover) and (pointer: fine)").matches;

function openFaqItem(detail, { immediate = false } = {}) {
  if (detail.dataset.animating === "open") return;
  if (detail.open && !detail.dataset.animating) return;

  faqDetails.forEach((other) => {
    if (other !== detail && other.open) {
      closeFaqItem(other, { immediate });
    }
  });

  const answer = detail.querySelector(".faq-answer");
  const icon = detail.querySelector("summary .icon");
  detail.dataset.animating = "open";
  detail.open = true;

  if (
    immediate ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    if (answer) {
      answer.style.height = "auto";
      answer.style.opacity = "1";
    }
    if (icon) icon.style.transform = "rotate(45deg)";
    delete detail.dataset.animating;
    ScrollTrigger.refresh();
    return;
  }

  if (answer) {
    gsap.killTweensOf(answer);
    answer.style.height = "auto";
    const targetHeight = answer.scrollHeight;
    const startHeight = answer.offsetHeight || 0;

    gsap.fromTo(
      answer,
      { height: startHeight, opacity: startHeight > 0 ? undefined : 0 },
      {
        height: targetHeight,
        opacity: 1,
        duration: 0.38,
        ease: "power2.out",
        onUpdate: () => ScrollTrigger.refresh(),
        onComplete: () => {
          answer.style.height = "auto";
          delete detail.dataset.animating;
          ScrollTrigger.refresh();
        },
      },
    );
  }
  if (icon) {
    gsap.to(icon, { rotate: 45, duration: 0.3, ease: "power2.out" });
  }
}

function closeFaqItem(detail, { immediate = false, force = false } = {}) {
  if (!detail.open || detail.dataset.animating === "close") return;
  if (!force) {
    if (detail.contains(document.activeElement)) return;
    if (document.querySelector("dialog[open]")) return;
  }

  const answer = detail.querySelector(".faq-answer");
  const icon = detail.querySelector("summary .icon");
  detail.dataset.animating = "close";

  if (
    immediate ||
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ) {
    detail.open = false;
    if (answer) {
      answer.style.height = "0px";
      answer.style.opacity = "0";
    }
    if (icon) icon.style.transform = "rotate(0deg)";
    delete detail.dataset.animating;
    ScrollTrigger.refresh();
    return;
  }

  if (answer) {
    gsap.killTweensOf(answer);
    const startHeight = answer.scrollHeight;

    gsap.fromTo(
      answer,
      { height: startHeight, opacity: 1 },
      {
        height: 0,
        opacity: 0,
        duration: 0.3,
        ease: "power2.inOut",
        onUpdate: () => ScrollTrigger.refresh(),
        onComplete: () => {
          detail.open = false;
          delete detail.dataset.animating;
          ScrollTrigger.refresh();
        },
      },
    );
  } else {
    detail.open = false;
    delete detail.dataset.animating;
    ScrollTrigger.refresh();
  }
  if (icon) {
    gsap.to(icon, { rotate: 0, duration: 0.28, ease: "power2.inOut" });
  }
}

let faqHoverTimeout = null;

faqDetails.forEach((detail) => {
  const summary = detail.querySelector("summary");

  detail.addEventListener("mouseenter", () => {
    if (!canHover()) return;
    if (faqHoverTimeout) {
      clearTimeout(faqHoverTimeout);
      faqHoverTimeout = null;
    }
    detail.dataset.hoveredAt = String(Date.now());
    openFaqItem(detail);
  });

  detail.addEventListener("mouseleave", () => {
    if (!canHover()) return;
    delete detail.dataset.hoveredAt;
    if (faqHoverTimeout) clearTimeout(faqHoverTimeout);
    faqHoverTimeout = setTimeout(() => {
      if (detail.contains(document.activeElement)) return;
      if (document.querySelector("dialog[open]")) return;
      closeFaqItem(detail);
    }, 140);
  });

  if (summary) {
    summary.addEventListener("click", (event) => {
      event.preventDefault();
      const justHovered =
        detail.dataset.hoveredAt &&
        Date.now() - Number(detail.dataset.hoveredAt) < 800;
      if (justHovered) {
        openFaqItem(detail);
        delete detail.dataset.hoveredAt;
      } else if (detail.open && detail.dataset.animating !== "open") {
        closeFaqItem(detail);
      } else {
        openFaqItem(detail);
      }
    });
  }
});

// Disclosures and late font/image layout changes can move later trigger positions.
document
  .querySelectorAll("details")
  .forEach((details) =>
    details.addEventListener("toggle", () => ScrollTrigger.refresh()),
  );
document.fonts.ready.then(() => ScrollTrigger.refresh());
window.addEventListener("load", () => ScrollTrigger.refresh(), { once: true });
if (import.meta.hot) import.meta.hot.dispose(() => motion.revert());
