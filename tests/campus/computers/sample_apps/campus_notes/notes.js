const form = document.querySelector("#notebook");
const note = document.querySelector("#note");
const save = document.querySelector("button[type=submit]");
const status = document.querySelector("#status");
const storage = "/__campus__/state.json";

async function openNotebook() {
  try {
    const response = await fetch(storage);
    if (!response.ok) throw new Error("Notebook unavailable");
    const state = await response.json();
    note.value = typeof state.note === "string" ? state.note : "";
    note.disabled = false;
    save.disabled = false;
    status.textContent = "";
  } catch {
    status.textContent = "Install this package to open its notebook.";
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const body = JSON.stringify({note: note.value});
  if (new TextEncoder().encode(body).length > 4096) {
    status.textContent = "This note is too long. Shorten it and try again.";
    return;
  }
  save.disabled = true;
  try {
    const response = await fetch(storage, {method: "PUT", body});
    if (!response.ok) throw new Error("Save unavailable");
    status.textContent = "Note saved.";
  } catch {
    status.textContent = "Could not save this note. Try again.";
  } finally {
    save.disabled = false;
  }
});

openNotebook();
