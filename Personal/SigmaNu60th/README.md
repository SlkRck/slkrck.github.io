# Sigma Nu 60th Anniversary — Google Form Automation

This repository contains a Google Apps Script that automatically builds the
**60th Anniversary Celebration Registration** Google Form for the Sigma Nu
Eta Sigma Chapter.

---

## What it does

Running the script creates a fully configured Google Form with:

- **8 guided sections** (one step at a time, easy for any skill level)
- All event questions for July 9–12, 2026
- Attendance count dropdowns for each event
- Dues, event payment, and donation questions
- Email collection so registrants receive a copy of their answers
- A confirmation message with payment reminders

---

## Files

| File | Purpose |
|------|---------|
| `createForm.gs` | Main Apps Script — paste this into Google Apps Script to build the form |
| `README.md` | This file |

---

## How to run

### Step 1 — Open Google Apps Script

Go to [https://script.google.com](https://script.google.com) and sign in
with the Google account that should own the form.

### Step 2 — Create a new project

Click **New project** (top left).

### Step 3 — Paste the script

1. Delete any starter code in the editor.
2. Open `createForm.gs` from this repo.
3. Copy the entire contents.
4. Paste into the Apps Script editor.
5. Press **Ctrl+S** (Windows) or **Cmd+S** (Mac) to save.

### Step 4 — Run the script

1. In the toolbar dropdown, make sure **buildForm** is selected.
2. Click the **▶ Run** button.
3. Google will ask you to approve permissions — click **Review permissions**,
   choose your account, and click **Allow**.
4. Wait ~10 seconds for the script to finish.

### Step 5 — Get your form URL

After the script finishes, click **Execution log** at the bottom of the screen.
You will see two URLs:

- **Form URL** — the public link to share with members
- **Edit URL** — your private editor link to make changes

---

## Events covered

| Day | Event | Cost |
|-----|-------|------|
| Thursday July 9 | Welcome Event — Terrazza Overlook, 6 PM | Included |
| Friday July 10 | ENMU Alumni Scholarship Golf Tournament | Separate |
| Friday July 10 | Balloon Museum Outing + El Pinto lunch | Included |
| Friday July 10 | ENMU Alumni Mixer, 7 PM hotel ballroom | Separate |
| Saturday July 11 | Sigma Nu Golf Outing — Santa Ana Golf Club | Pay at course |
| Saturday July 11 | Champagne Breakfast, 8:30 AM Hospitality Suite | Included |
| Saturday July 11 | Indian Pueblo Cultural Center outing | Included |
| Saturday July 11 | Main Banquet — 5:30 PM cocktails / 6:30 PM dinner | Included |
| Sunday July 12 | Farewell Breakfast & Annual Chapter Meeting, 10 AM | Included |

---

## After the form is live — recommended checks

- [ ] Fill out the form yourself from start to finish
- [ ] Confirm all dates, times, and locations look correct
- [ ] Confirm a confirmation email is sent after Submit
- [ ] Update "XYZ Room" on the Main Banquet and Farewell Breakfast questions
       once the actual room name is confirmed with the hotel
- [ ] Share the form URL in the Facebook Event and Facebook Posts

---

## Notes

- The script uses the **Google Forms API via Apps Script** — no API key required.
- The form is created in the Google Drive of whichever account runs the script.
- To re-run and create a fresh form, just run `buildForm` again (it always creates a new form).

---

*Prepared for Sigma Nu Eta Sigma Chapter — 60th Anniversary Celebration, July 9–12, 2026*
