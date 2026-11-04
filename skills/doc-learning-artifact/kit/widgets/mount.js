// mount every widget; a failing widget shows a message and reports to the console (check.py fails on console errors)
document.querySelectorAll(".wg[data-wg]").forEach(root => {
  const f = WG[root.dataset.wg];
  try {
    if (!f) throw new Error("no widget named " + root.dataset.wg);
    f(root); root.dataset.ready = "1";
  } catch (e) {
    root.dataset.ready = "0";
    root.innerHTML = '<div class="wg-body"><p class="wg-note">Šis interaktyvus elementas neįsikėlė.</p></div>';
    console.error("widget " + root.dataset.wg + ": " + e.message);
  }
});
