#!/usr/bin/env node
// Tests for the demo fixtures — that fizzy-fetch --demo answers every request
// the panel makes, in the shape the panel reads.
//
//   node dev/test-demo.js
//
// This is the test that would have caught steps rendering as empty rows: the
// fixtures had a `title` on each step and CardPage.qml reads `content`, and
// nothing but a screenshot said so. Anything the QML reads off a fixture
// belongs here, named after the file that reads it.
"use strict"

const { execFileSync } = require("child_process")
const path = require("path")

const HELPER = path.join(__dirname, "..", "fizzy-fetch")

function get(apiPath) {
  const out = execFileSync(HELPER, ["--demo", "GET", apiPath], { encoding: "utf8" })
  return JSON.parse(out)
}

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

function ok(value, what) {
  if (!value) throw new Error(what || "expected truthy")
}

function eq(actual, expected, what) {
  if (JSON.stringify(actual) !== JSON.stringify(expected))
    throw new Error((what || "") + " expected " + JSON.stringify(expected) +
                    " got " + JSON.stringify(actual))
}

const BOARD = "demo-board-1"
const cards = () => get("/1/cards?board_ids%5B%5D=" + BOARD)

// ------------------------------------------------------------- every request

test("the panel's whole first load is answered", () => {
  ok(get("/my/identity").accounts.length > 0, "identity")
  ok(get("/1/boards").length >= 2, "boards")
  ok(get("/1/boards/" + BOARD + "/columns").length >= 3, "columns")
  ok(cards().length > 0, "cards")
  ok(get("/1/users").length > 0, "users")
  ok(get("/1/tags").length > 0, "tags")
  ok(get("/1/cards?board_ids%5B%5D=" + BOARD + "&indexed_by=not_now").length > 0, "not now")
  ok(get("/1/cards?board_ids%5B%5D=" + BOARD + "&indexed_by=closed").length > 0, "done")
  ok(get("/1/cards/388").number === 388, "card detail")
  ok(get("/1/cards/388/comments").length > 0, "comments")
})

test("a write is refused rather than pretended", () => {
  let refused = false
  try {
    execFileSync(HELPER, ["--demo", "POST", "/1/cards/388/closure"], { stdio: "pipe" })
  } catch (error) {
    refused = true
  }
  ok(refused, "--demo must refuse writes")
})

// ------------------------------------------------------- the shapes QML reads

test("CardRow.qml reads: number, title, column, tags, assignees, last_active_at", () => {
  for (const card of cards()) {
    ok(typeof card.number === "number", "number on " + card.id)
    ok(typeof card.title === "string" && card.title.length > 0, "title on #" + card.number)
    ok(Array.isArray(card.assignees), "assignees on #" + card.number)
    ok(Array.isArray(card.tags), "tags on #" + card.number)
    ok(!isNaN(Date.parse(card.last_active_at)), "last_active_at on #" + card.number)
    ok(card.column === null || typeof card.column.id === "string", "column on #" + card.number)
  }
})

test("CardPage.qml reads step.content, not step.title", () => {
  const steps = get("/1/cards/388").steps
  ok(steps.length > 0, "the showcase card should have steps")
  for (const step of steps) {
    ok(typeof step.content === "string" && step.content.length > 0, "step content")
    ok(typeof step.completed === "boolean", "step completed")
  }
})

test("CardPage.qml reads comment.creator and a body it can render", () => {
  for (const comment of get("/1/cards/388/comments")) {
    ok(comment.creator && comment.creator.name, "comment creator")
    ok(comment.body && (comment.body.html || comment.body.plain_text), "comment body")
    ok(!isNaN(Date.parse(comment.created_at)), "comment created_at")
  }
})

test("Model.columnColor reads column.color.value as a CSS variable", () => {
  for (const column of get("/1/boards/" + BOARD + "/columns"))
    ok(/^var\(--color-card-\w+\)$/.test(column.color.value), column.name + " colour")
})

// ------------------------------------------------- what the fixtures are for

test("timestamps are relative to now, so the images never age", () => {
  const newest = cards()
    .map((card) => Date.parse(card.last_active_at))
    .sort((a, b) => b - a)[0]
  ok(Date.now() - newest < 60 * 60 * 1000, "the freshest card should read in minutes")
})

test("a card carries more people than the row has seats, so overflow is drawn", () => {
  const crowded = cards().filter((card) => card.assignees.length > 3)
  ok(crowded.length > 0, "expected a card with more than three assignees")
})

test("a card is truncated by the server, so the 'more' seat is drawn too", () => {
  ok(cards().some((card) => card.has_more_assignees === true),
     "expected a card with has_more_assignees")
})

test("nobody in the fixtures has a picture, so no image is ever fetched", () => {
  for (const person of get("/1/users"))
    eq(person.avatar_url, null, person.name + " should have no avatar_url")
  eq(JSON.parse(execFileSync(HELPER, ["--demo", "--avatars"], { encoding: "utf8" })), {})
})

test("no reachable host or address is named in the fixtures", () => {
  const raw = require("fs").readFileSync(
    path.join(__dirname, "..", "fizzy-demo.json"), "utf8")

  // Every host and every address in here has to be reserved for documentation
  // (RFC 2606), so a fixture can never name somebody's instance or mailbox —
  // not the default one either, which is a real service that would then appear
  // in a screenshot as if it were the account being shown.
  for (const url of raw.match(/https?:\/\/[^"\s]+/g) || [])
    ok(/^https?:\/\/fizzy\.example(\/|$)/.test(url), "fixture URL " + url)
  for (const mail of raw.match(/[\w.+-]+@[\w.-]+/g) || [])
    ok(/@example\.com$/.test(mail), "fixture address " + mail)
})

// ----------------------------------------------------------------

if (failures.length > 0) {
  console.error(failures.length + " failed:")
  failures.forEach((line) => console.error("  " + line))
  process.exit(1)
}
console.log(passed + " passed")
