<#
.SYNOPSIS
    Launches a Covey-style task matrix GUI for entering, managing, and persisting tasks.

.DESCRIPTION
    Windows Forms PowerShell GUI. Collects task description, importance, and urgency,
    then assigns each task to a quadrant and level using the Covey rubric.

    Quadrant assignments:
        Q1 (H|M)   = Do Now      — Urgent + Important
        Q2 (H|M|L) = Schedule    — Important, Not Urgent
        Q3 (H|M|L) = Delegate    — Urgent/Soon, Less Important
        Q4 (H)     = Eliminate   — Not Urgent + Not Important

.VERSION
    2.0.0

.CHANGES FROM v1.5.3
    - Object-based task model (pscustomobject with Id, Name, Importance, Urgency,
      Quadrant, Level, SortOrder, CreatedOn)
    - Centralized $RuleMap replaces duplicate rubric logic
    - Save / Load JSON persistence (File menu + Ctrl+S / Ctrl+O)
    - Export to CSV (File menu)
    - Edit task by double-clicking — loads back into form, shows Update / Cancel
    - Top priority always re-derived from task list after every state change
    - Drag/drop updates real task object attributes, not just display strings
    - Keyboard shortcuts: Esc clears form, Delete removes selected task,
      Ctrl+S saves, Ctrl+O opens, Ctrl+N new/clear all
    - Status bar replaces most modal pop-ups for routine feedback
    - Removed unused New-ComboBox function

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
#  CENTRALIZED RULE MAP
#  Single source of truth for all rubric and level-validation logic.
#  Key = "Urgency|Importance"
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

# Valid levels per quadrant (used when a dragged task changes quadrant)
$script:QuadLevelValid   = @{ Q1=@('H','M'); Q2=@('H','M','L'); Q3=@('H','M','L'); Q4=@('H') }
$script:QuadLevelDefault = @{ Q1='M'; Q2='H'; Q3='M'; Q4='H' }

function Get-QuadrantAssignment {
    [CmdletBinding()]
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
#  $script:Tasks is the single source of truth.
#  ListBoxes are display-only views rendered from it.
# ══════════════════════════════════════════════════════════════════
$script:Tasks        = [System.Collections.Generic.List[pscustomobject]]::new()
$script:NextSort     = 0      # monotonically increasing sort key
$script:EditingId    = $null  # non-null while an edit is in progress
$script:CurrentFile  = $null  # path of last saved/loaded file

function New-TaskObject {
    param(
        [string]$Name,
        [string]$Importance,
        [string]$Urgency,
        [string]$Quadrant,
        [string]$Level
    )
    $script:NextSort++
    return [pscustomobject]@{
        Id         = [guid]::NewGuid().Guid
        Name       = $Name
        Importance = $Importance
        Urgency    = $Urgency
        Quadrant   = $Quadrant
        Level      = $Level
        SortOrder  = $script:NextSort
        CreatedOn  = (Get-Date).ToString('o')
    }
}

function Format-TaskLabel ([pscustomobject]$Task) {
    '[{0} {1}]  {2}' -f $Task.Quadrant, $Task.Level, $Task.Name
}

# ══════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════
function New-Label {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 120, [int]$Height = 24,
        [System.Drawing.Font]$Font   = (New-Object System.Drawing.Font('Segoe UI',10)),
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::Black
    )
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = New-Object System.Drawing.Point($X,$Y)
    $l.Size = New-Object System.Drawing.Size($Width,$Height)
    $l.Font = $Font; $l.ForeColor = $ForeColor
    return $l
}

