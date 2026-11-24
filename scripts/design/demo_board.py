#!/usr/bin/env python3
"""Writes a demo board.json that exercises every card feature.
usage: demo_board.py <dir> full|empty|corrupt|newer"""
import json, os, sys, uuid, datetime as dt
d, kind = sys.argv[1], sys.argv[2]
os.makedirs(d, exist_ok=True)
now = dt.datetime.now(dt.timezone.utc)
today = dt.date.today()
iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%S.") + f"{t.microsecond // 1000:03d}Z"
day = lambda n: (today + dt.timedelta(days=n)).isoformat()
cards, idx = [], {}
def card(title, column, priority="none", category="", next_step="", waiting="", start=None, due=None, done_days_ago=None, archived=False):
    idx[column] = idx.get(column, 0) + 1
    completed = iso(now - dt.timedelta(days=done_days_ago)) if done_days_ago is not None else None
    c = {"id": str(uuid.uuid4()).upper(), "title": title, "nextStep": next_step, "waitingOn": waiting, "category": category,
         "priority": priority, "column": column, "sortIndex": idx[column], "createdAt": iso(now - dt.timedelta(days=5)),
         "updatedAt": completed or iso(now), "isArchived": archived}
    if start: c["startDate"] = start
    if due: c["dueDate"] = due
    if completed: c["completedAt"] = completed
    cards.append(c)
if kind in ("full", "corrupt", "newer"):
    card("Post infographic on LinkedIn", "todo", "medium", "LinkedIn", "Design + caption, then post")
    card("Recruiter calling — past recruiters' HRs", "todo", "high", "Recruiter outreach", "Invite HRs of past-year recruiters to campus for summer internships", start=day(2))
    card("Update CV with SIP project", "todo", "low", "Prep", due=day(4))
    card("Shortlist 20 target companies", "todo", category="Research")
    card("पूर्व छात्रों को फ़ोन करें 🎯", "todo", "medium", "Alumni")
    card("A deliberately long task title to show how cards wrap at three lines and then truncate with an ellipsis so the layout never breaks, even when someone pastes a whole sentence or two into the composer box", "todo")
    card("Complete SIP brochure", "inProgress", "high", "Brochure", "Alumni page still pending (rest is done)", due=day(0))
    card("Mock interview with two seniors", "inProgress", "medium", "Prep", "Book a slot", due=day(1))
    card("Draft pitch email for recruiters", "inProgress", "high", "Recruiter outreach", due=day(-2))
    card("Finalise alumni contact list", "inProgress", "low", "Alumni")
    card("Brochure sign-off from committee", "onHold", "medium", "Brochure", waiting="Placement committee")
    card("Alumni database access", "onHold", "low", "Alumni", waiting="IT office", due=day(9))
    card("Shortlist companies", "done", "medium", "Research", done_days_ago=0)
    card("Polish LinkedIn headline", "done", "low", "LinkedIn", done_days_ago=3)
    card("Collect last year's placement report", "done", done_days_ago=20, archived=True)
    card("Register on the placement portal", "done", "high", done_days_ago=30, archived=True)
board = {"schemaVersion": 2 if kind == "newer" else 1, "cards": cards,
         "settings": {"wipLimit": 3, "archiveAfterDays": 14, "showSummaryStrip": True}}
text = json.dumps(board, indent=2, ensure_ascii=False)
if kind == "corrupt":
    os.makedirs(os.path.join(d, "backups"), exist_ok=True)
    stamp = (dt.datetime.now() - dt.timedelta(minutes=25)).strftime("%Y-%m-%dT%H-%M-%S")
    open(os.path.join(d, "backups", f"board-{stamp}.json"), "w").write(text)
    text = '{"schemaVersion": 1, "cards": [ {"id": oops'
if kind != "seed":
    open(os.path.join(d, "board.json"), "w").write(text)
