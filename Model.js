// Model.js — pure helpers for the Fizzy widget. No QML state in here.
.pragma library

// Fizzy runs at app.fizzy.do, but it also self-hosts, so every request goes
// through config.base_url and this default is only the fallback. The value is
// user-typed (auth page or a hand-edited config file), so normalize it before
// it reaches curl rather than trusting whatever was pasted.
var DEFAULT_BASE_URL = "https://app.fizzy.do";

function defaultBaseUrl() {
  return DEFAULT_BASE_URL;
}

// Returns a canonical "scheme://host[:port][/prefix]" with no trailing slash,
// or "" when the input can't be a Fizzy address. Blank means "the default".
function normalizeBaseUrl(input) {
  var raw = String(input || "").trim();
  if (raw === "") return DEFAULT_BASE_URL;
  if (/[\s"'<>\\]/.test(raw)) return "";

  if (!/^[a-z][a-z0-9+.\-]*:\/\//i.test(raw)) {
    // A scheme is "word://"; a colon followed by digits is a port, so
    // "localhost:3000" stays a host. Anything else (file:, javascript:, ...)
    // is a typo at best.
    if (/^[a-z][a-z0-9+.\-]*:(?!\d)/i.test(raw)) return "";
    // The common paste is a bare host — "fizzy.example.com" — and https is
    // the only sane default off-machine. A loopback host is the exception:
    // it is a dev instance, which does not speak TLS.
    var loopback = /^(localhost|127\.[0-9.]+|\[::1\])(:|\/|$)/i.test(raw);
    raw = (loopback ? "http://" : "https://") + raw;
  }

  var match = /^(https?):\/\/([^\/?#]+)([^?#]*)/i.exec(raw);
  if (!match) return "";

  var host = match[2];
  // Credentials in the host would ride along on every request URL.
  if (host.indexOf("@") >= 0) return "";
  var named = /^[a-z0-9][a-z0-9.\-]*(:[0-9]{1,5})?$/i.test(host);
  var bracketed = /^\[[0-9a-f:.]+\](:[0-9]{1,5})?$/i.test(host);
  if (!named && !bracketed) return "";

  // A path prefix is kept (some instances live under one); the trailing
  // slash is not, because every API path already starts with one.
  var prefix = String(match[3] || "").replace(/\/+$/, "");
  return match[1].toLowerCase() + "://" + host.toLowerCase() + prefix;
}

// What to show a human: the address without the scheme noise.
function baseUrlLabel(url) {
  return String(url || "").replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}

// Fizzy column palette. The API reports colors as CSS variables
// (var(--color-card-N)) with a human name; map both to hex per theme.
var PALETTE = {
  "default": { name: "Blue",   dark: "#6ea8fe", light: "#2f6fed" },
  "1":       { name: "Gray",   dark: "#9aa4b2", light: "#6b7280" },
  "2":       { name: "Tan",    dark: "#d2b48c", light: "#a1794f" },
  "3":       { name: "Yellow", dark: "#f2d16b", light: "#c9a227" },
  "4":       { name: "Lime",   dark: "#a3d977", light: "#5f9e3c" },
  "5":       { name: "Aqua",   dark: "#6fd6d0", light: "#12958d" },
  "6":       { name: "Violet", dark: "#b79cff", light: "#7c5cd6" },
  "7":       { name: "Purple", dark: "#cf9bf2", light: "#9d4edd" },
  "8":       { name: "Pink",   dark: "#f4a6c8", light: "#d6608f" }
};

function columnColor(column, lightTheme) {
  var key = "default";
  if (column && column.color) {
    var value = typeof column.color === "object" ? column.color.value : column.color;
    var match = /--color-card-(\w+)/.exec(String(value || ""));
    if (match) key = match[1];
  }
  var entry = PALETTE[key] || PALETTE["default"];
  return lightTheme ? entry.light : entry.dark;
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""));
    return parsed === null || parsed === undefined ? fallback : parsed;
  } catch (e) {
    return fallback;
  }
}

function parseArray(text) {
  var parsed = parseJson(text, []);
  return Array.isArray(parsed) ? parsed : [];
}

// Group an open-cards list response into Maybe? (no column) + per-column ids.
function groupOpenCards(cards) {
  var maybe = [];
  var byColumn = {};
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    // Ids are normalized to strings at this boundary; everything downstream
    // (filter keys, chip actives, mover targets) compares strings only.
    var columnId = card.column && card.column.id ? String(card.column.id) : null;
    if (!columnId) {
      maybe.push(card);
    } else {
      if (!byColumn[columnId]) byColumn[columnId] = [];
      byColumn[columnId].push(card);
    }
  }
  return { maybe: maybe, byColumn: byColumn };
}