function New-QuadrantPanel {
    param(
        [string]$Title, [string]$Subtitle,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size,
        [System.Drawing.Color]$BackColor,
        [string]$QuadrantId
    )
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = $Location; $panel.Size = $Size
    $panel.BackColor = $BackColor
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $panel.Controls.Add((New-Label $Title 10 10 ($Size.Width-20) 32 `
        (New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)) `
        ([System.Drawing.Color]::FromArgb(44,62,80))))

    $panel.Controls.Add((New-Label $Subtitle 12 45 ($Size.Width-24) 24 `
        (New-Object System.Drawing.Font('Georgia',10,[System.Drawing.FontStyle]::Italic)) `
        ([System.Drawing.Color]::DimGray)))

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(10,75)
    $lb.Size = New-Object System.Drawing.Size(($Size.Width-20),($Size.Height-85))
    $lb.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $lb.HorizontalScrollbar = $true
    $lb.Tag = $QuadrantId
    $lb.IntegralHeight = $false
    $panel.Controls.Add($lb)

    return [pscustomobject]@{ Panel=$panel; ListBox=$lb }
}

# ══════════════════════════════════════════════════════════════════
#  FORM
# ══════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Daily Work Priority Matrix  v2'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1500,980)
$form.MinimumSize = New-Object System.Drawing.Size(1200,800)
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
$form.Font = New-Object System.Drawing.Font('Segoe UI',10)
$form.KeyPreview = $true   # needed for global keyboard shortcuts

# ══════════════════════════════════════════════════════════════════
#  MENU STRIP
# ══════════════════════════════════════════════════════════════════
$menu = New-Object System.Windows.Forms.MenuStrip

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

# ══════════════════════════════════════════════════════════════════
#  HEADER
# ══════════════════════════════════════════════════════════════════
$form.Controls.Add((New-Label 'Daily Work Priority Matrix' 500 42 540 42 `
    (New-Object System.Drawing.Font('Georgia',22,[System.Drawing.FontStyle]::Bold)) `
    ([System.Drawing.Color]::FromArgb(44,84,150))))

$form.Controls.Add((New-Label 'Based on the Covey urgent/important framework' 520 86 440 26 `
    (New-Object System.Drawing.Font('Georgia',11,[System.Drawing.FontStyle]::Italic)) `
    ([System.Drawing.Color]::DimGray)))

# ══════════════════════════════════════════════════════════════════
#  INFO BAND
# ══════════════════════════════════════════════════════════════════
$topBand = New-Object System.Windows.Forms.Panel
$topBand.Location = New-Object System.Drawing.Point(40,130)
$topBand.Size = New-Object System.Drawing.Size(1420,52)
$topBand.BackColor = [System.Drawing.Color]::FromArgb(221,232,243)
$form.Controls.Add($topBand)

$today = Get-Date
$fBandBold   = New-Object System.Drawing.Font('Georgia',12,[System.Drawing.FontStyle]::Bold)
$fBandNormal = New-Object System.Drawing.Font('Segoe UI',11)

$topBand.Controls.Add((New-Label 'Date:'    10  14  52  24 $fBandBold))
$topBand.Controls.Add((New-Label $today.ToString('MM/dd/yyyy') 66  14 110 24 $fBandNormal))
$topBand.Controls.Add((New-Label 'Day:'     190 14  44  24 $fBandBold))
$topBand.Controls.Add((New-Label $today.ToString('dddd')       238 14 110 24 $fBandNormal))
$topBand.Controls.Add((New-Label 'Top Priority:' 490 14 120 24 $fBandBold))

$script:lblTopPriority = New-Label '(none yet)' 616 14 440 24 $fBandNormal
$topBand.Controls.Add($script:lblTopPriority)

$topBand.Controls.Add((New-Label 'Primary Time Block:' 1070 14 175 24 $fBandBold))
$txtPrimaryBlock = New-Object System.Windows.Forms.TextBox
$txtPrimaryBlock.Location = New-Object System.Drawing.Point(1250,12)
$txtPrimaryBlock.Size = New-Object System.Drawing.Size(160,28)
$txtPrimaryBlock.Font = $fBandNormal
$topBand.Controls.Add($txtPrimaryBlock)

# ══════════════════════════════════════════════════════════════════
#  LEFT INPUT PANEL
# ══════════════════════════════════════════════════════════════════
$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Location = New-Object System.Drawing.Point(40,234)
$inputPanel.Size = New-Object System.Drawing.Size(360,700)
$inputPanel.BackColor = [System.Drawing.Color]::White
$inputPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($inputPanel)

