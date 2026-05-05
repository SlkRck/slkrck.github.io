/**
 * Sigma Nu Eta Sigma Chapter — 60th Anniversary Registration
 * Google Sheets Email Trigger
 *
 * This script lives in your Google Sheet (not the Form).
 * Every time a new registration row is added, it emails a copy
 * of all the answers to the registrant's email address and CC's
 * the chapter inboxes.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ONE-TIME SETUP — DO THIS BEFORE RUNNING:
 *
 *   Step 1 — Open this script from the Sheet:
 *     a. Open your Google Sheet that is receiving form responses.
 *     b. Click Extensions → Apps Script.
 *     c. Delete any existing code in the editor.
 *     d. Paste this entire file and save (Ctrl+S / Cmd+S).
 *
 *   Step 2 — Find your email column number:
 *     a. Look at Row 1 of your sheet — those are the column headers.
 *     b. Count left to right to find which column contains "Email Address".
 *        Column A = 1, Column B = 2, Column C = 3, etc.
 *     c. Enter that number below as EMAIL_COLUMN.
 *
 *   Step 3 — Install the trigger:
 *     a. Select "installTrigger" in the function dropdown.
 *     b. Click ▶ Run and approve any permissions asked.
 *     c. Done — the trigger watches the sheet automatically from now on.
 *
 *   Step 4 — Test it:
 *     a. Submit a test entry through your form.
 *     b. Check that the email arrives at the address you entered.
 *     c. Check that contact@sigmanuetasigma.com and your address were CC'd.
 * ─────────────────────────────────────────────────────────────────────────────
 */

// ── CONFIGURATION — fill these in before running ──────────────────────────────

// Which column holds the respondent's email address?
// Count from left: A=1, B=2, C=3 ... find "Email Address" in row 1.
var EMAIL_COLUMN = 5;  // ← change this number if needed

// Your personal notification email
var NOTIFICATION_EMAIL = 'YOUR_EMAIL_ADDRESS_HERE';  // ← fill in

// Chapter email — always CC'd
var CC_EMAIL = 'contact@sigmanuetasigma.com';

// ─────────────────────────────────────────────────────────────────────────────


/**
 * installTrigger — run this ONE TIME to attach the watcher to the sheet.
 * After that, onNewRow fires automatically whenever a new row is added.
 */
function installTrigger() {
  // Remove any old duplicate triggers for this function first
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'onNewRow') {
      ScriptApp.deleteTrigger(triggers[i]);
      Logger.log('Removed old trigger.');
    }
  }

  var sheet = SpreadsheetApp.getActiveSpreadsheet();
  ScriptApp.newTrigger('onNewRow')
           .forSpreadsheet(sheet)
           .onFormSubmit()
           .create();

  Logger.log('SUCCESS: Trigger installed on sheet: ' + sheet.getName());
  Logger.log('Every new form submission will email the registrant automatically.');
  Logger.log('Notification copies go to: ' + NOTIFICATION_EMAIL + ' and ' + CC_EMAIL);
}


/**
 * onNewRow — fires automatically when the sheet receives a new form row.
 * Reads all columns, finds the email address, and sends the registrant
 * a formatted copy of their answers along with payment instructions.
 */
