<#
.SYNOPSIS
    Launches a Covey-style task matrix GUI for entering, managing, and persisting tasks.

.VERSION
    2.1.0

.CHANGES FROM v2.0
    - Right-click any task in any quadrant to get a context menu with Delete and Edit
    - Mouse wheel scrolling works anywhere on the form (scrolls the quadrant the cursor
      is over, or the whole form when over empty space)
    - Due date/time field added to every task (optional)
    - Alert system: a background timer checks every 60 seconds; when a task's due
      time is within the next 15 minutes (or past due) a Windows toast-style balloon
      notification fires from the system tray icon, and the task row is highlighted
      red in its listbox
    - Format-TaskLabel now appends a clock symbol and due time when set
    - Save/Load JSON preserves DueOn field; existing files without it load cleanly
    - Export to CSV includes DueOn column

.REQUIREMENTS
    - Windows PowerShell 5.1 or PowerShell 7+ on Windows
    - Windows Forms support

.EXAMPLE
    PS> .\WorkPriorityMatrix_v2.ps1
#>

[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ══════════════════════════════════════════════════════════════════
#  RULE MAP  (single source of truth for rubric + drag-drop logic)
# ══════════════════════════════════════════════════════════════════
$script:RuleMap = @{
    'T|I' = [pscustomobject]@{ Quadrant='Q1'; Level='H'; Title='Do Now'    }
    'T|S' = [pscustomobject]@{ Quadrant='Q1'; Level='M'; Title='Do Now'    }
    'T|N' = [pscustomobject]@{ Quadrant='Q4'; Level='H'; Title='Eliminate' }
    'S|I' = [pscustomobject]@{ Quadrant='Q2'; Level='H'; Title='Schedule'  }
    'S|S' = [pscustomobject]@{ Quadrant='Q2'; Level='M'; Title='Schedule'  }
    'S|N' = [pscustomobject]@{ Quadrant='Q3'; Level='M'; Title='Delegate'  }
    'L|I' = [pscustomobject]@{ Quadrant='Q2'; Level='L'; Title='Schedule'  }
    'L|S' = [pscustomobject]@{ Quadrant='Q3'; Level='H'; Title='Delegate'  }
    'L|N' = [pscustomobject]@{ Quadrant='Q3'; Level='L'; Title='Delegate'  }
}
$script:QuadLevelValid   = @{ Q1=@('H','M'); Q2=@('H','M','L'); Q3=@('H','M','L'); Q4=@('H') }
$script:QuadLevelDefault = @{ Q1='M'; Q2='H'; Q3='M'; Q4='H' }

function Get-QuadrantAssignment {
    param(
        [Parameter(Mandatory)][ValidateSet('I','S','N')][string]$Importance,
        [Parameter(Mandatory)][ValidateSet('T','S','L')][string]$Urgency
    )
    $key = "$Urgency|$Importance"
    if ($script:RuleMap.ContainsKey($key)) { return $script:RuleMap[$key] }
    throw "Unsupported combination: $Urgency / $Importance"
}

# ══════════════════════════════════════════════════════════════════
#  TASK DATA MODEL
# ══════════════════════════════════════════════════════════════════
$script:Tasks       = [System.Collections.Generic.List[pscustomobject]]::new()
$script:NextSort    = 0
$script:EditingId   = $null
$script:CurrentFile = $null

# IDs of tasks whose alerts have already fired this session (avoid re-alerting)
$script:AlertedIds  = [System.Collections.Generic.HashSet[string]]::new()

function New-TaskObject {
    param(
        [string]$Name, [string]$Importance, [string]$Urgency,
        [string]$Quadrant, [string]$Level,
        [string]$DueOn = ''     # ISO datetime string or empty
    )
    $script:NextSort++
    return [pscustomobject]@{
        Id         = [guid]::NewGuid().Guid
        Name       = $Name
        Importance = $Importance
        Urgency    = $Urgency
        Quadrant   = $Quadrant
        Level      = $Level
        DueOn      = $DueOn
        Done       = $false
        SortOrder  = $script:NextSort
        CreatedOn  = (Get-Date).ToString('o')
    }
}

function Format-TaskLabel ([pscustomobject]$Task) {
    $base = '[{0} {1}]  {2}' -f $Task.Quadrant, $Task.Level, $Task.Name
    if (-not [string]::IsNullOrWhiteSpace($Task.DueOn)) {
        try {
            $due = [datetime]::Parse($Task.DueOn)
            $base += '  ⏰ ' + $due.ToString('MM/dd HH:mm')
        } catch {}
    }
    return $base
}

# ══════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════
function New-Label {
    param(
        [string]$Text, [int]$X, [int]$Y,
        [int]$Width=120, [int]$Height=24,
        [System.Drawing.Font]$Font=(New-Object System.Drawing.Font('Segoe UI',10)),
        [System.Drawing.Color]$ForeColor=[System.Drawing.Color]::Black
    )
    $l = New-Object System.Windows.Forms.Label
    $l.Text=$Text; $l.Location=New-Object System.Drawing.Point($X,$Y)
    $l.Size=New-Object System.Drawing.Size($Width,$Height)
    $l.Font=$Font; $l.ForeColor=$ForeColor
    return $l
}

function New-QuadrantPanel {
    param(
        [string]$Title, [string]$Subtitle,
        [System.Drawing.Point]$Location, [System.Drawing.Size]$Size,
        [System.Drawing.Color]$BackColor, [string]$QuadrantId
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location=$Location; $panel.Size=$Size
    $panel.BackColor=$BackColor
    $panel.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle

    $panel.Controls.Add((New-Label $Title 10 10 ($Size.Width-20) 32 `
        (New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)) `
        ([System.Drawing.Color]::FromArgb(44,62,80))))
    $panel.Controls.Add((New-Label $Subtitle 12 45 ($Size.Width-24) 24 `
        (New-Object System.Drawing.Font('Georgia',10,[System.Drawing.FontStyle]::Italic)) `
        ([System.Drawing.Color]::DimGray)))

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location=New-Object System.Drawing.Point(10,75)
    $lb.Size=New-Object System.Drawing.Size(($Size.Width-20),($Size.Height-85))
    $lb.Font=New-Object System.Drawing.Font('Segoe UI',10)
    $lb.HorizontalScrollbar=$true
    $lb.Tag=$QuadrantId
    $lb.IntegralHeight=$false
    $panel.Controls.Add($lb)

    return [pscustomobject]@{ Panel=$panel; ListBox=$lb }
}

# ══════════════════════════════════════════════════════════════════
#  FORM
# ══════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Daily Work Priority Matrix  v2.1'
$form.StartPosition = 'CenterScreen'
$form.Size          = New-Object System.Drawing.Size(1500,980)
$form.MinimumSize   = New-Object System.Drawing.Size(1200,800)
$form.BackColor     = [System.Drawing.Color]::FromArgb(245,247,250)
$form.Font          = New-Object System.Drawing.Font('Segoe UI',10)
$form.KeyPreview    = $true

# ── Menu ─────────────────────────────────────────────────────────
$menu    = New-Object System.Windows.Forms.MenuStrip
$mFile   = New-Object System.Windows.Forms.ToolStripMenuItem '&File'
$mNew    = New-Object System.Windows.Forms.ToolStripMenuItem '&New / Clear All    Ctrl+N'
$mOpen   = New-Object System.Windows.Forms.ToolStripMenuItem '&Open JSON…         Ctrl+O'
$mSave   = New-Object System.Windows.Forms.ToolStripMenuItem '&Save               Ctrl+S'
$mSaveAs = New-Object System.Windows.Forms.ToolStripMenuItem 'Save &As JSON…'
$mExport = New-Object System.Windows.Forms.ToolStripMenuItem '&Export to CSV…'
$mSep    = New-Object System.Windows.Forms.ToolStripSeparator
$mExit   = New-Object System.Windows.Forms.ToolStripMenuItem 'E&xit'
$mFile.DropDownItems.AddRange(@($mNew,$mOpen,$mSave,$mSaveAs,$mExport,$mSep,$mExit))
$menu.Items.Add($mFile) | Out-Null
$form.Controls.Add($menu)
$form.MainMenuStrip = $menu

# ── Header ───────────────────────────────────────────────────────
$form.Controls.Add((New-Label 'Daily Work Priority Matrix' 500 42 540 42 `
    (New-Object System.Drawing.Font('Georgia',22,[System.Drawing.FontStyle]::Bold)) `
    ([System.Drawing.Color]::FromArgb(44,84,150))))
$form.Controls.Add((New-Label 'Based on the Covey urgent/important framework' 520 86 440 26 `
    (New-Object System.Drawing.Font('Georgia',11,[System.Drawing.FontStyle]::Italic)) `
    ([System.Drawing.Color]::DimGray)))

# ── Info band ────────────────────────────────────────────────────
$topBand = New-Object System.Windows.Forms.Panel
$topBand.Location = New-Object System.Drawing.Point(40,130)
$topBand.Size     = New-Object System.Drawing.Size(1420,52)
$topBand.BackColor = [System.Drawing.Color]::FromArgb(221,232,243)
$form.Controls.Add($topBand)

$today     = Get-Date
$fBandBold = New-Object System.Drawing.Font('Georgia',12,[System.Drawing.FontStyle]::Bold)
$fBandNorm = New-Object System.Drawing.Font('Segoe UI',11)

$topBand.Controls.Add((New-Label 'Date:'    10  14  52  24 $fBandBold))
$topBand.Controls.Add((New-Label $today.ToString('MM/dd/yyyy') 66  14 110 24 $fBandNorm))
$topBand.Controls.Add((New-Label 'Day:'     190 14  44  24 $fBandBold))
$topBand.Controls.Add((New-Label $today.ToString('dddd')       238 14 110 24 $fBandNorm))
$topBand.Controls.Add((New-Label 'Top Priority:' 490 14 120 24 $fBandBold))
$script:lblTopPriority = New-Label '(none yet)' 616 14 440 24 $fBandNorm
$topBand.Controls.Add($script:lblTopPriority)
$topBand.Controls.Add((New-Label 'Primary Time Block:' 1070 14 175 24 $fBandBold))
$txtPrimaryBlock = New-Object System.Windows.Forms.TextBox
$txtPrimaryBlock.Location=New-Object System.Drawing.Point(1250,12)
$txtPrimaryBlock.Size=New-Object System.Drawing.Size(160,28); $txtPrimaryBlock.Font=$fBandNorm
$topBand.Controls.Add($txtPrimaryBlock)

# ══════════════════════════════════════════════════════════════════
#  LEFT INPUT PANEL
# ══════════════════════════════════════════════════════════════════
$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Location    = New-Object System.Drawing.Point(40,234)
$inputPanel.Size        = New-Object System.Drawing.Size(360,720)
$inputPanel.BackColor   = [System.Drawing.Color]::White
$inputPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($inputPanel)

$fHead    = New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)
$fLabel   = New-Object System.Drawing.Font('Georgia',11,[System.Drawing.FontStyle]::Bold)
$fInput   = New-Object System.Drawing.Font('Segoe UI',10)
$fSmall   = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Italic)
$blue     = [System.Drawing.Color]::FromArgb(44,84,150)
$pGray    = [System.Drawing.Color]::FromArgb(245,247,250)

