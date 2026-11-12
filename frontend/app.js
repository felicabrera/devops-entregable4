(function () {
  "use strict";

  const API = "/api";
  const form = document.getElementById("note-form");
  const input = document.getElementById("note-text");
  const list = document.getElementById("notes");
  const empty = document.getElementById("empty");
  const count = document.getElementById("count");
  const status = document.getElementById("status");
  const refresh = document.getElementById("refresh");

  async function request(path, options) {
    const response = await fetch(API + path, options);
    if (!response.ok && response.status !== 204) {
      throw new Error("HTTP " + response.status);
    }
    return response.status === 204 ? null : response.json();
  }

  function render(notes) {
    list.textContent = "";
    count.textContent = String(notes.length);
    empty.hidden = notes.length > 0;
    for (const note of notes) {
      const item = document.createElement("li");
      const text = document.createElement("span");
      text.textContent = note.text;
      const when = document.createElement("time");
      when.dateTime = note.created_at;
      when.textContent = new Date(note.created_at).toLocaleString();
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "danger";
      remove.textContent = "Borrar";
      remove.addEventListener("click", async () => {
        await request("/notes/" + note.id, { method: "DELETE" });
        await load();
      });
      item.append(text, when, remove);
      list.append(item);
    }
  }

  async function load() {
    try {
      const health = await request("/health");
      status.textContent = "API " + health.version + " (" + health.env + ")";
      const data = await request("/notes");
      render(data.notes);
    } catch (error) {
      status.textContent = "No se pudo conectar con la API: " + error.message;
    }
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) {
      return;
    }
    await request("/notes", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    input.value = "";
    await load();
  });
  refresh.addEventListener("click", load);

  load();
})();