$fSectionHead = New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)
$fLabel       = New-Object System.Drawing.Font('Georgia',11,[System.Drawing.FontStyle]::Bold)
$fInput       = New-Object System.Drawing.Font('Segoe UI',10)
$fSmall       = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Italic)
$accentBlue   = [System.Drawing.Color]::FromArgb(44,84,150)
$panelGray    = [System.Drawing.Color]::FromArgb(245,247,250)

# Section title — changes between "Task Entry" and "Edit Task"
$script:lblSectionTitle = New-Label 'Task Entry' 16 16 260 28 $fSectionHead $accentBlue
$inputPanel.Controls.Add($script:lblSectionTitle)

$inputPanel.Controls.Add((New-Label 'TASK' 16 65 80 22 $fLabel))
$txtTask = New-Object System.Windows.Forms.TextBox
$txtTask.Location = New-Object System.Drawing.Point(16,90)
$txtTask.Size = New-Object System.Drawing.Size(320,28)
$txtTask.Font = $fInput
$inputPanel.Controls.Add($txtTask)

# Importance group
$grpImp = New-Object System.Windows.Forms.GroupBox
$grpImp.Text = 'IMPORTANCE'; $grpImp.Font = $fLabel
$grpImp.Location = New-Object System.Drawing.Point(10,132)
$grpImp.Size = New-Object System.Drawing.Size(336,108)
$inputPanel.Controls.Add($grpImp)

$rbImportant = New-Object System.Windows.Forms.RadioButton
$rbImportant.Location = New-Object System.Drawing.Point(10,24); $rbImportant.Size = New-Object System.Drawing.Size(280,24)
$rbImportant.Text = 'Important (I)'; $rbImportant.Font = $fInput; $rbImportant.TabIndex = 2

$rbSomewhat = New-Object System.Windows.Forms.RadioButton
$rbSomewhat.Location = New-Object System.Drawing.Point(10,52); $rbSomewhat.Size = New-Object System.Drawing.Size(280,24)
$rbSomewhat.Text = 'Somewhat Important (S)'; $rbSomewhat.Font = $fInput; $rbSomewhat.TabIndex = 3

$rbNot = New-Object System.Windows.Forms.RadioButton
$rbNot.Location = New-Object System.Drawing.Point(10,80); $rbNot.Size = New-Object System.Drawing.Size(280,24)
$rbNot.Text = 'Not Important (N)'; $rbNot.Font = $fInput; $rbNot.TabIndex = 4

$grpImp.Controls.AddRange(@($rbImportant,$rbSomewhat,$rbNot))

# Urgency group
$grpUrg = New-Object System.Windows.Forms.GroupBox
$grpUrg.Text = 'URGENCY'; $grpUrg.Font = $fLabel
$grpUrg.Location = New-Object System.Drawing.Point(10,252)
$grpUrg.Size = New-Object System.Drawing.Size(336,108)
$inputPanel.Controls.Add($grpUrg)

$rbToday = New-Object System.Windows.Forms.RadioButton
$rbToday.Location = New-Object System.Drawing.Point(10,24); $rbToday.Size = New-Object System.Drawing.Size(280,24)
$rbToday.Text = 'Today (T)'; $rbToday.Font = $fInput; $rbToday.TabIndex = 5

$rbSoon = New-Object System.Windows.Forms.RadioButton
$rbSoon.Location = New-Object System.Drawing.Point(10,52); $rbSoon.Size = New-Object System.Drawing.Size(280,24)
$rbSoon.Text = 'Soon (S)'; $rbSoon.Font = $fInput; $rbSoon.TabIndex = 6

$rbLater = New-Object System.Windows.Forms.RadioButton
$rbLater.Location = New-Object System.Drawing.Point(10,80); $rbLater.Size = New-Object System.Drawing.Size(280,24)
$rbLater.Text = 'Later (L)'; $rbLater.Font = $fInput; $rbLater.TabIndex = 7

$grpUrg.Controls.AddRange(@($rbToday,$rbSoon,$rbLater))