$script:lblSectionTitle = New-Label 'Task Entry' 16 16 260 28 $fHead $blue
$inputPanel.Controls.Add($script:lblSectionTitle)

$inputPanel.Controls.Add((New-Label 'TASK' 16 65 80 22 $fLabel))
$txtTask = New-Object System.Windows.Forms.TextBox
$txtTask.Location=New-Object System.Drawing.Point(16,90); $txtTask.Size=New-Object System.Drawing.Size(320,28)
$txtTask.Font=$fInput; $txtTask.TabIndex=1
$inputPanel.Controls.Add($txtTask)

# Importance
$grpImp = New-Object System.Windows.Forms.GroupBox
$grpImp.Text='IMPORTANCE'; $grpImp.Font=$fLabel
$grpImp.Location=New-Object System.Drawing.Point(10,130); $grpImp.Size=New-Object System.Drawing.Size(336,108)
$inputPanel.Controls.Add($grpImp)

$rbImportant = New-Object System.Windows.Forms.RadioButton
$rbImportant.Text='Important (I)'; $rbImportant.Location=New-Object System.Drawing.Point(10,24)
$rbImportant.Size=New-Object System.Drawing.Size(280,24); $rbImportant.Font=$fInput; $rbImportant.TabIndex=2

$rbSomewhat = New-Object System.Windows.Forms.RadioButton
$rbSomewhat.Text='Somewhat Important (S)'; $rbSomewhat.Location=New-Object System.Drawing.Point(10,52)
$rbSomewhat.Size=New-Object System.Drawing.Size(280,24); $rbSomewhat.Font=$fInput; $rbSomewhat.TabIndex=3