function onNewRow(e) {
  try {
    var sheet  = e.range.getSheet();
    var newRow = e.range.getRow();

    // ── Read headers from row 1 ──────────────────────────────────────────
    var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];

    // ── Read the new response row ────────────────────────────────────────
    var values  = sheet.getRange(newRow, 1, 1, sheet.getLastColumn()).getValues()[0];

    // ── Find the respondent's email ──────────────────────────────────────
    // Primary: use the configured column number
    var respondent = (values[EMAIL_COLUMN - 1] || '').toString().trim();

    // Secondary: scan all columns for anything that looks like an email
    if (!respondent) {
      for (var c = 0; c < values.length; c++) {
        var cell = values[c].toString().trim();
        if (cell.indexOf('@') > 0 && cell.indexOf('.') > 0) {
          respondent = cell;
          Logger.log('Email found by scan in column ' + (c + 1) + ': ' + respondent);
          break;
        }
      }
    }

    // ── Get submission timestamp ─────────────────────────────────────────
    var timestamp = '';
    // Column A in a form-linked sheet is always the timestamp
    if (values[0]) {
      timestamp = Utilities.formatDate(
        new Date(values[0]),
        Session.getScriptTimeZone(),
        'MMMM d, yyyy  h:mm a z'
      );
    }

    // ── Build the answers block ──────────────────────────────────────────
    var answers = '';
    for (var i = 0; i < headers.length; i++) {
      if (!headers[i]) continue;               // skip blank header columns
      var q = headers[i].toString();
      var a = (values[i] !== undefined && values[i] !== null && values[i] !== '')
              ? values[i].toString()
              : '(no answer)';
      answers += 'Q: ' + q + '\n';
      answers += 'A: ' + a + '\n\n';
    }

    var divider = '-------------------------------------------\n';
    var subject = '*60th Registration* — Your Registration Confirmation';

    // ── Payment instructions block ───────────────────────────────────────
    var paymentInfo =
      '===========================================\n' +
      'HOW TO PAY\n' +
      '===========================================\n' +
      'Dues: $50 per person\n' +
      'Celebration fee: $250 per person\n\n' +
      '1. ZELLE\n' +
      '   Search for: sigmanuetasigma  (all lowercase, one word, no spaces)\n' +
      '   In the notes/memo add: "60th Anniversary reg for [your name]"\n' +
      '   or "2026 dues for [your name]"\n\n' +
      '2. ETF — Wells Fargo\n' +
      '   Routing: 111900659  |  Account: 5445278160\n' +
      '   Include your name and payment purpose in the memo field.\n\n' +
      '3. MAIL A CHECK to:\n' +
      '   Sigma Nu - Eta Sigma\n' +
      '   ENMU - Sta. 4343\n' +
      '   1500 S. Ave. K\n' +
      '   Portales, NM 88130\n' +
      '   (Do NOT use PO Box in the address)\n' +
      '   Write your name and payment purpose on the memo line.\n\n' +
      'If you or a brother you know are finding it difficult to afford the 60th Anniversary Celebration,\n' +
      'email contact@sigmanuetasigma.com to see if you qualify for a scholarship.\n' +
      'Several brothers have made scholarship money available to help fellow SNs.\n\n' +
      'Questions? Email contact@sigmanuetasigma.com\n';

    // ── Send to respondent ───────────────────────────────────────────────
    if (respondent) {
      var body =
        'Thank you for registering for the Sigma Nu Eta Sigma Chapter\n' +
        '60th Anniversary Celebration — July 9-12, 2026\n' +
        'Santa Ana Star Casino Hotel, Bernalillo, New Mexico\n\n' +
        'Here is a copy of your completed registration:\n\n' +
        divider +
        (timestamp ? 'Submitted: ' + timestamp + '\n\n' : '') +
        answers +
        divider +
        paymentInfo;

      MailApp.sendEmail({
        to:      respondent,
        cc:      NOTIFICATION_EMAIL + ',' + CC_EMAIL,
        subject: subject,
        body:    body
      });

      Logger.log('Email sent TO: ' + respondent + ' | CC: ' + NOTIFICATION_EMAIL + ', ' + CC_EMAIL);

    } else {
      // No email found — alert chapter addresses so someone can follow up
      var alertBody =
        '===========================================\n' +
        '  *60th Registration* — New Submission\n' +
        '  WARNING: No email address found in row ' + newRow + '.\n' +
        '  Please follow up with this registrant manually.\n' +
        '===========================================\n\n' +
        (timestamp ? 'Submitted: ' + timestamp + '\n\n' : '') +
        answers +
        divider +
        'Sigma Nu Eta Sigma Chapter — Automated notification\n';

      MailApp.sendEmail({
        to:      NOTIFICATION_EMAIL,
        cc:      CC_EMAIL,
        subject: '*60th Registration* — New Submission — NO EMAIL FOUND (Row ' + newRow + ')',
        body:    alertBody
      });

      Logger.log('WARNING: No email found in row ' + newRow + '. Alert sent to chapter addresses.');
    }

  } catch (err) {
    // Log the error but never let it block a submission from being recorded
    Logger.log('ERROR in onNewRow (row ' + (e.range ? e.range.getRow() : '?') + '): ' + err);
  }
}


/**
 * findEmailColumn — run this as a helper if you are not sure which
 * column number to use for EMAIL_COLUMN above.
 * It prints the column number of every header containing "email".
 */
function findEmailColumn() {
  var sheet   = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  Logger.log('Column headers in this sheet:');
  for (var i = 0; i < headers.length; i++) {
    Logger.log('  Column ' + (i + 1) + ' ('+String.fromCharCode(65+i)+'): ' + headers[i]);
    if (headers[i].toString().toLowerCase().indexOf('email') >= 0) {
      Logger.log('  ^^^ THIS looks like your email column. Set EMAIL_COLUMN = ' + (i + 1));
    }
  }
}