# Assigned designation (read-only preview)
$inputPanel.Controls.Add((New-Label 'Assigned Designation' 16 374 250 22 $fLabel))
$txtAssigned = New-Object System.Windows.Forms.TextBox
$txtAssigned.Location = New-Object System.Drawing.Point(16,398); $txtAssigned.Size = New-Object System.Drawing.Size(320,28)
$txtAssigned.ReadOnly = $true; $txtAssigned.BackColor = $panelGray; $txtAssigned.Font = $fInput
$inputPanel.Controls.Add($txtAssigned)

# Buttons row 1 — Add / Clear / Remove
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Location = New-Object System.Drawing.Point(16,442); $btnAdd.Size = New-Object System.Drawing.Size(100,36)
$btnAdd.Text = 'Add Task'; $btnAdd.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnAdd.BackColor = $accentBlue; $btnAdd.ForeColor = [System.Drawing.Color]::White
$btnAdd.FlatStyle = 'Flat'; $btnAdd.TabIndex = 8

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object System.Drawing.Point(126,442); $btnClear.Size = New-Object System.Drawing.Size(100,36)
$btnClear.Text = 'Clear Form'; $btnClear.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnClear.FlatStyle = 'Flat'; $btnClear.TabIndex = 9

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Location = New-Object System.Drawing.Point(236,442); $btnRemove.Size = New-Object System.Drawing.Size(100,36)
$btnRemove.Text = 'Remove'; $btnRemove.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnRemove.FlatStyle = 'Flat'; $btnRemove.TabIndex = 10

$inputPanel.Controls.AddRange(@($btnAdd,$btnClear,$btnRemove))

# Buttons row 2 — Update / Cancel Edit (hidden until editing)
$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Location = New-Object System.Drawing.Point(16,486); $btnUpdate.Size = New-Object System.Drawing.Size(154,34)
$btnUpdate.Text = 'Update Task'; $btnUpdate.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(40,140,60); $btnUpdate.ForeColor = [System.Drawing.Color]::White
$btnUpdate.FlatStyle = 'Flat'; $btnUpdate.Visible = $false; $btnUpdate.TabIndex = 11

$btnCancelEdit = New-Object System.Windows.Forms.Button
$btnCancelEdit.Location = New-Object System.Drawing.Point(180,486); $btnCancelEdit.Size = New-Object System.Drawing.Size(154,34)
$btnCancelEdit.Text = 'Cancel Edit'; $btnCancelEdit.Font = New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$btnCancelEdit.FlatStyle = 'Flat'; $btnCancelEdit.Visible = $false; $btnCancelEdit.TabIndex = 12

$inputPanel.Controls.AddRange(@($btnUpdate,$btnCancelEdit))

# Rubric preview
$inputPanel.Controls.Add((New-Label 'Rubric Preview' 16 530 140 22 $fLabel))
$txtRubric = New-Object System.Windows.Forms.TextBox
$txtRubric.Location = New-Object System.Drawing.Point(16,554); $txtRubric.Size = New-Object System.Drawing.Size(320,30)
$txtRubric.ReadOnly = $true; $txtRubric.BackColor = $panelGray; $txtRubric.Font = $fSmall
$txtRubric.Text = 'Select Importance and Urgency to preview.'
$inputPanel.Controls.Add($txtRubric)

# Tip label
$lblTip = New-Label 'Tip: double-click any task to edit it.' 16 596 320 22 $fSmall ([System.Drawing.Color]::DimGray)
$inputPanel.Controls.Add($lblTip)

# ══════════════════════════════════════════════════════════════════
#  MATRIX AXIS LABELS
# ══════════════════════════════════════════════════════════════════
$axisBG = [System.Drawing.Color]::FromArgb(200,218,233)
$fAxisBig  = New-Object System.Drawing.Font('Georgia',16,[System.Drawing.FontStyle]::Bold)
$fAxisSmall = New-Object System.Drawing.Font('Georgia',10,[System.Drawing.FontStyle]::Bold)