$rbNot = New-Object System.Windows.Forms.RadioButton
$rbNot.Text='Not Important (N)'; $rbNot.Location=New-Object System.Drawing.Point(10,80)
$rbNot.Size=New-Object System.Drawing.Size(280,24); $rbNot.Font=$fInput; $rbNot.TabIndex=4

$grpImp.Controls.AddRange(@($rbImportant,$rbSomewhat,$rbNot))

# Urgency
$grpUrg = New-Object System.Windows.Forms.GroupBox
$grpUrg.Text='URGENCY'; $grpUrg.Font=$fLabel
$grpUrg.Location=New-Object System.Drawing.Point(10,250); $grpUrg.Size=New-Object System.Drawing.Size(336,108)
$inputPanel.Controls.Add($grpUrg)

$rbToday = New-Object System.Windows.Forms.RadioButton
$rbToday.Text='Today (T)'; $rbToday.Location=New-Object System.Drawing.Point(10,24)
$rbToday.Size=New-Object System.Drawing.Size(280,24); $rbToday.Font=$fInput; $rbToday.TabIndex=5

$rbSoon = New-Object System.Windows.Forms.RadioButton
$rbSoon.Text='Soon (S)'; $rbSoon.Location=New-Object System.Drawing.Point(10,52)
$rbSoon.Size=New-Object System.Drawing.Size(280,24); $rbSoon.Font=$fInput; $rbSoon.TabIndex=6

$rbLater = New-Object System.Windows.Forms.RadioButton
$rbLater.Text='Later (L)'; $rbLater.Location=New-Object System.Drawing.Point(10,80)
$rbLater.Size=New-Object System.Drawing.Size(280,24); $rbLater.Font=$fInput; $rbLater.TabIndex=7

$grpUrg.Controls.AddRange(@($rbToday,$rbSoon,$rbLater))

# ── Due date / time  (NEW in v2.1) ───────────────────────────────
$inputPanel.Controls.Add((New-Label 'Due Date / Time  (optional)' 16 372 240 22 $fLabel))

# Date picker
$dtpDue = New-Object System.Windows.Forms.DateTimePicker
$dtpDue.Location   = New-Object System.Drawing.Point(16,396)
$dtpDue.Size       = New-Object System.Drawing.Size(190,28)
$dtpDue.Font       = $fInput
$dtpDue.Format     = [System.Windows.Forms.DateTimePickerFormat]::Short
$dtpDue.TabIndex   = 8
# "No date" is represented by unchecking ShowCheckBox
$dtpDue.ShowCheckBox = $true
$dtpDue.Checked      = $false
$inputPanel.Controls.Add($dtpDue)

# Time picker  (masked textbox  HH:mm)
$inputPanel.Controls.Add((New-Label 'Time:' 214 400 40 20 $fSmall ([System.Drawing.Color]::DimGray)))
$txtDueTime = New-Object System.Windows.Forms.MaskedTextBox
$txtDueTime.Location = New-Object System.Drawing.Point(256,396)
$txtDueTime.Size     = New-Object System.Drawing.Size(78,28)
$txtDueTime.Font     = $fInput
$txtDueTime.Mask     = '00:00'
$txtDueTime.Text     = '08:00'
$txtDueTime.TabIndex = 9
$inputPanel.Controls.Add($txtDueTime)

$inputPanel.Controls.Add((New-Label 'Tip: check the date box to set a due alert.' 16 428 320 18 $fSmall ([System.Drawing.Color]::DimGray)))

# Assigned designation
$inputPanel.Controls.Add((New-Label 'Assigned Designation' 16 458 250 22 $fLabel))
$txtAssigned = New-Object System.Windows.Forms.TextBox
$txtAssigned.Location=New-Object System.Drawing.Point(16,482); $txtAssigned.Size=New-Object System.Drawing.Size(320,28)
$txtAssigned.ReadOnly=$true; $txtAssigned.BackColor=$pGray; $txtAssigned.Font=$fInput
$inputPanel.Controls.Add($txtAssigned)

# Row 1 buttons: Add / Clear Form / Remove
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Location=New-Object System.Drawing.Point(16,520); $btnAdd.Size=New-Object System.Drawing.Size(100,36)
$btnAdd.Text='Add Task'; $btnAdd.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnAdd.BackColor=$blue; $btnAdd.ForeColor=[System.Drawing.Color]::White
$btnAdd.FlatStyle='Flat'; $btnAdd.TabIndex=10

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location=New-Object System.Drawing.Point(126,520); $btnClear.Size=New-Object System.Drawing.Size(100,36)
$btnClear.Text='Clear Form'; $btnClear.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnClear.FlatStyle='Flat'; $btnClear.TabIndex=11

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Location=New-Object System.Drawing.Point(236,520); $btnRemove.Size=New-Object System.Drawing.Size(100,36)
$btnRemove.Text='Remove'; $btnRemove.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnRemove.FlatStyle='Flat'; $btnRemove.TabIndex=12
$inputPanel.Controls.AddRange(@($btnAdd,$btnClear,$btnRemove))

# Row 2 buttons: Update / Cancel Edit (hidden until edit mode)
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Location=New-Object System.Drawing.Point(16,564); $btnUpdate.Size=New-Object System.Drawing.Size(154,34)
$btnUpdate.Text='Update Task'; $btnUpdate.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnUpdate.BackColor=[System.Drawing.Color]::FromArgb(40,140,60); $btnUpdate.ForeColor=[System.Drawing.Color]::White
$btnUpdate.FlatStyle='Flat'; $btnUpdate.Visible=$false; $btnUpdate.TabIndex=13

$btnCancelEdit = New-Object System.Windows.Forms.Button
$btnCancelEdit.Location=New-Object System.Drawing.Point(180,564); $btnCancelEdit.Size=New-Object System.Drawing.Size(154,34)
$btnCancelEdit.Text='Cancel Edit'; $btnCancelEdit.Font=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnCancelEdit.FlatStyle='Flat'; $btnCancelEdit.Visible=$false; $btnCancelEdit.TabIndex=14
$inputPanel.Controls.AddRange(@($btnUpdate,$btnCancelEdit))

