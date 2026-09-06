#!/usr/bin/env node
// Tests for Model.js — the shaping the panel binds to.
//
//   node dev/test-model.js
//
// Model.js is deliberately free of Qt types so it can be run here: the address
// parsing, the board grouping, the filter chips, the avatar colours and the
// time labels are all decisions worth checking without a compositor in the way.
"use strict"

const fs = require("fs")
const path = require("path")

const source = fs
  .readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(".pragma library", "")

const Model = new Function(
  source +
    "; return { defaultBaseUrl, normalizeBaseUrl, baseUrlLabel, columnColor, parseJson, " +
    "parseArray, groupOpenCards, buildFilters, cardsForFilter, cardPlace, avatarColor, " +
    "initials, relativeTime, stepsProgress, stripImages, commentHtml, tagTitle, " +
    "hasAssignee, hasTag, accountsFromIdentity, themeColor }"
)()

let passed = 0
const failures = []

function test(name, body) {
  try {
    body()
    passed++
  } catch (error) {
    failures.push(name + ": " + error.message)
  }
}

function eq(actual, expected, what) {
  const a = JSON.stringify(actual)
  const b = JSON.stringify(expected)
  if (a !== b) throw new Error((what || "") + " expected " + b + " got " + a)
}

function ok(value, what) {
  if (!value) throw new Error(what || "expected truthy")
}

const column = (id, name, value) => ({
  id, name, color: { name, value: "var(--color-card-" + value + ")" }
})

const card = (over) => Object.assign({
  number: 1, title: "A card", column: null, assignees: [], tags: [], closed: false
}, over || {})

// ---------------------------------------------------------- normalizeBaseUrl

test("blank means the default instance", () => {
  eq(Model.normalizeBaseUrl(""), Model.defaultBaseUrl())
  eq(Model.normalizeBaseUrl("   "), Model.defaultBaseUrl())
})

test("a bare host is https, because off-machine it always is", () => {
  eq(Model.normalizeBaseUrl("fizzy.example.com"), "https://fizzy.example.com")
})

test("loopback is http, because a dev instance does not speak TLS", () => {
  eq(Model.normalizeBaseUrl("localhost:3000"), "http://localhost:3000")
  eq(Model.normalizeBaseUrl("127.0.0.1:3000"), "http://127.0.0.1:3000")
})

test("the scheme and host are lowercased, the trailing slash dropped", () => {
  eq(Model.normalizeBaseUrl("HTTPS://Fizzy.Example.COM/"), "https://fizzy.example.com")
})

test("a path prefix survives, because some instances live under one", () => {
  eq(Model.normalizeBaseUrl("https://example.com/fizzy/"), "https://example.com/fizzy")
})

test("an address that could not be a Fizzy instance is refused", () => {
  for (const bad of ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com",
                     "https://user:pw@example.com", "https://exa mple.com",
                     'https://example.com/"', "https://exa<mple>.com"])
    eq(Model.normalizeBaseUrl(bad), "", bad)
})

test("a port on a bare host is a port, not a scheme", () => {
  eq(Model.normalizeBaseUrl("fizzy.example.com:8443"), "https://fizzy.example.com:8443")
})

test("the label is the address without the scheme noise", () => {
  eq(Model.baseUrlLabel("https://fizzy.example.com/"), "fizzy.example.com")
  eq(Model.baseUrlLabel(""), "")
})

// ------------------------------------------------------------- board shaping

test("a card with no column is in Maybe?, one with a column is not", () => {
  const grouped = Model.groupOpenCards([
    card({ number: 1 }),
    card({ number: 2, column: column("c1", "Working on", "6") })
  ])
  eq(grouped.maybe.map((c) => c.number), [1])
  eq(grouped.byColumn["c1"].map((c) => c.number), [2])
})

test("column ids are compared as strings, whatever the API sent", () => {
  const grouped = Model.groupOpenCards([card({ number: 7, column: { id: 42 } })])
  ok(grouped.byColumn["42"], "numeric id should key as a string")
})

test("the filter chips are Maybe?, the columns, Not Now, Done", () => {
  const cols = [column("c1", "Needs to be done", "5"), column("c2", "Working on", "6")]
  const grouped = Model.groupOpenCards([
    card({ number: 1 }),
    card({ number: 2, column: cols[1] }),
    card({ number: 3, column: cols[1] })
  ])
  const filters = Model.buildFilters(cols, grouped, false)
  eq(filters.map((f) => f.key), ["maybe", "c1", "c2", "not_now", "closed"])
  eq(filters.map((f) => f.count), [1, 0, 2, -1, -1])
})

test("Not Now and Done come from their own lists, not from the board", () => {
  const grouped = Model.groupOpenCards([card({ number: 1 })])
  eq(Model.cardsForFilter("maybe", grouped, [], []).length, 1)
  eq(Model.cardsForFilter("not_now", grouped, [card({ number: 9 })], []).length, 1)
  eq(Model.cardsForFilter("closed", grouped, [], [card({ number: 8 })]).length, 1)
  eq(Model.cardsForFilter("nope", grouped, [], []), [])
})

test("where a card lives: closed wins over the list, the list over the column", () => {
  eq(Model.cardPlace(card({ closed: true, column: { id: "c1" } }), "maybe"), "closed")
  eq(Model.cardPlace(card({ column: { id: "c1" } }), "not_now"), "not_now")
  eq(Model.cardPlace(card({ column: { id: "c1" } }), "maybe"), "c1")
  eq(Model.cardPlace(card(), "maybe"), "maybe")
  eq(Model.cardPlace(null, "maybe"), "maybe")
})

// -------------------------------------------------------------------- people