foreach ($h in @(
    @{T='Urgent';      X=500; W=470},
    @{T='Not Urgent';  X=970; W=470}
)) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($h.X, 234)
    $p.Size = New-Object System.Drawing.Size($h.W, 56)
    $p.BackColor = $axisBG
    $p.Controls.Add((New-Label $h.T ([int](($h.W-160)/2)) 12 160 28 $fAxisBig))
    $form.Controls.Add($p)
}

foreach ($v in @(
    @{T='Important';     Y=290},
    @{T='Not Important'; Y=580}
)) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(410, $v.Y)
    $p.Size = New-Object System.Drawing.Size(90,290)
    $p.BackColor = $axisBG
    $p.Controls.Add((New-Label $v.T 4 121 82 48 $fAxisSmall))
    $form.Controls.Add($p)
}

# ══════════════════════════════════════════════════════════════════
#  QUADRANT PANELS
# ══════════════════════════════════════════════════════════════════
$q1 = New-QuadrantPanel 'Do Now'   'Q1 — Urgent + Important' `
    (New-Object System.Drawing.Point(500,290)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(239,231,193)) 'Q1'

$q2 = New-QuadrantPanel 'Schedule' 'Q2 — Important, Not Urgent' `
    (New-Object System.Drawing.Point(970,290)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(214,226,206)) 'Q2'

$q3 = New-QuadrantPanel 'Delegate' 'Q3 — Urgent, Less Important' `
    (New-Object System.Drawing.Point(500,580)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(233,214,200)) 'Q3'

$q4 = New-QuadrantPanel 'Eliminate' 'Q4 — Not Urgent + Not Important' `
    (New-Object System.Drawing.Point(970,580)) (New-Object System.Drawing.Size(470,290)) `
    ([System.Drawing.Color]::FromArgb(224,224,224)) 'Q4'

$form.Controls.AddRange(@($q1.Panel,$q2.Panel,$q3.Panel,$q4.Panel))

# Map quadrant ID → ListBox for easy lookup
$script:QuadListBox = @{
    Q1 = $q1.ListBox; Q2 = $q2.ListBox; Q3 = $q3.ListBox; Q4 = $q4.ListBox
}

# ══════════════════════════════════════════════════════════════════
#  STATUS STRIP
# ══════════════════════════════════════════════════════════════════
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = 'Ready.  Enter a task, choose Importance and Urgency, then click Add Task.'
[void]$statusStrip.Items.Add($script:statusLabel)
$form.Controls.Add($statusStrip)

# ══════════════════════════════════════════════════════════════════
#  CORE FUNCTIONS
# ══════════════════════════════════════════════════════════════════

function Set-Status ([string]$Msg) { $script:statusLabel.Text = $Msg }

function Refresh-AllListBoxes {
    # Clear all four listboxes and re-populate from $script:Tasks
    foreach ($qid in @('Q1','Q2','Q3','Q4')) {
        $script:QuadListBox[$qid].Items.Clear()
    }
    foreach ($t in ($script:Tasks | Sort-Object SortOrder)) {
        $script:QuadListBox[$t.Quadrant].Items.Add((Format-TaskLabel $t)) | Out-Null
    }
    Update-TopPriority
}

function Update-TopPriority {
    $best = $script:Tasks |
        Where-Object { $_.Quadrant -eq 'Q1' -and $_.Level -eq 'H' } |
        Sort-Object SortOrder | Select-Object -First 1
    if ($best) {
        $script:lblTopPriority.Text = $best.Name
    } elseif ($script:Tasks.Count -eq 0) {
        $script:lblTopPriority.Text = '(none yet)'
    }
    # if Q1-H tasks exist, the first one remains displayed
}

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
        $txtAssigned.Text = ''
        $txtRubric.Text   = 'Select Importance and Urgency to preview.'
        return
    }
    $a = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $txtAssigned.Text = '{0} ({1}) — {2}' -f $a.Quadrant, $a.Level, $a.Title
    $txtRubric.Text   = 'Rubric: {0} ({1}) — {2}' -f $a.Quadrant, $a.Level, $a.Title
}

function Clear-EntryForm {
    $script:EditingId = $null
    $txtTask.Clear()
    foreach ($rb in @($rbImportant,$rbSomewhat,$rbNot,$rbToday,$rbSoon,$rbLater)) {
        $rb.Checked = $false
    }
    $txtAssigned.Clear()
    $txtRubric.Text = 'Select Importance and Urgency to preview.'
    $script:lblSectionTitle.Text = 'Task Entry'
    $btnAdd.Visible        = $true
    $btnClear.Visible      = $true
    $btnRemove.Visible     = $true
    $btnUpdate.Visible     = $false
    $btnCancelEdit.Visible = $false
    $grpImp.BackColor      = [System.Drawing.Color]::Transparent
    $grpUrg.BackColor      = [System.Drawing.Color]::Transparent
    $txtTask.Focus()
}

function Add-Task {
    $name = $txtTask.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        $grpImp.BackColor = [System.Drawing.Color]::Transparent
        $grpUrg.BackColor = [System.Drawing.Color]::Transparent
        Set-Status 'Please enter a task name.'
        $txtTask.Focus(); return
    }
    $imp = Get-SelectedImportance
    if (-not $imp) {
        $grpImp.BackColor = [System.Drawing.Color]::FromArgb(255,235,200)
        Set-Status 'Please select an Importance value.'
        return
    }
    $grpImp.BackColor = [System.Drawing.Color]::Transparent

    $urg = Get-SelectedUrgency
    if (-not $urg) {
        $grpUrg.BackColor = [System.Drawing.Color]::FromArgb(255,235,200)
        Set-Status 'Please select an Urgency value.'
        return
    }
    $grpUrg.BackColor = [System.Drawing.Color]::Transparent

    $a    = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $task = New-TaskObject -Name $name -Importance $imp -Urgency $urg `
                           -Quadrant $a.Quadrant -Level $a.Level
    $script:Tasks.Add($task)
    Refresh-AllListBoxes
    Set-Status "Added '$name'  →  $($a.Quadrant) ($($a.Level)) — $($a.Title)"
    Clear-EntryForm
}