# Rubric preview
$inputPanel.Controls.Add((New-Label 'Rubric Preview' 16 610 140 22 $fLabel))
$txtRubric = New-Object System.Windows.Forms.TextBox
$txtRubric.Location=New-Object System.Drawing.Point(16,634); $txtRubric.Size=New-Object System.Drawing.Size(320,30)
$txtRubric.ReadOnly=$true; $txtRubric.BackColor=$pGray; $txtRubric.Font=$fSmall
$txtRubric.Text='Select Importance and Urgency to preview.'
$inputPanel.Controls.Add($txtRubric)

$inputPanel.Controls.Add((New-Label 'Tip: double-click a task to edit  |  right-click to delete' 16 676 320 22 $fSmall ([System.Drawing.Color]::DimGray)))

# ══════════════════════════════════════════════════════════════════
#  MATRIX AXIS HEADERS
# ══════════════════════════════════════════════════════════════════
$axisBG    = [System.Drawing.Color]::FromArgb(200,218,233)
$fAxisBig  = New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)
$fAxisSm   = New-Object System.Drawing.Font('Georgia',10,[System.Drawing.FontStyle]::Bold)

foreach ($h in @(@{T='Urgent';X=500;W=470},@{T='Not Urgent';X=970;W=470})) {
    $p=New-Object System.Windows.Forms.Panel; $p.Location=New-Object System.Drawing.Point($h.X,234)
    $p.Size=New-Object System.Drawing.Size($h.W,56); $p.BackColor=$axisBG
    $p.Controls.Add((New-Label $h.T ([int](($h.W-160)/2)) 12 160 28 $fAxisBig))
    $form.Controls.Add($p)
}
foreach ($v in @(@{T='Important';Y=290},@{T='Not Important';Y=580})) {
    $p=New-Object System.Windows.Forms.Panel; $p.Location=New-Object System.Drawing.Point(410,$v.Y)
    $p.Size=New-Object System.Drawing.Size(90,290); $p.BackColor=$axisBG
    $p.Controls.Add((New-Label $v.T 4 121 82 48 $fAxisSm))
    $form.Controls.Add($p)
}

# ══════════════════════════════════════════════════════════════════
#  QUADRANT PANELS
# ══════════════════════════════════════════════════════════════════
$q1 = New-QuadrantPanel 'Do Now'    'Q1 — Urgent + Important' `
    (New-Object System.Drawing.Point(500,290)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(239,231,193)) 'Q1'

$q2 = New-QuadrantPanel 'Schedule'  'Q2 — Important, Not Urgent' `
    (New-Object System.Drawing.Point(970,290)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(214,226,206)) 'Q2'

$q3 = New-QuadrantPanel 'Delegate'  'Q3 — Urgent, Less Important' `
    (New-Object System.Drawing.Point(500,580)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(233,214,200)) 'Q3'

$q4 = New-QuadrantPanel 'Eliminate' 'Q4 — Not Urgent + Not Important' `
    (New-Object System.Drawing.Point(970,580)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(224,224,224)) 'Q4'

$form.Controls.AddRange(@($q1.Panel,$q2.Panel,$q3.Panel,$q4.Panel))

$script:QuadListBox = @{
    Q1=$q1.ListBox; Q2=$q2.ListBox; Q3=$q3.ListBox; Q4=$q4.ListBox
}

# Alert highlight colour for overdue / imminent tasks
$script:AlertColor  = [System.Drawing.Color]::FromArgb(255,80,80)
$script:AlertBgColor = [System.Drawing.Color]::FromArgb(255,230,230)

# ══════════════════════════════════════════════════════════════════
#  STATUS STRIP
# ══════════════════════════════════════════════════════════════════
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = 'Ready.  Enter a task, choose Importance and Urgency, then click Add Task.'
[void]$statusStrip.Items.Add($script:statusLabel)
$form.Controls.Add($statusStrip)

# ══════════════════════════════════════════════════════════════════
#  SYSTEM TRAY ICON  (used for balloon alert notifications)
# ══════════════════════════════════════════════════════════════════
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon    = [System.Drawing.SystemIcons]::Information
$trayIcon.Visible = $true
$trayIcon.Text    = 'Work Priority Matrix'

$form.Add_FormClosed({
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
})

# ══════════════════════════════════════════════════════════════════
#  CORE FUNCTIONS
# ══════════════════════════════════════════════════════════════════
function Set-Status ([string]$Msg) { $script:statusLabel.Text = $Msg }

function Refresh-AllListBoxes {
    foreach ($qid in @('Q1','Q2','Q3','Q4')) {
        $script:QuadListBox[$qid].Items.Clear()
    }
    foreach ($t in ($script:Tasks | Sort-Object SortOrder)) {
        $script:QuadListBox[$t.Quadrant].Items.Add((Format-TaskLabel $t)) | Out-Null
    }
    Update-TopPriority
    Apply-AlertHighlights
}

function Update-TopPriority {
    $best = $script:Tasks |
        Where-Object { $_.Quadrant -eq 'Q1' -and $_.Level -eq 'H' } |
        Sort-Object SortOrder | Select-Object -First 1
    if ($best) { $script:lblTopPriority.Text = $best.Name }
    elseif ($script:Tasks.Count -eq 0) { $script:lblTopPriority.Text = '(none yet)' }
}

function Get-DueOnString {
    # Build ISO datetime string from the date/time picker controls.
    # Returns empty string if the date checkbox is unchecked.
    if (-not $dtpDue.Checked) { return '' }
    try {
        $timeStr = $txtDueTime.Text.Trim()
        if ($timeStr -match '^\d{2}:\d{2}$') {
            $combined = $dtpDue.Value.Date.ToString('yyyy-MM-dd') + 'T' + $timeStr + ':00'
            [void][datetime]::Parse($combined)   # validate
            return $combined
        }
    } catch {}
    return $dtpDue.Value.Date.ToString('o')
}