// Filter chips for a board, in Fizzy's own words: Maybe?, columns, Not Now, Done.
function buildFilters(columns, grouped, lightTheme) {
  var filters = [{
    key: "maybe", label: "Maybe?", dot: "", count: grouped.maybe.length
  }];
  for (var i = 0; i < columns.length; i++) {
    var column = columns[i];
    var inColumn = grouped.byColumn[String(column.id)] || [];
    filters.push({
      key: String(column.id),
      label: column.name,
      dot: columnColor(column, lightTheme),
      count: inColumn.length
    });
  }
  filters.push({ key: "not_now", label: "Not Now", dot: "", count: -1 });
  filters.push({ key: "closed", label: "Done", dot: "", count: -1 });
  return filters;
}

function cardsForFilter(filterKey, grouped, notNowCards, closedCards) {
  if (filterKey === "maybe") return grouped.maybe;
  if (filterKey === "not_now") return notNowCards;
  if (filterKey === "closed") return closedCards;
  return grouped.byColumn[filterKey] || [];
}

// Where a card currently lives, as a mover-chip key.
function cardPlace(card, listKey) {
  if (!card) return "maybe";
  if (card.closed === true || listKey === "closed") return "closed";
  if (listKey === "not_now") return "not_now";
  if (card.column && card.column.id) return String(card.column.id);
  return "maybe";
}

// Stable per-person color drawn from Fizzy's own card palette, so avatars
// are colorful without leaving the product's color language.
var AVATAR_KEYS = ["default", "3", "4", "5", "6", "7", "8", "2"];

function avatarColor(name, lightTheme) {
  var s = String(name || "");
  var hash = 0;
  for (var i = 0; i < s.length; i++) hash = (hash * 31 + s.charCodeAt(i)) | 0;
  var entry = PALETTE[AVATAR_KEYS[Math.abs(hash) % AVATAR_KEYS.length]];
  return lightTheme ? entry.light : entry.dark;
}

function initials(name) {
  var parts = String(name || "").trim().split(/\s+/);
  if (parts.length === 0 || parts[0] === "") return "?";
  var first = parts[0].charAt(0);
  var last = parts.length > 1 ? parts[parts.length - 1].charAt(0) : "";
  return (first + last).toUpperCase();
}

function relativeTime(isoString, now) {
  var then = new Date(isoString).getTime();
  if (isNaN(then)) return "";
  var seconds = Math.max(0, Math.floor(((now || Date.now()) - then) / 1000));
  if (seconds < 60) return "now";
  if (seconds < 3600) return Math.floor(seconds / 60) + "m";
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h";
  if (seconds < 86400 * 30) return Math.floor(seconds / 86400) + "d";
  return Math.floor(seconds / (86400 * 30)) + "mo";
}

function stepsProgress(steps) {
  var list = steps || [];
  var done = 0;
  for (var i = 0; i < list.length; i++) if (list[i].completed) done++;
  return { done: done, total: list.length };
}

// Qt RichText fetches <img src> resources, remote URLs included; strip them
// so remote-authored HTML can't trigger network loads from the shell.
function stripImages(html) {
  return String(html || "").replace(/<img\b[^>]*>/gi, "");
}

// Comment body arrives as { plain_text, html }; older shapes were strings.
function commentHtml(comment) {
  if (!comment) return "";
  var body = comment.body;
  if (body && typeof body === "object") return stripImages(body.html || body.plain_text || "");
  return stripImages(comment.body_html || String(body || ""));
}

function tagTitle(tag) {
  return typeof tag === "object" ? (tag.title || "") : String(tag || "");
}

function hasAssignee(card, userId) {
  var assignees = (card && card.assignees) || [];
  for (var i = 0; i < assignees.length; i++)
    if (String(assignees[i].id) === String(userId)) return true;
  return false;
}

function hasTag(card, title) {
  var tags = (card && card.tags) || [];
  for (var i = 0; i < tags.length; i++)
    if (tagTitle(tags[i]).toLowerCase() === String(title).toLowerCase()) return true;
  return false;
}

// Pick the account slug out of a /my/identity response. Accounts usually
// carry a slug or a URL ending in the slug; handle both defensively.
function accountsFromIdentity(identity) {
  var raw = identity && identity.accounts ? identity.accounts : [];
  var accounts = [];
  for (var i = 0; i < raw.length; i++) {
    var account = raw[i];
    var slug = account.slug || account.account_slug || "";
    if (!slug && account.url) {
      var match = /^https?:\/\/[^/]+\/([^/]+)/.exec(account.url);
      if (match) slug = match[1];
    }
    if (slug) {
      accounts.push({
        slug: String(slug).replace(/^\//, ""),
        name: account.name || account.company_name || String(slug)
      });
    }
  }
  return accounts;
}