test("initials are first and last, and never empty", () => {
  eq(Model.initials("Ada Okonkwo"), "AO")
  eq(Model.initials("Prince"), "P")
  eq(Model.initials("  Camille   Devereux  "), "CD")
  eq(Model.initials(""), "?")
  eq(Model.initials(null), "?")
})

test("a person's colour is stable, and comes from Fizzy's own palette", () => {
  const once = Model.avatarColor("Ada Okonkwo", false)
  eq(Model.avatarColor("Ada Okonkwo", false), once)
  ok(/^#[0-9a-f]{6}$/i.test(once), "expected a hex colour, got " + once)
  ok(Model.avatarColor("Ada Okonkwo", true) !== once, "light theme should differ")
})

test("assignment is checked by id, as a string", () => {
  const crowded = card({ assignees: [{ id: "u1" }, { id: 2 }] })
  ok(Model.hasAssignee(crowded, "u1"))
  ok(Model.hasAssignee(crowded, "2"), "numeric id should match its string")
  ok(!Model.hasAssignee(crowded, "u9"))
  ok(!Model.hasAssignee(null, "u1"))
})

test("a card carries as many people as it likes", () => {
  const five = card({ assignees: ["a", "b", "c", "d", "e"].map((id) => ({ id })) })
  eq(five.assignees.length, 5)
  ok(five.assignees.every((who) => Model.hasAssignee(five, who.id)))
})

// ---------------------------------------------------------------------- tags

test("a tag is its title, whether it arrives as an object or a string", () => {
  eq(Model.tagTitle({ title: "infra" }), "infra")
  eq(Model.tagTitle("infra"), "infra")
  eq(Model.tagTitle(null), "")
})

test("tag matching ignores case", () => {
  ok(Model.hasTag(card({ tags: [{ title: "Infra" }] }), "infra"))
  ok(!Model.hasTag(card({ tags: [] }), "infra"))
})

// --------------------------------------------------------------------- steps

test("progress counts what is completed", () => {
  eq(Model.stepsProgress([{ completed: true }, { completed: false }]), { done: 1, total: 2 })
  eq(Model.stepsProgress([]), { done: 0, total: 0 })
  eq(Model.stepsProgress(null), { done: 0, total: 0 })
})

// ------------------------------------------------------------------ comments

test("a comment body is read from either shape the API uses", () => {
  eq(Model.commentHtml({ body: { html: "<p>hi</p>" } }), "<p>hi</p>")
  eq(Model.commentHtml({ body: { plain_text: "hi" } }), "hi")
  eq(Model.commentHtml({ body_html: "<p>hi</p>" }), "<p>hi</p>")
  eq(Model.commentHtml(null), "")
})

test("images are stripped, so remote HTML cannot make the shell fetch", () => {
  eq(Model.stripImages('<p>a<img src="https://tracker.example/x.gif">b</p>'), "<p>ab</p>")
  eq(Model.commentHtml({ body: { html: '<IMG SRC="x">hi' } }), "hi")
})

// ---------------------------------------------------------------- timestamps

test("relative time reads the way a person would say it", () => {
  const now = Date.parse("2026-09-06T12:00:00Z")
  const ago = (s) => Model.relativeTime(new Date(now - s * 1000).toISOString(), now)
  eq(ago(10), "now")
  eq(ago(60 * 14), "14m")
  eq(ago(3600 * 4), "4h")
  eq(ago(86400 * 3), "3d")
  eq(ago(86400 * 90), "3mo")
})

test("a timestamp that is not one says nothing at all", () => {
  eq(Model.relativeTime("not a date", Date.now()), "")
})

// ------------------------------------------------------------------ identity

test("an account slug is taken from the slug, or from the URL if it has none", () => {
  eq(Model.accountsFromIdentity({ accounts: [{ slug: "/3", name: "Northwind" }] }),
     [{ slug: "3", name: "Northwind" }])
  eq(Model.accountsFromIdentity({ accounts: [{ url: "https://fizzy.example/7/x" }] }),
     [{ slug: "7", name: "7" }])
  eq(Model.accountsFromIdentity({ accounts: [{ name: "no slug anywhere" }] }), [])
  eq(Model.accountsFromIdentity(null), [])
})

// --------------------------------------------------------------------- theme

test("the plugin's colour is one of the theme's, and the bar's is the default", () => {
  eq(Model.themeColor("bar active", "#bar", "#accent", "#urgent"), "#bar")
  eq(Model.themeColor("accent", "#bar", "#accent", "#urgent"), "#accent")
  eq(Model.themeColor("urgent", "#bar", "#accent", "#urgent"), "#urgent")
  eq(Model.themeColor("nonsense", "#bar", "#accent", "#urgent"), "#bar")
})

// -------------------------------------------------------------------- colour

test("a column paints in its palette entry, and an unknown one still paints", () => {
  const aqua = Model.columnColor(column("c", "Aqua", "5"), false)
  ok(/^#[0-9a-f]{6}$/i.test(aqua))
  ok(/^#[0-9a-f]{6}$/i.test(Model.columnColor(null, false)))
  ok(Model.columnColor(column("c", "Aqua", "5"), true) !== aqua, "light theme should differ")
})

// --------------------------------------------------------------------- parse

test("bad JSON is the fallback, not a crash", () => {
  eq(Model.parseJson("{not json", { a: 1 }), { a: 1 })
  eq(Model.parseJson("null", "fallback"), "fallback")
  eq(Model.parseArray("{}"), [])
  eq(Model.parseArray('[{"number":1}]'), [{ number: 1 }])
})

// ----------------------------------------------------------------

if (failures.length > 0) {
  console.error(failures.length + " failed:")
  failures.forEach((line) => console.error("  " + line))
  process.exit(1)
}
console.log(passed + " passed")