function Set-DuePickers ([string]$DueOn) {
    if ([string]::IsNullOrWhiteSpace($DueOn)) {
        $dtpDue.Checked = $false
        $txtDueTime.Text = '08:00'
        return
    }
    try {
        $d = [datetime]::Parse($DueOn)
        $dtpDue.Checked  = $true
        $dtpDue.Value    = $d
        $txtDueTime.Text = $d.ToString('HH:mm')
    } catch {
        $dtpDue.Checked = $false
    }
}

# ── Alert highlighting ────────────────────────────────────────────
# Colours the text of overdue / imminent items red in the listbox.
# WinForms ListBox doesn't support per-item colour natively, so we
# use DrawItem with OwnerDraw mode when any task in that list has a due date.
function Apply-AlertHighlights {
    $now = Get-Date
    # Build a set of due-task display labels that are overdue or within 15 min
    $script:AlertLabels = @{}
    foreach ($t in $script:Tasks) {
        if ([string]::IsNullOrWhiteSpace($t.DueOn)) { continue }
        try {
            $due = [datetime]::Parse($t.DueOn)
            $diff = ($due - $now).TotalMinutes
            if ($diff -le 15) {
                $label = Format-TaskLabel $t
                $script:AlertLabels[$label] = $true
            }
        } catch {}
    }
}

# Enable owner-draw on a listbox so we can colour urgent rows red
function Enable-AlertDraw ([System.Windows.Forms.ListBox]$lb) {
    $lb.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed

    $lb.Add_DrawItem({
        param($s,$e)
        try {
            if ($e.Index -lt 0) { return }
            $itemText = $s.Items[$e.Index].ToString()

            $isAlert    = $script:AlertLabels.ContainsKey($itemText)
            $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0

            if ($isSelected) {
                $bg = [System.Drawing.SystemBrushes]::Highlight
                $fg = [System.Drawing.SystemBrushes]::HighlightText
            } elseif ($isAlert) {
                $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,220,220))
                $fg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,0,0))
            } else {
                $bg = New-Object System.Drawing.SolidBrush($s.BackColor)
                $fg = New-Object System.Drawing.SolidBrush($s.ForeColor)
            }

            $e.Graphics.FillRectangle($bg, $e.Bounds)
            $e.Graphics.DrawString($itemText, $s.Font, $fg,
                [float]($e.Bounds.X + 2), [float]($e.Bounds.Y + 2))

            if (-not $isSelected) { $bg.Dispose(); $fg.Dispose() }
        } catch {}
    })
}

foreach ($qid in @('Q1','Q2','Q3','Q4')) {
    Enable-AlertDraw $script:QuadListBox[$qid]
}

# ── Alert check timer (fires every 60 seconds) ───────────────────
$script:AlertLabels = @{}
$alertTimer = New-Object System.Windows.Forms.Timer
$alertTimer.Interval = 60000   # 60 seconds

$alertTimer.Add_Tick({
    $now = Get-Date
    Apply-AlertHighlights
    Refresh-AllListBoxes   # repaint with updated colours

    foreach ($t in $script:Tasks) {
        if ([string]::IsNullOrWhiteSpace($t.DueOn)) { continue }
        if ($script:AlertedIds.Contains($t.Id))     { continue }
        try {
            $due  = [datetime]::Parse($t.DueOn)
            $diff = ($due - $now).TotalMinutes
            if ($diff -le 15) {
                $msg = if ($diff -le 0) {
                    "OVERDUE: $($t.Name)`nWas due $([Math]::Abs([int]$diff)) min ago"
                } else {
                    "DUE SOON: $($t.Name)`nDue in $([int]$diff) min  ($($due.ToString('HH:mm')))"
                }
                $trayIcon.BalloonTipTitle = 'Work Priority Matrix — Task Alert'
                $trayIcon.BalloonTipText  = $msg
                $trayIcon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
                $trayIcon.ShowBalloonTip(8000)
                Set-Status "⚠ ALERT: $($t.Name)"
                [void]$script:AlertedIds.Add($t.Id)
            }
        } catch {}
    }
})

$alertTimer.Start()

# ══════════════════════════════════════════════════════════════════
#  MOUSE WHEEL SCROLLING  (NEW in v2.1)
#  Hooks into the form's MouseWheel. Finds which quadrant listbox
#  (or the form itself) the cursor is over and scrolls it.
# ══════════════════════════════════════════════════════════════════
function Get-ListBoxUnderCursor {
    $cursor = [System.Windows.Forms.Cursor]::Position
    foreach ($qid in @('Q1','Q2','Q3','Q4')) {
        $lb = $script:QuadListBox[$qid]
        $screenRect = [System.Drawing.Rectangle]::new(
            $lb.PointToScreen([System.Drawing.Point]::Empty),
            $lb.Size)
        if ($screenRect.Contains($cursor)) { return $lb }
    }
    return $null
}

$form.Add_MouseWheel({
    param($s,$e)
    $lb = Get-ListBoxUnderCursor
    if ($lb) {
        # Scroll the listbox: each wheel notch = 3 items
        $lines = -[int]($e.Delta / 40)
        $newTop = [Math]::Max(0, [Math]::Min($lb.TopIndex + $lines, $lb.Items.Count - 1))
        $lb.TopIndex = $newTop
    } else {
        # Scroll the whole form if mouse is over empty space
        $delta = -[int]($e.Delta / 2)
        $form.AutoScrollPosition = New-Object System.Drawing.Point(
            [Math]::Abs($form.AutoScrollPosition.X),
            [Math]::Max(0, [Math]::Abs($form.AutoScrollPosition.Y) + $delta))
    }
})

# Also attach wheel handler to each listbox directly so it fires even
# when the listbox has focus (WinForms bubbles wheel to focused control first)
foreach ($qid in @('Q1','Q2','Q3','Q4')) {
    $script:QuadListBox[$qid].Add_MouseWheel({
        param($s,$e)
        $lines = -[int]($e.Delta / 40)
        $newTop = [Math]::Max(0, [Math]::Min($s.TopIndex + $lines, $s.Items.Count - 1))
        $s.TopIndex = $newTop
    })
}

