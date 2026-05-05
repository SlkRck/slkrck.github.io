/**
 * Sigma Nu Eta Sigma Chapter
 * 60th Anniversary Celebration — Google Form Builder
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * BEFORE YOU RUN — ADD THE FLYER IMAGE (one-time setup, takes ~2 minutes):
 *
 *   1. Upload "Event_Schedule_v4.jpg" to your Google Drive.
 *   2. Right-click the file → "Get link" → set to "Anyone with the link can view"
 *      → copy the link.
 *   3. The link looks like:
 *        https://drive.google.com/file/d/XXXXXXXXXXXXXXXXXXXXXXXXX/view
 *   4. Copy ONLY the long ID between /d/ and /view  — that is your File ID.
 *   5. Paste it below, replacing  YOUR_DRIVE_FILE_ID_HERE
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * HOW TO RUN — TWO STEPS:
 *
 *   STEP 1 — Build the form:
 *   1. Go to https://script.google.com and create a New Project.
 *   2. Delete any existing code in the editor.
 *   3. Paste this entire file into the editor and save (Ctrl+S / Cmd+S).
 *   4. Fill in FLYER_FILE_ID and NOTIFICATION_EMAIL at the top of the script.
 *   5. Select buildForm in the function dropdown and click ▶ Run.
 *   6. Approve any permissions Google asks for.
 *   7. The Execution Log will print your live form URL when done.
 *
 *   STEP 2 — Install the email notification trigger (run ONCE after Step 1):
 *   1. Select setupTrigger in the function dropdown and click ▶ Run.
 *   2. Approve any additional permissions if asked.
 *   3. Done — every future submission will email NOTIFICATION_EMAIL automatically.
 * ─────────────────────────────────────────────────────────────────────────────
 */

// ── PASTE YOUR GOOGLE DRIVE FILE ID HERE ─────────────────────────────────────
var FLYER_FILE_ID = 'YOUR_DRIVE_FILE_ID_HERE';
// ─────────────────────────────────────────────────────────────────────────────

// ── EMAIL ADDRESS TO RECEIVE EVERY COMPLETED REGISTRATION ────────────────────
var NOTIFICATION_EMAIL = 'YOUR_EMAIL_ADDRESS_HERE';
// ─────────────────────────────────────────────────────────────────────────────

// ── CHAPTER EMAIL — CC'D ON EVERY SUBMISSION ─────────────────────────────────
var CC_EMAIL = 'contact@sigmanuetasigma.com';
// ─────────────────────────────────────────────────────────────────────────────

