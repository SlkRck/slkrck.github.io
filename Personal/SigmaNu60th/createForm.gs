/**
 * Sigma Nu Eta Sigma Chapter
 * 60th Anniversary Celebration — Google Form Builder
 *
 * HOW TO RUN:
 *   1. Go to https://script.google.com and create a New Project.
 *   2. Delete any existing code in the editor.
 *   3. Paste this entire file into the editor.
 *   4. Click the Save icon (or Ctrl+S / Cmd+S).
 *   5. Select the function "buildForm" from the function dropdown at the top.
 *   6. Click ▶ Run.
 *   7. Approve any permissions Google asks for (it needs access to Forms & Drive).
 *   8. When it finishes, check the Execution Log at the bottom — it will print
 *      the live URL of your new form.
 */

function buildForm() {

  // ── Create the form ──────────────────────────────────────────────────────
  var form = FormApp.create('60th Anniversary Celebration Registration');
  form.setTitle('60th Anniversary Celebration Registration');
  form.setDescription(
    'Welcome!\n\n' +
    'This form will help you register for the 60th Anniversary Celebration, July 9–12, 2026.\n\n' +
    'Please go one step at a time. The form is simple and should only take a few minutes.\n\n' +
    'Before you begin:\n' +
    '• Please have your contact information ready\n' +
    '• If you are bringing guests, please have their names ready\n' +
    '• Some activities are included in the event cost, and some are separate\n' +
    '• If you still owe your 2026 dues of $50, please note that before registering\n' +
    '• At the end of the form, you will see payment and donation questions\n\n' +
    'Important:\n' +
    'When you finish, click Submit at the bottom of the form. ' +
    'A copy of your answers will be sent to your email.'
  );

  // Collect email so respondents receive a copy
  form.setCollectEmail(true);
  form.setConfirmationMessage(
    'Thank you for registering for the 60th Anniversary Celebration!\n\n' +
    'Your form has been submitted successfully.\n\n' +
    'A copy of your answers will be sent to your email address.\n\n' +
    'Please remember to follow the payment instructions listed in the Facebook Event and Facebook Posts.'
  );

  // Use sections (pages) so the form is presented one step at a time
  form.setProgressBar(true);

  // ── SECTION 1 — Contact Information ────────────────────────────────────
  var sec1 = form.addPageBreakItem();
  sec1.setTitle('Step 1 of 8 — Tell Us About Yourself');
  sec1.setHelpText(
    'Please enter your contact information below.\n' +
    'This helps us know who is registering and how to reach you if needed.\n' +
    'Please answer each question carefully.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  form.addTextItem()
      .setTitle('First Name')
      .setRequired(true);

  form.addTextItem()
      .setTitle('Last Name')
      .setRequired(true);

  form.addTextItem()
      .setTitle('Phone Number')
      .setRequired(true);

  form.addTextItem()
      .setTitle('Email Address')
      .setRequired(true);

  form.addTextItem()
      .setTitle('Mailing Address')
      .setRequired(true);

  // ── SECTION 2 — Guests ──────────────────────────────────────────────────
  var sec2 = form.addPageBreakItem();
  sec2.setTitle('Step 2 of 8 — Who Is Coming With You?');
  sec2.setHelpText(
    'Please tell us whether you are coming alone or bringing guests.\n' +
    'If you are bringing guests, enter their names below.\n' +
    'If you are not bringing guests, you may leave the guest name boxes blank.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('How many people are included in this registration?')
      .setChoiceValues(['Just me', 'Me and 1 guest', 'Me and 2 guests'])
      .setRequired(true);

  form.addTextItem()
      .setTitle('Guest #1 First Name')
      .setHelpText('Leave blank if this does not apply to you.');

  form.addTextItem()
      .setTitle('Guest #1 Last Name')
      .setHelpText('Leave blank if this does not apply to you.');

  form.addTextItem()
      .setTitle('Guest #2 First Name')
      .setHelpText('Leave blank if this does not apply to you.');

  form.addTextItem()
      .setTitle('Guest #2 Last Name')
      .setHelpText('Leave blank if this does not apply to you.');

  // ── SECTION 3 — Thursday Welcome Event ─────────────────────────────────
  var sec3 = form.addPageBreakItem();
  sec3.setTitle('Step 3 of 8 — Thursday Welcome Event');
  sec3.setHelpText(
    'Please tell us if you plan to attend the welcome event.\n\n' +
    'Event details:\n' +
    'Thursday, July 9, 2026 — 6:00 PM\n' +
    'Terrazza Overlook, 2nd Floor\n\n' +
    'This event is INCLUDED in the event cost.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Thursday welcome event?')
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend this event?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Include yourself and any guests.');

  // ── SECTION 4 — Friday Activities ──────────────────────────────────────
  var sec4 = form.addPageBreakItem();
  sec4.setTitle('Step 4 of 8 — Friday Activities (July 10, 2026)');
  sec4.setHelpText(
    'This section asks about Friday activities.\n' +
    'Please answer each question carefully.\n\n' +
    'Some Friday activities are part of the celebration, and some are SEPARATE from the Sigma Nu event cost.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  // ENMU Golf Tournament
  form.addMultipleChoiceItem()
      .setTitle('Are you or your guest(s) on a golf team playing in the ENMU Alumni Scholarship Tournament?')
      .setHelpText(
        'Friday, July 10, 2026. Registration begins at 6:00 AM. Tee time is 8:00 AM.\n' +
        '⚠ This is SEPARATE from the Sigma Nu event — cost is handled outside this form.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  // Balloon Museum
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Balloon Museum outing?')
      .setHelpText(
        'Friday, July 10, 2026. Depart hotel at 9:30 AM.\n' +
        'Lunch at 12:00 Noon at El Pinto Restaurant (10500 4th St. NW) — Dutch treat.\n' +
        '✅ This outing is INCLUDED in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Balloon Museum outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ENMU Alumni Mixer
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the ENMU Alumni Mixer?')
      .setHelpText(
        'Friday evening, July 10, 2026 — 7:00 PM, hotel ballroom.\n' +
        'Appetizers provided by ENMU. Cash bar. Reserved tables for Sigma Nu.\n' +
        '⚠ This is SEPARATE from the Sigma Nu event.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the ENMU Alumni Mixer?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 5 — Saturday Activities ────────────────────────────────────
  var sec5 = form.addPageBreakItem();
  sec5.setTitle('Step 5 of 8 — Saturday Activities (July 11, 2026)');
  sec5.setHelpText(
    'This section asks about Saturday activities.\n' +
    'Please answer each item, even if your answer is No.\n\n' +
    'Some events are included in the celebration cost, and some require payment at the location.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  // Sigma Nu Golf Outing
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) play in the Sigma Nu golf outing?')
      .setHelpText(
        'Saturday, July 11, 2026 — Santa Ana Golf Club.\n' +
        'First tee time 9:50 AM, last tee time 10:30 AM.\n' +
        'Cost: $71 if under age 55 / $62 if age 55 or older — Pay at the course.\n' +
        '⚠ Limited to the first 20 players. Pay at the course.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will play in the Sigma Nu golf outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // Champagne Breakfast
  form.addMultipleChoiceItem()
      .setTitle('Will a Sweetheart, Little Sister, Spouse, or Partner attend the Champagne Breakfast?')
      .setHelpText(
        'Saturday, July 11, 2026 — 8:30 AM, Hospitality Suite.\n' +
        '✅ Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  // Indian Pueblo Cultural Center
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Indian Pueblo Cultural Center outing?')
      .setHelpText(
        'Saturday, July 11, 2026. Depart hotel at 10:15 AM.\n' +
        'Lunch at the Pueblo Culture Restaurant — Dutch treat.\n' +
        '✅ Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Indian Pueblo Cultural Center outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // Main Banquet
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Main Banquet?')
      .setHelpText(
        'Saturday evening, July 11, 2026 — XYZ Room.\n' +
        'Appetizers and cocktails begin at 5:30 PM. Dinner and program begin at 6:30 PM.\n' +
        '✅ Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Main Banquet?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 6 — Sunday Farewell Breakfast ──────────────────────────────
  var sec6 = form.addPageBreakItem();
  sec6.setTitle('Step 6 of 8 — Sunday Farewell Breakfast (July 12, 2026)');
  sec6.setHelpText(
    'Please tell us if you will attend the farewell breakfast and annual chapter meeting.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Farewell Breakfast and Annual Chapter Meeting?')
      .setHelpText(
        'Sunday, July 12, 2026 — 10:00 AM, XYZ Room.\n' +
        '✅ Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Farewell Breakfast?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 7 — Dues, Payment, and Donation ────────────────────────────
  var sec7 = form.addPageBreakItem();
  sec7.setTitle('Step 7 of 8 — Dues, Event Payment, and Donation');
  sec7.setHelpText(
    'This section is about money owed, event payment, and an optional donation.\n' +
    'Please answer each question carefully.\n\n' +
    'When you are done with this page, click Next at the bottom to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Do you still need to pay your 2026 dues of $50 before registering?')
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people are you paying the 60th Anniversary Celebration fee for?')
      .setChoiceValues(['1', '2', '3'])
      .setHelpText('The celebration cost is $250 per person.')
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('Would you like to make a donation to our Community Service project?')
      .setHelpText('St. Felix Food Pantry of Rio Rancho / Sandoval County.')
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addTextItem()
      .setTitle('If yes, please enter your donation amount (example: 25)')
      .setHelpText('Leave blank if you answered No above. Enter numbers only, no $ sign needed.');

  form.addSectionHeaderItem()
      .setTitle('Payment Instructions')
      .setHelpText(
        'Please follow the payment instructions listed in the Facebook Event and Facebook Posts.\n' +
        'Payment for the celebration ($250/person) and dues ($50) should be submitted there.'
      );

  // ── SECTION 8 — Notes ───────────────────────────────────────────────────
  var sec8 = form.addPageBreakItem();
  sec8.setTitle('Step 8 of 8 — Final Notes');
  sec8.setHelpText(
    'If you have any comments, special notes, or anything you would like us to know, please enter that below.\n\n' +
    'When you are done, click Submit at the bottom of the form.'
  );

  form.addParagraphTextItem()
      .setTitle('Note / Comment')
      .setHelpText('Leave blank if you have nothing to add.');

  // ── Done — log the URL ──────────────────────────────────────────────────
  var url = form.getPublishedUrl();
  Logger.log('✅ Form created successfully!');
  Logger.log('📋 Form URL (share this link): ' + url);
  Logger.log('✏️  Edit URL (your editor link): ' + form.getEditUrl());

  // Also show a popup in the Apps Script editor
  SpreadsheetApp.getUi && SpreadsheetApp.getUi().alert(
    'Form created! Share this URL:\n\n' + url
  );
}