# ══════════════════════════════════════════════════════════════════
#  RIGHT-CLICK CONTEXT MENU  (NEW in v2.1)
# ══════════════════════════════════════════════════════════════════
$ctxMenu       = New-Object System.Windows.Forms.ContextMenuStrip
$ctxEdit       = New-Object System.Windows.Forms.ToolStripMenuItem 'Edit Task…'
$ctxDelete     = New-Object System.Windows.Forms.ToolStripMenuItem 'Delete Task'
$ctxSep        = New-Object System.Windows.Forms.ToolStripSeparator
$ctxClearAlerts = New-Object System.Windows.Forms.ToolStripMenuItem 'Clear Alert for This Task'
$ctxMenu.Items.AddRange(@($ctxEdit,$ctxDelete,$ctxSep,$ctxClearAlerts))

# Shared variable: which listbox the right-click happened on
$script:CtxListBox = $null
$script:CtxIndex   = -1

function Get-CtxTask {
    if ($null -eq $script:CtxListBox -or $script:CtxIndex -lt 0) { return $null }
    $qid     = $script:CtxListBox.Tag.ToString()
    $visible = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
    if ($script:CtxIndex -ge $visible.Count) { return $null }
    return $visible[$script:CtxIndex]
}

$ctxEdit.Add_Click({
    $task = Get-CtxTask
    if ($task) { Begin-EditTask $task }
})

$ctxDelete.Add_Click({
    $task = Get-CtxTask
    if ($task) {
        $script:Tasks.Remove($task) | Out-Null
        [void]$script:AlertedIds.Remove($task.Id)
        Refresh-AllListBoxes
        Set-Status "Deleted '$($task.Name)'."
        if ($script:EditingId -eq $task.Id) { Clear-EntryForm }
    }
})

$ctxClearAlerts.Add_Click({
    $task = Get-CtxTask
    if ($task) {
        [void]$script:AlertedIds.Remove($task.Id)
        Apply-AlertHighlights
        Refresh-AllListBoxes
        Set-Status "Alert cleared for '$($task.Name)'.  It will re-alert next check."
    }
})