function buildForm() {

  // ── Create the form ──────────────────────────────────────────────────────
  var form = FormApp.create('*60th Registration*');
  form.setTitle('*60th Registration*');
  form.setDescription(
    'Sigma Nu Eta Sigma Chapter — 60th Anniversary Celebration\n' +
    'July 9–12, 2026  |  Santa Ana Star Casino Hotel  |  Bernalillo, New Mexico\n\n' +
    'Welcome! This form will register you and your guest(s) for the celebration.\n' +
    'Please go one step at a time — it should only take a few minutes.\n\n' +
    'Before you begin:\n' +
    '• Please have your contact information ready\n' +
    '• If you are bringing guests, please have their names ready\n' +
    '• The Hospitality Suite is open daily 8 AM to 10 PM+ with complimentary\n' +
    '  soft drinks, beer, wine, and snacks — it opens at 3 PM on Thursday\n' +
    '• Some activities are included in the event cost; some are separate\n' +
    '• If you still owe your 2026 dues of $50, you will be asked about that\n' +
    '• There is also an opportunity to support the SN Food Drive for St. Felix Pantry\n\n' +
    'When you finish, click Submit. A copy of your answers will be sent to your email.'
  );

  form.setCollectEmail(true);
  form.setConfirmationMessage(
    'Thank you for registering for the 60th Anniversary Celebration!\n\n' +
    'Your registration has been submitted successfully.\n' +
    'A copy of your answers has been sent to your email address.\n\n' +
    '─────────────────────────────────\n' +
    'HOW TO PAY\n' +
    '─────────────────────────────────\n' +
    'Dues: $50 per person\n' +
    'Celebration fee: $250 per person\n\n' +
    '1. ZELLE — Search for "sigmanuetasigma" (all lowercase, one word, no spaces) in your bank app.\n' +
    '   When sending payment, add a note such as: "60th Anniversary registration for [your name]"\n' +
    '   or "2026 dues for [your name]" so we can match your payment.\n\n' +
    '2. ETF (Wells Fargo) — Routing: 111900659 / Account: 5445278160\n' +
    '   Please include your name and what the payment is for in the memo/notes field.\n\n' +
    '3. MAIL A CHECK to:\n' +
    '   Sigma Nu - Eta Sigma\n' +
    '   ENMU - Sta. 4343\n' +
    '   1500 S. Ave. K\n' +
    '   Portales, NM 88130\n' +
    '   (Do NOT use PO Box in the address)\n' +
    '   Please write your name and payment purpose on the memo line of the check.\n\n' +
    'Questions? Email contact@sigmanuetasigma.com\n\n' +
    'We look forward to seeing you July 9-12, 2026 at the Santa Ana Star Casino Hotel!'
  );

  form.setProgressBar(true);

  // ── FLYER IMAGE — shown at the top of the form ────────────────────────────
  if (FLYER_FILE_ID !== 'YOUR_DRIVE_FILE_ID_HERE') {
    try {
      var flyerBlob = DriveApp.getFileById(FLYER_FILE_ID).getBlob();
      form.addImageItem()
          .setImage(flyerBlob)
          .setTitle('Schedule of Events')
          .setHelpText('Full schedule — July 9-12, 2026, Santa Ana Star Casino Hotel, Bernalillo, NM');
    } catch (e) {
      Logger.log('WARNING: Could not load flyer image. Check FLYER_FILE_ID and file sharing. Error: ' + e);
    }
  } else {
    Logger.log('INFO: Flyer image skipped. Paste your Drive File ID into FLYER_FILE_ID at the top to include it.');
  }

  // ── SECTION 1 — Contact Information ────────────────────────────────────
  var sec1 = form.addPageBreakItem();
  sec1.setTitle('Step 1 of 8 — Tell Us About Yourself');
  sec1.setHelpText(
    'Please enter your contact information below.\n' +
    'This helps us know who is registering and how to reach you.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  form.addTextItem().setTitle('First Name').setRequired(true);
  form.addTextItem().setTitle('Last Name').setRequired(true);
  form.addTextItem().setTitle('Phone Number').setRequired(true);
  form.addTextItem().setTitle('Email Address').setRequired(true);
  form.addTextItem().setTitle('Mailing Address').setRequired(true);

  // ── SECTION 2 — Guests ──────────────────────────────────────────────────
  var sec2 = form.addPageBreakItem();
  sec2.setTitle('Step 2 of 8 — Who Is Coming With You?');
  sec2.setHelpText(
    'Please tell us whether you are coming alone or bringing guests.\n' +
    'If you are not bringing guests, leave the guest name boxes blank.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('How many people are included in this registration?')
      .setChoiceValues(['Just me', 'Me and 1 guest', 'Me and 2 guests'])
      .setRequired(true);

  form.addTextItem().setTitle('Guest #1 First Name').setHelpText('Leave blank if this does not apply to you.');
  form.addTextItem().setTitle('Guest #1 Last Name').setHelpText('Leave blank if this does not apply to you.');
  form.addTextItem().setTitle('Guest #2 First Name').setHelpText('Leave blank if this does not apply to you.');
  form.addTextItem().setTitle('Guest #2 Last Name').setHelpText('Leave blank if this does not apply to you.');

  // ── SECTION 3 — Thursday Welcome Reception ─────────────────────────────
  var sec3 = form.addPageBreakItem();
  sec3.setTitle('Step 3 of 8 — Thursday Welcome Reception (July 9)');
  sec3.setHelpText(
    'Thursday, July 9, 2026 — 6:00 PM\n' +
    'La Terraza Overlook, 2nd Floor Lobby\n\n' +
    'Pizza, Sliders, Wings, Desserts & Open Bar.\n' +
    'Visit with your Brothers and Sisters!\n\n' +
    'Note: Our private Hospitality Suite opens at 3:00 PM today and will be open late\n' +
    'after the reception with complimentary soft drinks, beer, wine, and snacks.\n' +
    'The suite is open daily 8 AM to 10 PM+ throughout the weekend.\n\n' +
    'This event is INCLUDED in the event cost.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Thursday Welcome Reception?')
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Welcome Reception?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Include yourself and any guests. Leave at 0 if you answered No above.');

  // ── SECTION 4 — Friday Activities ──────────────────────────────────────
  var sec4 = form.addPageBreakItem();
  sec4.setTitle('Step 4 of 8 — Friday Activities (July 10)');
  sec4.setHelpText(
    'This section covers Friday activities.\n' +
    'Some are included in the event cost; some require separate registration or payment.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  // ENMU Golf Tournament
  form.addMultipleChoiceItem()
      .setTitle('Are you or your guest(s) registered to play in the ENMU Alumni Scholarship Golf Tournament?')
      .setHelpText(
        'Friday, July 10, 2026\n' +
        'Registration opens at 6:00 AM. Tee time: 8:00 AM.\n' +
        'Box lunch is provided with the registration fee.\n' +
        'WARNING: You must register by May 29th.\n' +
        'Scan the QR code on the event flyer for information and registration.\n\n' +
        'This tournament is SEPARATE from the Sigma Nu event.\n' +
        'Cost and registration are handled outside this form.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  // Balloon Museum
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Balloon Museum guided tour and lunch at El Pinto?')
      .setHelpText(
        'Friday, July 10, 2026\n' +
        'Depart hotel lobby at 9:30 AM.\n' +
        'Guided tour: 10:00 AM to 11:30 AM, followed by 30 minutes free time to explore.\n' +
        '12:00 Noon: Depart for El Pinto Restaurant — reservation at 12:30 PM.\n' +
        'Lunch is Dutch treat.\n\n' +
        'The guided tour outing is INCLUDED in the event cost. Lunch is on your own.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Balloon Museum outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ENMU Mix and Mingle
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the ENMU Mix and Mingle?')
      .setHelpText(
        'Friday evening, July 10, 2026 — 7:00 PM to 9:00 PM\n' +
        'Sandia Resort & Casino\n' +
        'Eagle Mountain Terrace View Room\n' +
        '30 Rainbow Rd, Albuquerque, NM 87113\n' +
        '(Look for our reserved tables)\n\n' +
        'Appetizers provided by ENMU. Cash bar.\n' +
        'See old friends from Eastern, meet new ones, and enjoy the company of your Brothers and Sisters.\n' +
        'The Hospitality Suite at Santa Ana will be open after the event.\n\n' +
        'While this event is hosted by ENMU, Sigma Nu Eta Sigma considers it part of our 60th Celebration activities.\n' +
        'You must register your attendance through the ENMU Alumni Events page at:\n' +
        'https://giving.enmu.edu/e/enmu-july-mix-and-mingle/'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the ENMU Mix and Mingle?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // GGAS — Friday
  form.addMultipleChoiceItem()
      .setTitle('GGAS (Friday) — Will anyone in this registration participate in Gambling, Games and Socializing on Friday?')
      .setHelpText(
        'GGAS = Gambling, Games and Socializing!\n' +
        'For those not interested in golf or the planned outings, gather in the Hospitality Suite\n' +
        'during outing time and play the games you love — or head to the casino.\n' +
        'Sign up during the Welcome Reception Thursday night, or just show up.\n' +
        'The hotel also has a pool, gym, and bowling alley.\n' +
        'Have lunch together at one of the hotel restaurants.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will participate in GGAS on Friday?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 5 — Saturday Activities ────────────────────────────────────
  var sec5 = form.addPageBreakItem();
  sec5.setTitle('Step 5 of 8 — Saturday Activities (July 11)');
  sec5.setHelpText(
    'This section covers Saturday activities.\n' +
    'Please answer each question, even if your answer is No.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  // Sigma Nu Golf Outing
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) play in the SN Golf Outing at Santa Ana Golf Club?')
      .setHelpText(
        'Saturday, July 11, 2026\n' +
        'We have 5 tee times for 20 golfers.\n' +
        'First tee time: 9:50 AM — Last tee time: 10:30 AM.\n' +
        'Please be there NO LESS than 30 minutes early.\n' +
        'Cost: $71 per person (under age 55) / $62 per person (age 55 or older).\n' +
        'Pay at the course.\n\n' +
        'Golf is NOT included in the event cost. Limited to the first 20 players.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will play in the SN Golf Outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // Champagne Breakfast
  form.addMultipleChoiceItem()
      .setTitle('Will a Sweetheart, Little Sister, Spouse, or Partner attend the Champagne Breakfast?')
      .setHelpText(
        'Saturday, July 11, 2026 — 9:00 AM, Hospitality Suite\n' +
        'A light breakfast of pastries, breakfast sandwiches, and fruit will be served,\n' +
        'accompanied by champagne with juices for mimosas.\n' +
        'No Brothers allowed!\n\n' +
        'Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Champagne Breakfast?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // Indian Pueblo Cultural Center
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Indian Pueblo Cultural Center private guided tour and lunch?')
      .setHelpText(
        'Saturday, July 11, 2026\n' +
        'Depart hotel at 10:15 AM.\n' +
        'Docent-led tour begins at 10:45 AM, followed by free time to explore and visit Indian artisans.\n' +
        'Catch the Indian Dancers — usually scheduled 12 Noon to 1:00 PM.\n' +
        'Lunch at the on-site restaurant at 1:00 PM. Return to hotel at 2:00 PM.\n' +
        'Lunch is Dutch treat.\n\n' +
        'The guided tour outing is INCLUDED in the event cost. Lunch is on your own.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Indian Pueblo Cultural Center outing?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // GGAS — Saturday
  form.addMultipleChoiceItem()
      .setTitle('GGAS (Saturday) — Will anyone in this registration participate in Gambling, Games and Socializing on Saturday?')
      .setHelpText(
        'GGAS = Gambling, Games and Socializing!\n' +
        'For those not interested in golf or the planned outings, gather in the Hospitality Suite\n' +
        'during outing time and play the games you love — or head to the casino.\n' +
        'Sign up during the Welcome Reception Thursday night, or just show up.\n' +
        'The hotel also has a pool, gym, and bowling alley.\n' +
        'Have lunch together at one of the hotel restaurants.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will participate in GGAS on Saturday?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // Main Banquet
  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the 60th Anniversary Celebration Banquet and Presentation?')
      .setHelpText(
        'Saturday evening, July 11, 2026 — Sacramento Room\n' +
        'We gather at 6:00 PM for appetizers and cocktails at the open bar.\n' +
        'We will then move to the dining room for a triple entree banquet with double desserts.\n' +
        'Complimentary wine service during dinner; the bar will remain open.\n' +
        'We will recognize Brothers and Sisters who have gone to Chapter Eternal since our 50th Celebration.\n\n' +
        'Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Banquet and Presentation?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 6 — Sunday Farewell Brunch ─────────────────────────────────
  var sec6 = form.addPageBreakItem();
  sec6.setTitle('Step 6 of 8 — Sunday Farewell Brunch (July 12)');
  sec6.setHelpText(
    'Please tell us if you will attend the farewell brunch and annual chapter meeting.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Will you or your guest(s) attend the Farewell Brunch and Annual Alumni Chapter Meeting?')
      .setHelpText(
        'Sunday, July 12, 2026 — 10:00 AM, Tularosa Room\n' +
        'A New Mexican brunch will be served.\n' +
        'Annual meeting with election of officers.\n' +
        "Don't say goodbye — say until we meet again!\n" +
        'Remember: Hotel checkout time is 11:00 AM.\n\n' +
        'Included in the event cost.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people will attend the Farewell Brunch?')
      .setChoiceValues(['0', '1', '2', '3'])
      .setHelpText('Leave at 0 if you answered No above.');

  // ── SECTION 7 — Dues, Payment & Food Drive ──────────────────────────────
  var sec7 = form.addPageBreakItem();
  sec7.setTitle('Step 7 of 8 — Dues, Event Payment, and St. Felix Food Drive');
  sec7.setHelpText(
    'This section covers dues owed, event payment, and an opportunity to support\n' +
    'the SN Food Drive for St. Felix Pantry.\n\n' +
    'St. Felix is the only full-time food pantry serving Sandoval County where\n' +
    'the Santa Ana Pueblo is located.\n\n' +
    'A collection barrel will be in the La Terraza area during the welcome reception\n' +
    'and in the Hospitality Suite throughout the weekend.\n' +
    'Canned goods and dry goods are welcome. Cash donations are also accepted at the barrels.\n' +
    'To donate online, scan the QR code on the event flyer and note your donation is from SN.\n\n' +
    'When you are done with this page, click Next to continue.'
  );

  form.addMultipleChoiceItem()
      .setTitle('Do you still need to pay your 2026 dues of $50?')
      .setHelpText('Please pay dues before or along with your event registration payment.')
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addListItem()
      .setTitle('How many people are you paying the 60th Anniversary Celebration fee for?')
      .setChoiceValues(['1', '2', '3'])
      .setHelpText('The celebration cost is $250 per person.')
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('Would you like to make a monetary donation to the SN Food Drive for St. Felix Pantry?')
      .setHelpText(
        'Cash donations can also be made at the collection barrels on-site.\n' +
        'Online donations: scan the QR code on the event flyer and note your donation is from SN.'
      )
      .setChoiceValues(['Yes', 'No'])
      .setRequired(true);

  form.addTextItem()
      .setTitle('If yes, please enter your donation amount (example: 25)')
      .setHelpText('Leave blank if you answered No above. Enter numbers only — no $ sign needed.');

  form.addSectionHeaderItem()
      .setTitle('How to Pay — 2026 Dues ($50) and 60th Anniversary Celebration Fee ($250/person)')
      .setHelpText(
        'Payment can be made in any of the following 3 ways:\n\n' +

        '1. ZELLE (bank cash transfer — easiest option)\n' +
        '   Zelle is built into most bank "Online Banking" apps.\n' +
        '   Search for: sigmanuetasigma  (all lowercase, one word, no spaces)\n' +
        '   The email address contact@sigmanuetasigma.com also still works if you have it saved.\n' +
        '   IMPORTANT: When sending payment, add a note such as:\n' +
        '   "60th Anniversary registration for [your name]" or "2026 dues for [your name]"\n\n' +

        '2. ETF — Electronic Transfer / Direct Deposit\n' +
        '   We bank with Wells Fargo Bank.\n' +
        '   Routing Number:  111900659\n' +
        '   Account Number:  5445278160\n' +
        '   IMPORTANT: Include your name and what the payment is for in the memo/notes field.\n\n' +

        '3. MAIL A CHECK\n' +
        '   Make check payable to: Sigma Nu - Eta Sigma\n' +
        '   Write your name and payment purpose on the memo line.\n' +
        '   Mail to:\n' +
        '     Sigma Nu - Eta Sigma\n' +
        '     ENMU - Sta. 4343\n' +
        '     1500 S. Ave. K\n' +
        '     Portales, NM  88130\n' +
        '   (Do NOT put PO Box in the address)\n\n' +

        'If you or a brother you know are finding it difficult to afford the 60th Anniversary Celebration,\n' +
        'email contact@sigmanuetasigma.com to see if you qualify for a scholarship.\n' +
        'Several brothers have made scholarship money available to help fellow SNs.\n\n' +

        'Questions? Email us at contact@sigmanuetasigma.com'
      );

  // ── SECTION 8 — Notes ───────────────────────────────────────────────────
  var sec8 = form.addPageBreakItem();
  sec8.setTitle('Step 8 of 8 — Final Notes');
  sec8.setHelpText(
    'If you have any comments, special requests, or anything else you would like us to know,\n' +
    'please enter that below.\n\n' +
    'When you are done, click Submit at the bottom of the form.'
  );

  form.addParagraphTextItem()
      .setTitle('Note / Comment')
      .setHelpText('Leave blank if you have nothing to add.');

  // ── Done — log the URLs ─────────────────────────────────────────────────
  var url = form.getPublishedUrl();
  Logger.log('Form created successfully!');
  Logger.log('Form URL (share this link): ' + url);
  Logger.log('Edit URL (your editor link): ' + form.getEditUrl());
}

// =============================================================================
// STEP 2 — SET UP THE EMAIL NOTIFICATION TRIGGER
//
// After buildForm has run and created the form, run THIS function ONE TIME
// to install the trigger that emails you every completed registration.
//
// How to run it:
//   1. In the Apps Script editor, select "setupTrigger" in the function dropdown.
//   2. Click Run.
//   3. Approve any additional permissions if asked.
//   4. Done — every future submission will automatically email NOTIFICATION_EMAIL.
//
// You only need to run setupTrigger ONCE. Running it again just creates a
// duplicate trigger (use the Triggers page to delete extras if needed).
// =============================================================================

function setupTrigger() {
  // Find the most recently created form owned by this account
  // (the one buildForm just made) and attach a submit trigger to it.
  var files = DriveApp.getFilesByType(MimeType.GOOGLE_FORMS);
  var targetForm = null;
  var latestDate = new Date(0);

  while (files.hasNext()) {
    var file = files.next();
    if (file.getDateCreated() > latestDate) {
      latestDate = file.getDateCreated();
      targetForm = file;
    }
  }

  if (!targetForm) {
    Logger.log('ERROR: No Google Form found in your Drive. Run buildForm first.');
    return;
  }

  var formId = targetForm.getId();
  Logger.log('Attaching trigger to form: ' + targetForm.getName() + ' (ID: ' + formId + ')');

  ScriptApp.newTrigger('onFormSubmit')
           .forForm(formId)
           .onFormSubmit()
           .create();

  Logger.log('SUCCESS: Trigger installed. Every completed registration will be emailed to: ' + NOTIFICATION_EMAIL);
}

// =============================================================================
// onFormSubmit — runs automatically every time someone submits the form.
// Formats all answers into a readable email and sends it to NOTIFICATION_EMAIL.
// You do NOT run this manually — the trigger calls it for you.
// =============================================================================

function onFormSubmit(e) {
  try {
    var responses  = e.response.getItemResponses();
    var timestamp  = Utilities.formatDate(
                       e.response.getTimestamp(),
                       Session.getScriptTimeZone(),
                       'MMMM d, yyyy  h:mm a z'
                     );

    // ── Pull email from the typed "Email Address" field in the form ────────
    // This works whether or not the respondent is logged into Google.
    // We look for the question titled exactly "Email Address" in their answers.
    var respondent = '';
    for (var k = 0; k < responses.length; k++) {
      if (responses[k].getItem().getTitle() === 'Email Address') {
        respondent = responses[k].getResponse().trim();
        break;
      }
    }
    // Secondary fallback: Google's captured login email (only works if signed in)
    if (!respondent) {
      respondent = e.response.getRespondentEmail() || '';
    }

    // ── Build the answers section (shared by both emails) ─────────────────
    var answers = '';
    for (var i = 0; i < responses.length; i++) {
      var question = responses[i].getItem().getTitle();
      var answer   = responses[i].getResponse();
      if (Array.isArray(answer)) { answer = answer.join(', '); }
      if (answer === '' || answer === null || answer === undefined) { answer = '(no answer)'; }
      answers += 'Q: ' + question + '\n';
      answers += 'A: ' + answer   + '\n\n';
    }

    var divider = '-------------------------------------------\n';
    var subject = '*60th Registration* — Submission from ' + (respondent || 'unknown email');

    // ── Payment reminder block (appended to respondent copy) ──────────────
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

    // ── EMAIL 1: TO the respondent — their personal copy with payment info ─
    if (respondent) {
      var respondentBody =
        'Thank you for registering for the Sigma Nu Eta Sigma Chapter\n' +
        '60th Anniversary Celebration — July 9-12, 2026\n' +
        'Santa Ana Star Casino Hotel, Bernalillo, New Mexico\n\n' +
        'Here is a copy of your completed registration:\n\n' +
        divider +
        'Submitted: ' + timestamp + '\n\n' +
        answers +
        divider +
        paymentInfo;

      MailApp.sendEmail({
        to:      respondent,
        cc:      NOTIFICATION_EMAIL + ',' + CC_EMAIL,
        subject: subject,
        body:    respondentBody
      });

      Logger.log('Registration email sent TO: ' + respondent + ' | CC: ' + NOTIFICATION_EMAIL + ', ' + CC_EMAIL);

    } else {
      // No respondent email captured — send only to chapter addresses
      var fallbackBody =
        '===========================================\n' +
        '  *60th Registration* — New Submission\n' +
        '  NOTE: Respondent email was not captured.\n' +
        '===========================================\n\n' +
        'Submitted: ' + timestamp + '\n\n' +
        answers +
        divider +
        'Sigma Nu Eta Sigma Chapter — 60th Anniversary Celebration\n' +
        'Automated notification from Google Forms\n';

      MailApp.sendEmail({
        to:      NOTIFICATION_EMAIL,
        cc:      CC_EMAIL,
        subject: subject + ' — NO EMAIL FOUND, FOLLOW UP NEEDED',
        body:    fallbackBody
      });

      Logger.log('WARNING: No email found in typed field or Google login. Chapter addresses notified.');
    }

  } catch (err) {
    Logger.log('ERROR in onFormSubmit: ' + err);
    // Fail silently so the respondent submission is never affected
  }
}