function Remove-SelectedTask {
    foreach ($qid in @('Q1','Q2','Q3','Q4')) {
        $lb = $script:QuadListBox[$qid]
        if ($lb.SelectedIndex -ge 0) {
            # Find the matching task object by display position
            $visibleTasks = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            $task = $visibleTasks[$lb.SelectedIndex]
            if ($task) {
                $script:Tasks.Remove($task) | Out-Null
                Refresh-AllListBoxes
                Set-Status "Removed '$($task.Name)'."
                if ($script:EditingId -eq $task.Id) { Clear-EntryForm }
            }
            return
        }
    }
    Set-Status 'Select a task in any quadrant first, then click Remove  (or press Delete).'
}

function Begin-EditTask ([pscustomobject]$Task) {
    $script:EditingId = $Task.Id
    $script:lblSectionTitle.Text = 'Edit Task'
    $txtTask.Text = $Task.Name

    # Restore importance radio
    $rbImportant.Checked = ($Task.Importance -eq 'I')
    $rbSomewhat.Checked  = ($Task.Importance -eq 'S')
    $rbNot.Checked       = ($Task.Importance -eq 'N')

    # Restore urgency radio (only if not manually repositioned)
    $rbToday.Checked = ($Task.Urgency -eq 'T')
    $rbSoon.Checked  = ($Task.Urgency -eq 'S')
    $rbLater.Checked = ($Task.Urgency -eq 'L')

    $btnAdd.Visible        = $false
    $btnClear.Visible      = $false
    $btnRemove.Visible     = $false
    $btnUpdate.Visible     = $true
    $btnCancelEdit.Visible = $true
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
    $grpImp.BackColor = [System.Drawing.Color]::Transparent

    $urg = Get-SelectedUrgency
    if (-not $urg) { $grpUrg.BackColor=[System.Drawing.Color]::FromArgb(255,235,200); Set-Status 'Select a Urgency.'; return }
    $grpUrg.BackColor = [System.Drawing.Color]::Transparent

    $a             = Get-QuadrantAssignment -Importance $imp -Urgency $urg
    $task.Name      = $name
    $task.Importance= $imp
    $task.Urgency   = $urg
    $task.Quadrant  = $a.Quadrant
    $task.Level     = $a.Level

    Refresh-AllListBoxes
    Set-Status "Updated '$name'  →  $($a.Quadrant) ($($a.Level)) — $($a.Title)"
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
            $visible = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            if ($idx -ge $visible.Count) { return }
            $script:DragTaskId = $visible[$idx].Id
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
            if (-not $task) { $script:DragTaskId=$null; $script:DragSource=$null; return }

            # Calculate insertion position
            $pt      = $s.PointToClient([System.Drawing.Point]::new($e.X,$e.Y))
            $dropIdx = $s.IndexFromPoint($pt)
            if ($dropIdx -lt 0) { $dropIdx = $s.Items.Count }

            $destQid = $s.Tag.ToString()
            $srcQid  = $task.Quadrant

            # Update quadrant and level on the actual task object
            if ($destQid -ne $srcQid) {
                $newLevel = if ($script:QuadLevelValid[$destQid] -contains $task.Level) {
                    $task.Level
                } else {
                    $script:QuadLevelDefault[$destQid]
                }
                $task.Quadrant = $destQid
                $task.Level    = $newLevel
                # Clear Importance/Urgency when manually repositioned to a different quadrant
                # so edit-load doesn't show stale values
                $task.Importance = 'MANUAL'
                $task.Urgency    = 'MANUAL'
            }

            # Re-assign SortOrder so the task lands at $dropIdx within the destination
            $destTasks = @($script:Tasks |
                Where-Object { $_.Quadrant -eq $destQid -and $_.Id -ne $task.Id } |
                Sort-Object SortOrder)

            $clamp = [Math]::Max(0,[Math]::Min($dropIdx,$destTasks.Count))
            $newSort = if ($destTasks.Count -eq 0) {
                1000
            } elseif ($clamp -eq 0) {
                $destTasks[0].SortOrder - 1
            } elseif ($clamp -ge $destTasks.Count) {
                $destTasks[$destTasks.Count-1].SortOrder + 1
            } else {
                [int](($destTasks[$clamp-1].SortOrder + $destTasks[$clamp].SortOrder) / 2)
            }
            $task.SortOrder = $newSort

            Refresh-AllListBoxes
            Set-Status "Moved '$($task.Name)'  →  $($task.Quadrant) ($($task.Level))"
        } catch {}
        finally {
            $script:DragTaskId = $null
            $script:DragSource = $null
        }
    })

    $lb.Add_QueryContinueDrag({
        param($s,$e)
        try {
            if ($e.EscapePressed) {
                $e.Action = [System.Windows.Forms.DragAction]::Cancel
                $script:DragTaskId = $null; $script:DragSource = $null
            }
        } catch {}
    })

    # Double-click → edit task
    $lb.Add_DoubleClick({
        param($s,$e)
        try {
            $idx = $s.SelectedIndex
            if ($idx -lt 0) { return }
            $qid     = $s.Tag.ToString()
            $visible = @($script:Tasks | Where-Object { $_.Quadrant -eq $qid } | Sort-Object SortOrder)
            if ($idx -lt $visible.Count) { Begin-EditTask $visible[$idx] }
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
        $script:Tasks | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
        $script:CurrentFile = $Path
        $form.Text = "Daily Work Priority Matrix  v2  —  $(Split-Path $Path -Leaf)"
        Set-Status "Saved to $Path"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Save failed:`n$_",'Save Error','OK','Error') | Out-Null
    }
}

function Save-AsJson {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title  = 'Save Matrix As'
    $dlg.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dlg.DefaultExt = 'json'
    $dlg.FileName = "WorkMatrix_$($today.ToString('yyyy-MM-dd')).json"
    if ($dlg.ShowDialog() -eq 'OK') { Save-ToFile $dlg.FileName }
}

function Save-Current {
    if ($script:CurrentFile) { Save-ToFile $script:CurrentFile } else { Save-AsJson }
}

function Load-FromJson {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Open Matrix File'
    $dlg.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $raw = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Tasks.Clear()
        $maxSort = 0
        foreach ($r in $raw) {
            $t = [pscustomobject]@{
                Id         = if ($r.Id)        { $r.Id }        else { [guid]::NewGuid().Guid }
                Name       = $r.Name
                Importance = if ($r.Importance){ $r.Importance } else { 'I' }
                Urgency    = if ($r.Urgency)   { $r.Urgency }   else { 'T' }
                Quadrant   = $r.Quadrant
                Level      = $r.Level
                SortOrder  = if ($r.SortOrder) { [int]$r.SortOrder } else { ++$maxSort }
                CreatedOn  = if ($r.CreatedOn) { $r.CreatedOn } else { (Get-Date).ToString('o') }
            }
            if ($t.SortOrder -gt $maxSort) { $maxSort = $t.SortOrder }
            $script:Tasks.Add($t)
        }
        $script:NextSort  = $maxSort + 1
        $script:CurrentFile = $dlg.FileName
        $form.Text = "Daily Work Priority Matrix  v2  —  $(Split-Path $dlg.FileName -Leaf)"
        Refresh-AllListBoxes
        Clear-EntryForm
        Set-Status "Loaded $($script:Tasks.Count) tasks from $(Split-Path $dlg.FileName -Leaf)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Load failed:`n$_",'Load Error','OK','Error') | Out-Null
    }
}

function Export-ToCsv {
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = 'Export to CSV'
    $dlg.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    $dlg.DefaultExt = 'csv'
    $dlg.FileName = "WorkMatrix_$($today.ToString('yyyy-MM-dd')).csv"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $script:Tasks | Sort-Object Quadrant,SortOrder |
            Select-Object Quadrant,Level,Name,Importance,Urgency,CreatedOn |
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
        $script:Tasks.Clear()
        $script:CurrentFile = $null
        $script:NextSort = 0
        $form.Text = 'Daily Work Priority Matrix  v2'
        Refresh-AllListBoxes
        Clear-EntryForm
        Set-Status 'Matrix cleared.  Ready for a new day.'
    }
}