# Attach right-click handler to every quadrant listbox
foreach ($qid in @('Q1','Q2','Q3','Q4')) {
    $script:QuadListBox[$qid].Add_MouseDown({
        param($s,$e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
        $idx = $s.IndexFromPoint($e.Location)
        if ($idx -ge 0) {
            $s.SelectedIndex      = $idx
            $script:CtxListBox    = $s
            $script:CtxIndex      = $idx
            $ctxMenu.Show($s, $e.Location)
        }
    })
}

# ══════════════════════════════════════════════════════════════════
#  ENTRY FORM LOGIC
# ══════════════════════════════════════════════════════════════════
function Get-SelectedImportance {
    if ($rbImportant.Checked) { return 'I' }
    if ($rbSomewhat.Checked)  { return 'S' }
    if ($rbNot.Checked)       { return 'N' }
    return $null
}

function Get-SelectedUrgency {
    if ($rbToday.Checked) { return 'T' }
    if ($rbSoon.Checked)  { return 'S' }
    if ($rbLater.Checked) { return 'L' }
    return $null
}

function Update-RubricPreview {
    $imp = Get-SelectedImportance
    $urg = Get-SelectedUrgency
    if (-not $imp -or -not $urg) {
        $txtAssigned.Text=''; $txtRubric.Text='Select Importance and Urgency to preview.'
        return
    }
    $a = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $txtAssigned.Text = '{0} ({1}) — {2}' -f $a.Quadrant,$a.Level,$a.Title
    $txtRubric.Text   = 'Rubric: {0} ({1}) — {2}' -f $a.Quadrant,$a.Level,$a.Title
}

function Clear-EntryForm {
    $script:EditingId = $null
    $txtTask.Clear()
    foreach ($rb in @($rbImportant,$rbSomewhat,$rbNot,$rbToday,$rbSoon,$rbLater)) { $rb.Checked=$false }
    $dtpDue.Checked  = $false
    $txtDueTime.Text = '08:00'
    $txtAssigned.Clear()
    $txtRubric.Text  = 'Select Importance and Urgency to preview.'
    $script:lblSectionTitle.Text = 'Task Entry'
    $btnAdd.Visible=$true; $btnClear.Visible=$true; $btnRemove.Visible=$true
    $btnUpdate.Visible=$false; $btnCancelEdit.Visible=$false
    $grpImp.BackColor=[System.Drawing.Color]::Transparent
    $grpUrg.BackColor=[System.Drawing.Color]::Transparent
    $txtTask.Focus()
}

function Add-Task {
    $name = $txtTask.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Set-Status 'Please enter a task name.'; $txtTask.Focus(); return
    }
    $imp = Get-SelectedImportance
    if (-not $imp) {
        $grpImp.BackColor=[System.Drawing.Color]::FromArgb(255,235,200)
        Set-Status 'Please select an Importance value.'; return
    }
    $grpImp.BackColor=[System.Drawing.Color]::Transparent
    $urg = Get-SelectedUrgency
    if (-not $urg) {
        $grpUrg.BackColor=[System.Drawing.Color]::FromArgb(255,235,200)
        Set-Status 'Please select an Urgency value.'; return
    }
    $grpUrg.BackColor=[System.Drawing.Color]::Transparent

    $a    = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $due  = Get-DueOnString
    $task = New-TaskObject -Name $name -Importance $imp -Urgency $urg `
                           -Quadrant $a.Quadrant -Level $a.Level -DueOn $due
    $script:Tasks.Add($task)
    Refresh-AllListBoxes
    $dueMsg = if ($due) { "  — due $([datetime]::Parse($due).ToString('MM/dd HH:mm'))" } else { '' }
    Set-Status "Added '$name'  →  $($a.Quadrant) ($($a.Level))$dueMsg"
    Clear-EntryForm
}

function Remove-SelectedTask {
    foreach ($qid in @('Q1','Q2','Q3','Q4')) {
        $lb = $script:QuadListBox[$qid]
        if ($lb.SelectedIndex -ge 0) {
            $visible = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            $task = $visible[$lb.SelectedIndex]
            if ($task) {
                $script:Tasks.Remove($task) | Out-Null
                [void]$script:AlertedIds.Remove($task.Id)
                Refresh-AllListBoxes
                Set-Status "Removed '$($task.Name)'."
                if ($script:EditingId -eq $task.Id) { Clear-EntryForm }
            }
            return
        }
    }
    Set-Status 'Select a task first (click it), then press Remove or Delete — or right-click for the context menu.'
}

function Begin-EditTask ([pscustomobject]$Task) {
    $script:EditingId = $Task.Id
    $script:lblSectionTitle.Text = 'Edit Task'
    $txtTask.Text = $Task.Name
    $rbImportant.Checked = ($Task.Importance -eq 'I')
    $rbSomewhat.Checked  = ($Task.Importance -eq 'S')
    $rbNot.Checked       = ($Task.Importance -eq 'N')
    $rbToday.Checked     = ($Task.Urgency -eq 'T')
    $rbSoon.Checked      = ($Task.Urgency -eq 'S')
    $rbLater.Checked     = ($Task.Urgency -eq 'L')
    Set-DuePickers $Task.DueOn
    $btnAdd.Visible=$false; $btnClear.Visible=$false; $btnRemove.Visible=$false
    $btnUpdate.Visible=$true; $btnCancelEdit.Visible=$true
    Update-RubricPreview
    Set-Status "Editing '$($Task.Name)' — change values then click Update Task."
    $txtTask.Focus()
}

function Commit-EditTask {
    $task = $script:Tasks | Where-Object { $_.Id -eq $script:EditingId } | Select-Object -First 1
    if (-not $task) { Clear-EntryForm; return }
    $name = $txtTask.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { Set-Status 'Task name cannot be blank.'; return }
    $imp = Get-SelectedImportance
    if (-not $imp) { $grpImp.BackColor=[System.Drawing.Color]::FromArgb(255,235,200); Set-Status 'Select an Importance.'; return }
    $grpImp.BackColor=[System.Drawing.Color]::Transparent
    $urg = Get-SelectedUrgency
    if (-not $urg) { $grpUrg.BackColor=[System.Drawing.Color]::FromArgb(255,235,200); Set-Status 'Select a Urgency.'; return }
    $grpUrg.BackColor=[System.Drawing.Color]::Transparent

    $a             = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $task.Name      = $name
    $task.Importance= $imp
    $task.Urgency   = $urg
    $task.Quadrant  = $a.Quadrant
    $task.Level     = $a.Level
    $task.DueOn     = Get-DueOnString
    # Reset alert so the updated due time can re-fire
    [void]$script:AlertedIds.Remove($task.Id)

    Refresh-AllListBoxes
    Set-Status "Updated '$name'  →  $($a.Quadrant) ($($a.Level))"
    Clear-EntryForm
}

# ══════════════════════════════════════════════════════════════════
#  DRAG-AND-DROP
# ══════════════════════════════════════════════════════════════════
$script:DragTaskId = $null
$script:DragSource = $null

function Register-DragDrop ([System.Windows.Forms.ListBox]$lb) {
    $lb.AllowDrop = $true

    $lb.Add_MouseDown({
        param($s,$e)
        try {
            if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
            $idx = $s.IndexFromPoint($e.Location)
            if ($idx -lt 0) { return }
            $s.SelectedIndex = $idx
            $qid = $s.Tag.ToString()
            $vis = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            if ($idx -ge $vis.Count) { return }
            $script:DragTaskId = $vis[$idx].Id
            $script:DragSource = $s
            [void]$s.DoDragDrop($script:DragTaskId, [System.Windows.Forms.DragDropEffects]::Move)
        } catch {}
    })

    $lb.Add_DragEnter({
        param($s,$e)
        try {
            $e.Effect = if ($e.Data.GetDataPresent([string]) -and $script:DragTaskId) {
                [System.Windows.Forms.DragDropEffects]::Move
            } else { [System.Windows.Forms.DragDropEffects]::None }
        } catch {}
    })

    $lb.Add_DragOver({
        param($s,$e)
        try {
            if ($e.Data.GetDataPresent([string]) -and $script:DragTaskId) {
                $e.Effect = [System.Windows.Forms.DragDropEffects]::Move
            }
        } catch {}
    })

    $lb.Add_DragDrop({
        param($s,$e)
        try {
            if (-not $script:DragTaskId) { return }
            $task = $script:Tasks | Where-Object { $_.Id -eq $script:DragTaskId } | Select-Object -First 1
            if (-not $task) { return }

            $pt      = $s.PointToClient([System.Drawing.Point]::new($e.X,$e.Y))
            $dropIdx = $s.IndexFromPoint($pt)
            if ($dropIdx -lt 0) { $dropIdx = $s.Items.Count }

            $destQid = $s.Tag.ToString()
            if ($destQid -ne $task.Quadrant) {
                $newLevel = if ($script:QuadLevelValid[$destQid] -contains $task.Level) {
                    $task.Level } else { $script:QuadLevelDefault[$destQid] }
                $task.Quadrant   = $destQid
                $task.Level      = $newLevel
                $task.Importance = 'MANUAL'
                $task.Urgency    = 'MANUAL'
            }

            $destTasks = @($script:Tasks |
                Where-Object { $_.Quadrant -eq $destQid -and $_.Id -ne $task.Id } |
                Sort-Object SortOrder)
            $clamp   = [Math]::Max(0,[Math]::Min($dropIdx,$destTasks.Count))
            $newSort = if ($destTasks.Count -eq 0)   { 1000 }
                       elseif ($clamp -eq 0)          { $destTasks[0].SortOrder - 1 }
                       elseif ($clamp -ge $destTasks.Count) { $destTasks[$destTasks.Count-1].SortOrder + 1 }
                       else { [int](($destTasks[$clamp-1].SortOrder + $destTasks[$clamp].SortOrder)/2) }
            $task.SortOrder = $newSort

            Refresh-AllListBoxes
            Set-Status "Moved '$($task.Name)'  →  $($task.Quadrant) ($($task.Level))"
        } catch {}
        finally { $script:DragTaskId=$null; $script:DragSource=$null }
    })

    $lb.Add_QueryContinueDrag({
        param($s,$e)
        try {
            if ($e.EscapePressed) {
                $e.Action = [System.Windows.Forms.DragAction]::Cancel
                $script:DragTaskId=$null; $script:DragSource=$null
            }
        } catch {}
    })

    $lb.Add_DoubleClick({
        param($s,$e)
        try {
            $idx = $s.SelectedIndex; if ($idx -lt 0) { return }
            $qid = $s.Tag.ToString()
            $vis = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            if ($idx -lt $vis.Count) { Begin-EditTask $vis[$idx] }
        } catch {}
    })
}

Register-DragDrop $q1.ListBox
Register-DragDrop $q2.ListBox
Register-DragDrop $q3.ListBox
Register-DragDrop $q4.ListBox

# ══════════════════════════════════════════════════════════════════
#  SAVE / LOAD / EXPORT
# ══════════════════════════════════════════════════════════════════
function Save-ToFile ([string]$Path) {
    try {
        $script:Tasks | ConvertTo-Json -Depth 5 |
            Set-Content -Path $Path -Encoding UTF8
        $script:CurrentFile = $Path
        $form.Text = "Daily Work Priority Matrix  v2.1  —  $(Split-Path $Path -Leaf)"
        Set-Status "Saved to $Path"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Save failed:`n$_",'Save Error','OK','Error') | Out-Null
    }
}