# ══════════════════════════════════════════════════════════════════
#  EVENT WIRING
# ══════════════════════════════════════════════════════════════════

# Radio button live preview
$uh = { Update-RubricPreview }
foreach ($rb in @($rbImportant,$rbSomewhat,$rbNot,$rbToday,$rbSoon,$rbLater)) {
    $rb.Add_CheckedChanged($uh)
}

# Buttons
$btnAdd.Add_Click(       { Add-Task })
$btnClear.Add_Click(     { Clear-EntryForm })
$btnRemove.Add_Click(    { Remove-SelectedTask })
$btnUpdate.Add_Click(    { Commit-EditTask })
$btnCancelEdit.Add_Click({ Clear-EntryForm })

# Enter key in task box
$txtTask.Add_KeyDown({
    param($s,$e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        if ($script:EditingId) { Commit-EditTask } else { Add-Task }
        $e.SuppressKeyPress = $true
    }
})

# Global keyboard shortcuts
$form.Add_KeyDown({
    param($s,$e)
    switch ($true) {
        ($e.KeyCode -eq 'Escape') {
            Clear-EntryForm; $e.SuppressKeyPress = $true
        }
        ($e.KeyCode -eq 'Delete' -and -not $txtTask.Focused) {
            Remove-SelectedTask; $e.SuppressKeyPress = $true
        }
        ($e.Control -and $e.KeyCode -eq 'S') {
            Save-Current; $e.SuppressKeyPress = $true
        }
        ($e.Control -and $e.KeyCode -eq 'O') {
            Load-FromJson; $e.SuppressKeyPress = $true
        }
        ($e.Control -and $e.KeyCode -eq 'N') {
            Clear-AllTasks; $e.SuppressKeyPress = $true
        }
    }
})

# Menu items
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