function Save-AsJson {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title='Save Matrix As'; $dlg.Filter='JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.DefaultExt='json'; $dlg.FileName="WorkMatrix_$($today.ToString('yyyy-MM-dd')).json"
    if ($dlg.ShowDialog() -eq 'OK') { Save-ToFile $dlg.FileName }
}

function Save-Current {
    if ($script:CurrentFile) { Save-ToFile $script:CurrentFile } else { Save-AsJson }
}

function Load-FromJson {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title='Open Matrix File'; $dlg.Filter='JSON files (*.json)|*.json|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $raw = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Tasks.Clear()
        $script:AlertedIds.Clear()
        $maxSort = 0
        foreach ($r in $raw) {
            $t = [pscustomobject]@{
                Id         = if ($r.Id)        { $r.Id }        else { [guid]::NewGuid().Guid }
                Name       = $r.Name
                Importance = if ($r.Importance){ $r.Importance } else { 'I' }
                Urgency    = if ($r.Urgency)   { $r.Urgency }   else { 'T' }
                Quadrant   = $r.Quadrant
                Level      = $r.Level
                DueOn      = if ($r.DueOn)     { $r.DueOn }     else { '' }
                Done       = if ($r.PSObject.Properties['Done']) { [bool]$r.Done } else { $false }
                SortOrder  = if ($r.SortOrder) { [int]$r.SortOrder } else { ++$maxSort }
                CreatedOn  = if ($r.CreatedOn) { $r.CreatedOn } else { (Get-Date).ToString('o') }
            }
            if ($t.SortOrder -gt $maxSort) { $maxSort = $t.SortOrder }
            $script:Tasks.Add($t)
        }
        $script:NextSort    = $maxSort + 1
        $script:CurrentFile = $dlg.FileName
        $form.Text = "Daily Work Priority Matrix  v2.1  —  $(Split-Path $dlg.FileName -Leaf)"
        Refresh-AllListBoxes
        Clear-EntryForm
        Set-Status "Loaded $($script:Tasks.Count) tasks from $(Split-Path $dlg.FileName -Leaf)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Load failed:`n$_",'Load Error','OK','Error') | Out-Null
    }
}

function Export-ToCsv {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title='Export to CSV'; $dlg.Filter='CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    $dlg.DefaultExt='csv'; $dlg.FileName="WorkMatrix_$($today.ToString('yyyy-MM-dd')).csv"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $script:Tasks | Sort-Object Quadrant,SortOrder |
            Select-Object Quadrant,Level,Name,Importance,Urgency,DueOn,CreatedOn |
            Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding UTF8
        Set-Status "Exported to $(Split-Path $dlg.FileName -Leaf)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Export failed:`n$_",'Export Error','OK','Error') | Out-Null
    }
}

function Clear-AllTasks {
    $r = [System.Windows.Forms.MessageBox]::Show(
        'Clear all tasks and start a new matrix?','Confirm New','YesNo','Question')
    if ($r -eq 'Yes') {
        $script:Tasks.Clear(); $script:AlertedIds.Clear()
        $script:CurrentFile=$null; $script:NextSort=0
        $form.Text='Daily Work Priority Matrix  v2.1'
        Refresh-AllListBoxes; Clear-EntryForm
        Set-Status 'Matrix cleared.  Ready for a new day.'
    }
}

# ══════════════════════════════════════════════════════════════════
#  EVENT WIRING
# ══════════════════════════════════════════════════════════════════
$uh = { Update-RubricPreview }
foreach ($rb in @($rbImportant,$rbSomewhat,$rbNot,$rbToday,$rbSoon,$rbLater)) {
    $rb.Add_CheckedChanged($uh)
}

$btnAdd.Add_Click(       { Add-Task })
$btnClear.Add_Click(     { Clear-EntryForm })
$btnRemove.Add_Click(    { Remove-SelectedTask })
$btnUpdate.Add_Click(    { Commit-EditTask })
$btnCancelEdit.Add_Click({ Clear-EntryForm })

$txtTask.Add_KeyDown({
    param($s,$e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        if ($script:EditingId) { Commit-EditTask } else { Add-Task }
        $e.SuppressKeyPress = $true
    }
})

$form.Add_KeyDown({
    param($s,$e)
    switch ($true) {
        ($e.KeyCode -eq 'Escape')                           { Clear-EntryForm;    $e.SuppressKeyPress=$true }
        ($e.KeyCode -eq 'Delete' -and -not $txtTask.Focused){ Remove-SelectedTask; $e.SuppressKeyPress=$true }
        ($e.Control -and $e.KeyCode -eq 'S')                { Save-Current;        $e.SuppressKeyPress=$true }
        ($e.Control -and $e.KeyCode -eq 'O')                { Load-FromJson;       $e.SuppressKeyPress=$true }
        ($e.Control -and $e.KeyCode -eq 'N')                { Clear-AllTasks;      $e.SuppressKeyPress=$true }
    }
})

$mNew.Add_Click(    { Clear-AllTasks })
$mOpen.Add_Click(   { Load-FromJson })
$mSave.Add_Click(   { Save-Current })
$mSaveAs.Add_Click( { Save-AsJson })
$mExport.Add_Click( { Export-ToCsv })
$mExit.Add_Click(   { $form.Close() })

# ══════════════════════════════════════════════════════════════════
#  SHOW
# ══════════════════════════════════════════════════════════════════
$form.Add_Shown({ $txtTask.Focus() })
[void]$form.ShowDialog()

$alertTimer.Stop()
$alertTimer.Dispose()
