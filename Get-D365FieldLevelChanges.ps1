<#
.SYNOPSIS
    Detects field-level AND structural metadata changes (Added / Deleted / Data Type Changed /
    Relations / Indexes / Field Groups / Delete Actions / Table Properties) between two
    git commits for D365 F&O AxTable, AxTableExtension, AxDataEntityView, and
    AxDataEntityViewExtension XML files.

.DESCRIPTION
    Designed to run as a post-deployment step in an Azure DevOps Release pipeline.
    Compares the metadata XML at $FromCommit vs $ToCommit and prints a table of every
    change, per object, with the change type - directly to the pipeline log.
    (CSV export is temporarily disabled since the output file isn't reachable off the
    build agent without an extra "Publish Artifact" pipeline step - see the commented-out
    Export-Csv line near the end of the script for how to re-enable it once that's set up.)

    NOTE ON SCOPE: In addition to field-level changes, this version also diffs the
    Relations, Indexes, FieldGroups, and DeleteActions sections (whole-node XML
    comparison), plus any scalar/leaf table-level properties (e.g. whichever
    property represents the clustered index, PrimaryIndex, TableGroup, etc.).
    This closes the gap where a file shows up as "changed" in git but the field
    comparison alone reports "changes: 0" because the actual difference was a
    relation deletion, cluster key change, or similar structural edit outside
    <Fields>.

    Because Relations/Indexes/FieldGroups/DeleteActions are compared via normalized
    raw XML (OuterXml, whitespace-collapsed) rather than structured property-by-property
    comparison, this can also flag purely cosmetic XML differences (e.g. attribute
    reordering) as "Modified". If that becomes noisy, replace Get-NamedChildElements /
    Compare-NamedNodes with structured parsers similar to Get-FieldsFromXml.

.PARAMETER RepoPath
    Local path to the git repository (checked out) - e.g. $(System.DefaultWorkingDirectory)/CoreBuildGITRepo

.PARAMETER FromCommit
    (Optional) The "before" commit hash. If omitted, SinceHours is used instead to compute it automatically.

.PARAMETER SinceHours
    (Optional, default 24) Look back this many hours from now to find the "before" commit.
    Use this for a nightly pipeline - it automatically picks up "whatever changed since last night's run",
    with no need to track commit hashes or query release history.

.PARAMETER ToCommit
    The "after" commit hash (this deployment's source commit). Defaults to HEAD.

.PARAMETER OutputPath
    Where to write the CSV report. (Currently unused - see note above.)

.PARAMETER SendGridKey
    (Optional) SendGrid API key. If supplied together with -EmailTo, an email
    report is sent via SendGrid's v3 mail/send API - but ONLY when there is at
    least one reportable change (no email is sent on a "nothing changed" run).

.PARAMETER EmailFrom
    (Optional) The "from" address for the email report. Should be a verified
    sender/domain in your SendGrid account, e.g. noReply_d365CBPipeline@metcash.com.

.PARAMETER EmailTo
    (Optional) Comma-separated recipient address(es) for the email report.
    Email sending is skipped entirely if this or -SendGridKey is not supplied.

.PARAMETER Branch
    (Optional) The branch name being compared (e.g. "test"). Purely cosmetic -
    shown in the email report header instead of raw commit hashes/repo path,
    since that's more meaningful to a reader who isn't looking at the pipeline log.

.EXAMPLE
    # Nightly pipeline usage - "whatever changed in the last 24 hours", no commit tracking needed
    .\Get-D365FieldLevelChanges.ps1 -RepoPath "K:\CoreBuildGITRepo" -SinceHours 24 -OutputPath "K:\Reports\FieldChanges.csv"

.EXAMPLE
    # Manual / ad-hoc usage with explicit commits
    .\Get-D365FieldLevelChanges.ps1 -RepoPath "K:\CoreBuildGITRepo" -FromCommit "abc123" -ToCommit "def456" -OutputPath "K:\Reports\FieldChanges.csv"

.EXAMPLE
    # With email report on changes
    .\Get-D365FieldLevelChanges.ps1 -RepoPath "K:\CoreBuildGITRepo" -SinceHours 24 `
        -SendGridKey "$(SendGridKey)" -EmailFrom "$(SenderEmail)" -EmailTo "you@metcash.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $false)]
    [string]$FromCommit,

    [Parameter(Mandatory = $false)]
    [int]$SinceHours = 24,

    [Parameter(Mandatory = $false)]
    [string]$ToCommit = "HEAD",

    # Not used right now - CSV export is disabled in favor of printing the report
    # to the console as a table. Kept as an optional param so the wrapper script
    # doesn't need to change, and so file export can be switched back on later.
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$SendGridKey,

    [Parameter(Mandatory = $false)]
    [string]$EmailFrom,

    [Parameter(Mandatory = $false)]
    [string]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$Branch = "Unknown"
)

Set-Location $RepoPath

# If no explicit FromCommit was given, resolve one automatically based on SinceHours.
# This is the "whatever changed during the day" mode for a nightly pipeline - no commit
# tracking or release-history lookups required.
if ([string]::IsNullOrWhiteSpace($FromCommit)) {
    Write-Host "No -FromCommit supplied - resolving commit from $SinceHours hours ago..." -ForegroundColor Cyan

    $sinceTimestamp = (Get-Date).AddHours(-$SinceHours).ToString("yyyy-MM-dd HH:mm:ss")
    $resolvedCommit = git rev-list -1 --before="$sinceTimestamp" $ToCommit

    if ([string]::IsNullOrWhiteSpace($resolvedCommit)) {
        # No commit exists that far back (e.g. repo/branch is newer than SinceHours) - fall back to earliest commit
        Write-Warning "No commit found before $sinceTimestamp. Falling back to the earliest commit in the repo."
        $resolvedCommit = (git rev-list --max-parents=0 $ToCommit | Select-Object -Last 1)
    }

    $FromCommit = $resolvedCommit
    Write-Host "Resolved FromCommit: $FromCommit (as of $sinceTimestamp)" -ForegroundColor Cyan
}

# Quick check: if nothing changed in the window at all, exit cleanly instead of erroring downstream
$quickCheck = git diff --name-only $FromCommit $ToCommit
if (-not $quickCheck) {
    Write-Host "No changes found between $FromCommit and $ToCommit. Nothing to report." -ForegroundColor Yellow
    exit 0
}

# Folder patterns for the 4 object types we care about
$objectTypePatterns = @{
    'AxTable/'                    = 'Table'
    'AxTableExtension/'           = 'Table Extension'
    'AxDataEntityView/'           = 'Data Entity'
    'AxDataEntityViewExtension/'  = 'Data Entity Extension'
}

function Get-ObjectType {
    param([string]$FilePath)
    foreach ($pattern in $objectTypePatterns.Keys) {
        if ($FilePath -match [regex]::Escape($pattern)) {
            return $objectTypePatterns[$pattern]
        }
    }
    return "Other"
}

function Get-FileContentAtCommit {
    param([string]$Commit, [string]$FilePath)
    try {
        $content = git show "${Commit}:${FilePath}" 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($content -join "`n")
    } catch {
        return $null
    }
}

function Get-FileChangeDate {
    <#
        Returns the commit date/time of the most recent commit that touched this
        file within the ($FromCommit, $ToCommit] window - i.e. when this specific
        object was actually changed, not just when the report ran.
    #>
    param([string]$FromCommit, [string]$ToCommit, [string]$FilePath)
    try {
        $dateStr = git log -1 --format=%cI "$FromCommit..$ToCommit" -- "$FilePath" 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dateStr)) { return "Unknown" }
        return $dateStr.Trim()
    } catch {
        return "Unknown"
    }
}

function Get-FieldsFromXml {
    <#
        Returns a hashtable keyed by field Name, containing Type (i:type attribute)
        and ExtendedDataType, for both direct <Fields> declarations and, for extension
        files, <FieldModifications> (property overrides on inherited base fields).

        Uses the XmlElement indexer (element["ChildName"]) rather than PowerShell's
        dynamic property adapter, which is unreliable for indirect (variable-based)
        property name lookups on XML documents.
    #>
    param([xml]$Xml)

    $fields = @{}
    $root = $Xml.DocumentElement

    if (-not $root) { return $fields }

    $fieldsNode = $root["Fields"]
    if ($fieldsNode) {
        $fieldElements = @($fieldsNode.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        foreach ($field in $fieldElements) {
            $nameNode = $field["Name"]
            $fieldName = if ($nameNode) { $nameNode.InnerText } else { $null }
            if ([string]::IsNullOrWhiteSpace($fieldName)) { continue }

            $typeAttr = $field.GetAttribute("type", "http://www.w3.org/2001/XMLSchema-instance")
            $edtNode = $field["ExtendedDataType"]
            $mandatoryNode = $field["Mandatory"]
            $labelNode = $field["Label"]

            $fields[$fieldName] = [PSCustomObject]@{
                Source           = "Fields"
                Type             = $typeAttr
                ExtendedDataType = if ($edtNode) { $edtNode.InnerText } else { $null }
                Mandatory        = if ($mandatoryNode) { $mandatoryNode.InnerText } else { $null }
                Label            = if ($labelNode) { $labelNode.InnerText } else { $null }
            }
        }
    }

    $modsNode = $root["FieldModifications"]
    if ($modsNode) {
        $modElements = @($modsNode.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        foreach ($mod in $modElements) {
            $nameNode = $mod["Name"]
            $modName = if ($nameNode) { $nameNode.InnerText } else { $null }
            if ([string]::IsNullOrWhiteSpace($modName)) { continue }

            $props = @{}
            $propModsNode = $mod["PropertyModifications"]
            if ($propModsNode) {
                $propElements = @($propModsNode.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
                foreach ($p in $propElements) {
                    $pNameNode = $p["Name"]
                    $pValueNode = $p["Value"]
                    if ($pNameNode) {
                        $props[$pNameNode.InnerText] = if ($pValueNode) { $pValueNode.InnerText } else { $null }
                    }
                }
            }

            # If this field already exists (added under <Fields> too, unusual but possible), merge; otherwise create.
            $fields[$modName] = [PSCustomObject]@{
                Source           = "FieldModifications"
                Type             = $props["Type"]
                ExtendedDataType = $props["ExtendedDataType"]
                Mandatory        = $props["Mandatory"]
                Label            = $props["Label"]
            }
        }
    }

    return $fields
}

function Compare-ObjectFields {
    param(
        [hashtable]$OldFields,
        [hashtable]$NewFields,
        [string]$ObjectName,
        [string]$ObjectType,
        [string]$FilePath
    )

    $changes = @()

    # New/added fields
    foreach ($name in $NewFields.Keys) {
        if (-not $OldFields.ContainsKey($name)) {
            $changes += [PSCustomObject]@{
                ObjectType  = $ObjectType
                ObjectName  = $ObjectName
                FilePath    = $FilePath
                FieldName   = $name
                ChangeType  = "Field Added"
                OldRawType  = $null
                OldEDT      = $null
                NewRawType  = $NewFields[$name].Type
                NewEDT      = $NewFields[$name].ExtendedDataType
            }
        }
    }

    # Deleted fields
    foreach ($name in $OldFields.Keys) {
        if (-not $NewFields.ContainsKey($name)) {
            $changes += [PSCustomObject]@{
                ObjectType  = $ObjectType
                ObjectName  = $ObjectName
                FilePath    = $FilePath
                FieldName   = $name
                ChangeType  = "Field Deleted"
                OldRawType  = $OldFields[$name].Type
                OldEDT      = $OldFields[$name].ExtendedDataType
                NewRawType  = $null
                NewEDT      = $null
            }
        }
    }

    # Type-changed / Mandatory-changed fields (present in both)
    foreach ($name in $NewFields.Keys) {
        if ($OldFields.ContainsKey($name)) {
            $old = $OldFields[$name]
            $new = $NewFields[$name]

            if ($old.Type -ne $new.Type -or $old.ExtendedDataType -ne $new.ExtendedDataType) {
                $changes += [PSCustomObject]@{
                    ObjectType  = $ObjectType
                    ObjectName  = $ObjectName
                    FilePath    = $FilePath
                    FieldName   = $name
                    ChangeType  = "Data Type Changed"
                    OldRawType  = $old.Type
                    OldEDT      = $old.ExtendedDataType
                    NewRawType  = $new.Type
                    NewEDT      = $new.ExtendedDataType
                }
            }
            elseif ($old.Mandatory -ne $new.Mandatory) {
                $changes += [PSCustomObject]@{
                    ObjectType    = $ObjectType
                    ObjectName    = $ObjectName
                    FilePath      = $FilePath
                    FieldName     = $name
                    ChangeType    = "Mandatory Flag Changed"
                    OldRawType    = $old.Type
                    OldEDT        = $old.ExtendedDataType
                    NewRawType    = $new.Type
                    NewEDT        = $new.ExtendedDataType
                    OldMandatory  = $old.Mandatory
                    NewMandatory  = $new.Mandatory
                }
            }
        }
    }

    # NOTE: array-wrapping is handled at the call site with @(...) instead of here,
    # to avoid double-wrapping empty arrays into a phantom single "empty" entry.
    return $changes
}

function Get-NamedChildElements {
    <#
        Generic section-level extractor. Pulls every child element under a given
        parent node (e.g. Relations, Indexes, FieldGroups, DeleteActions), keyed by
        its <Name> child, with a whitespace-normalized OuterXml snapshot used purely
        for equality comparison (not structured field-by-field comparison).
    #>
    param([xml]$Xml, [string]$ParentNodeName, [string]$KeyChildName = "Name")

    $result = @{}
    $root = $Xml.DocumentElement
    if (-not $root) { return $result }

    $parent = $root[$ParentNodeName]
    if (-not $parent) { return $result }

    $children = @($parent.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    foreach ($child in $children) {
        $keyNode = $child[$KeyChildName]
        $key = if ($keyNode) { $keyNode.InnerText } else { "unnamed_$($result.Count)" }
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $result[$key] = ($child.OuterXml -replace '\s+', ' ').Trim()
    }
    return $result
}

function Compare-NamedNodes {
    <#
        Generic section-level differ - Added / Deleted / Modified - for whatever
        was extracted by Get-NamedChildElements. Modified is a whole-node string
        comparison, so it will catch relation deletions, cluster key / index
        definition changes, field group membership changes, etc. It can also flag
        cosmetic-only XML differences; see the header note for the tradeoff.
    #>
    param(
        [hashtable]$OldNodes,
        [hashtable]$NewNodes,
        [string]$ObjectName,
        [string]$ObjectType,
        [string]$FilePath,
        [string]$Category
    )

    $changes = @()

    foreach ($name in $NewNodes.Keys) {
        if (-not $OldNodes.ContainsKey($name)) {
            $changes += [PSCustomObject]@{
                ObjectType = $ObjectType; ObjectName = $ObjectName; FilePath = $FilePath
                FieldName  = "$Category`: $name"; ChangeType = "$Category Added"
                OldRawType = $null; OldEDT = $null; NewRawType = $null; NewEDT = $null
            }
        }
    }
    foreach ($name in $OldNodes.Keys) {
        if (-not $NewNodes.ContainsKey($name)) {
            $changes += [PSCustomObject]@{
                ObjectType = $ObjectType; ObjectName = $ObjectName; FilePath = $FilePath
                FieldName  = "$Category`: $name"; ChangeType = "$Category Deleted"
                OldRawType = $null; OldEDT = $null; NewRawType = $null; NewEDT = $null
            }
        }
    }
    foreach ($name in $NewNodes.Keys) {
        if ($OldNodes.ContainsKey($name) -and $OldNodes[$name] -ne $NewNodes[$name]) {
            $changes += [PSCustomObject]@{
                ObjectType = $ObjectType; ObjectName = $ObjectName; FilePath = $FilePath
                FieldName  = "$Category`: $name"; ChangeType = "$Category Modified"
                OldRawType = $null; OldEDT = $null; NewRawType = $null; NewEDT = $null
            }
        }
    }

    return $changes
}

function Get-SimpleTablePropertiesFromXml {
    <#
        Catches scalar/leaf table-level properties directly under the root element
        (e.g. whichever property represents the clustered index, PrimaryIndex,
        TableGroup, etc.) without needing to hardcode the exact tag name. Any root
        child element that itself has no element children is treated as a simple
        property and captured by name/value.
    #>
    param([xml]$Xml)

    $props = @{}
    $root = $Xml.DocumentElement
    if (-not $root) { return $props }

    foreach ($child in $root.ChildNodes) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $hasElementChildren = @($child.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element }).Count -gt 0
        if (-not $hasElementChildren) {
            $props[$child.Name] = $child.InnerText
        }
    }
    return $props
}

function ConvertTo-FriendlyType {
    <#
        Converts D365's internal type codes (e.g. AxTableFieldEnum) into plain-English
        labels a functional/business user can understand, optionally combined with the
        ExtendedDataType name for extra context (e.g. "Choice List (NoYesId)").
    #>
    param([string]$RawType, [string]$Edt)

    if (-not $RawType -and -not $Edt) { return "" }

    $category = switch -Regex ($RawType) {
        'UnmappedField(String|Container)$' { "Computed Text Field"; break }
        'UnmappedFieldReal$'               { "Computed Decimal Field"; break }
        'UnmappedField(Int64|Int)$'        { "Computed Whole Number Field"; break }
        'MappedField$'                     { "Mapped Field"; break }
        'String$'                          { "Text"; break }
        'Int64$'                           { "Whole Number (Large)"; break }
        '(Int32|Int)$'                     { "Whole Number"; break }
        'Real$'                            { "Decimal Number"; break }
        'Enum$'                            { "Choice List"; break }
        'UtcDateTime$'                     { "Date & Time"; break }
        'Date$'                            { "Date"; break }
        'Guid$'                            { "Unique ID"; break }
        'Container$'                       { "Container"; break }
        default {
            if ($RawType) { ($RawType -replace '^Ax(Table|DataEntityView)Field', '') } else { "" }
        }
    }

    if ($Edt) {
        if ($category) { return "$category ($Edt)" } else { return $Edt }
    }
    return $category
}

function ConvertTo-ReportHtml {
    <#
        Builds a simple, readable HTML email body from the report data:
        summary counts, high-priority items in full, new objects as a compact
        list, and field-level changes on existing objects called out separately
        (since that's the primary thing being watched for).
    #>
    param(
        [array]$DisplayReport,
        [array]$FieldLevelOnly,
        [array]$NewObjectRows,
        [int]$HighPriorityCount,
        [int]$InfoCount,
        [string]$ReportGeneratedAt,
        [string]$Branch
    )

    $style = @"
<style>
  body { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; color: #222; }
  h2 { color: #0b5394; margin-bottom: 4px; }
  h3 { margin-bottom: 4px; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
  th, td { border: 1px solid #ccc; padding: 5px 8px; text-align: left; font-size: 12px; }
  th { background-color: #0b5394; color: white; }
  tr:nth-child(even) { background-color: #f5f5f5; }
  .high { color: #b30000; font-weight: bold; }
  .info { color: #555; }
  .meta { color: #555; font-size: 12px; margin-bottom: 12px; }
</style>
"@

    $highRows = @($DisplayReport | Where-Object { $_.Priority -eq "Action Required" })

    $highTableRows = if ($highRows.Count -gt 0) {
        ($highRows | ForEach-Object {
            "<tr><td>$($_.'Object Type')</td><td>$($_.'Object Name')</td><td>$($_.'Field Name')</td><td>$($_.'Change Type')</td><td>$($_.'Changed On')</td><td>$($_.Description)</td></tr>"
        }) -join "`n"
    } else {
        "<tr><td colspan='6'>None</td></tr>"
    }

    $fieldTableRows = if ($FieldLevelOnly.Count -gt 0) {
        ($FieldLevelOnly | ForEach-Object {
            "<tr><td>$($_.'Object Type')</td><td>$($_.'Object Name')</td><td>$($_.'Field Name')</td><td>$($_.'Change Type')</td><td>$($_.'Changed On')</td><td>$($_.'Previous Type')</td><td>$($_.'New Type')</td></tr>"
        }) -join "`n"
    } else {
        "<tr><td colspan='7'>None - no field additions/removals/type changes on existing objects.</td></tr>"
    }

    $newObjectTableRows = if ($NewObjectRows.Count -gt 0) {
        ($NewObjectRows | Group-Object "Object Name" | ForEach-Object {
            $first = $_.Group[0]
            "<tr><td>$($first.'Object Type')</td><td>$($_.Name)</td><td>$($_.Count)</td><td>$($first.'Changed On')</td></tr>"
        }) -join "`n"
    } else {
        "<tr><td colspan='4'>None</td></tr>"
    }

    $html = @"
<html>
<head>$style</head>
<body>
  <h2>D365 F&amp;O Metadata Change Report</h2>
  <div class="meta">
    Report generated: $ReportGeneratedAt<br/>
    Branch: $Branch
  </div>

  <h3>Summary</h3>
  <p><span class="high">Action Required: $HighPriorityCount</span> &nbsp;|&nbsp; <span class="info">Info: $InfoCount</span></p>

  <h3>Action Required Items</h3>
  <table>
    <tr><th>Object Type</th><th>Object Name</th><th>Field Name</th><th>Change Type</th><th>Changed On</th><th>Description</th></tr>
    $highTableRows
  </table>

  <h3>Field-Level Changes on Existing Objects</h3>
  <table>
    <tr><th>Object Type</th><th>Object Name</th><th>Field Name</th><th>Change Type</th><th>Changed On</th><th>Previous Type</th><th>New Type</th></tr>
    $fieldTableRows
  </table>

  <h3>New Objects Created</h3>
  <table>
    <tr><th>Object Type</th><th>Object Name</th><th>Field Count</th><th>Changed On</th></tr>
    $newObjectTableRows
  </table>

  <p style="color:#888; font-size:11px;">Automatically generated by the D365 metadata change detection pipeline step.</p>
</body>
</html>
"@

    return $html
}

function Send-ChangeReportEmail {
    <#
        Sends the HTML report via SendGrid's v3 mail/send API. Silently does
        nothing (with a log note) if ApiKey/From/To aren't all supplied - so this
        is safe to call unconditionally from Main without extra guard logic
        everywhere else.
    #>
    param(
        [string]$ApiKey,
        [string]$FromAddress,
        [string]$ToAddresses,
        [string]$Subject,
        [string]$HtmlBody
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey) -or [string]::IsNullOrWhiteSpace($FromAddress) -or [string]::IsNullOrWhiteSpace($ToAddresses)) {
        Write-Host "Email not sent - SendGridKey/EmailFrom/EmailTo not all supplied." -ForegroundColor DarkGray
        return
    }

    $toList = $ToAddresses -split ',' | ForEach-Object { @{ email = $_.Trim() } }

    $payload = @{
        personalizations = @(@{ to = @($toList) })
        from             = @{ email = $FromAddress }
        subject          = $Subject
        content          = @(@{ type = "text/html"; value = $HtmlBody })
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri "https://api.sendgrid.com/v3/mail/send" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" } `
            -Body $payload | Out-Null
        Write-Host "Email report sent to: $ToAddresses" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to send email report via SendGrid: $($_.Exception.Message)"
    }
}

# ---- Main ----

Write-Host "Getting changed files between $FromCommit and $ToCommit..." -ForegroundColor Cyan

$changedFiles = git diff --name-only $FromCommit $ToCommit |
    Where-Object {
        $_ -match '/AxTable/|/AxTableExtension/|/AxDataEntityView/|/AxDataEntityViewExtension/' -and
        $_ -match '\.xml$'
    }

Write-Host "Found $($changedFiles.Count) changed metadata files" -ForegroundColor Cyan

# Sections (besides Fields/FieldModifications) diffed as whole named nodes.
# Explicit singular names below (do NOT derive with TrimEnd('s') - "Indexes" -> "Indexe" is wrong
# and silently breaks the $friendlyChangeTypeMap / $priorityMap lookups further down).
$structuralSections = @{
    "Relations"     = "Relation"
    "Indexes"       = "Index"
    "FieldGroups"   = "FieldGroup"
    "DeleteActions" = "DeleteAction"
}

$allChanges = @()

foreach ($file in $changedFiles) {

    $objectType = Get-ObjectType -FilePath $file
    $objectName = [System.IO.Path]::GetFileNameWithoutExtension($file) -replace '\.Metcash$', ''

    $oldContent = Get-FileContentAtCommit -Commit $FromCommit -FilePath $file
    $newContent = Get-FileContentAtCommit -Commit $ToCommit -FilePath $file
    $changedOn  = Get-FileChangeDate -FromCommit $FromCommit -ToCommit $ToCommit -FilePath $file

    # Handle new files (didn't exist before) - everything is "added"
    if (-not $oldContent -and $newContent) {
        try {
            [xml]$newXml = $newContent
            $newFields = Get-FieldsFromXml -Xml $newXml
            foreach ($name in $newFields.Keys) {
                $allChanges += [PSCustomObject]@{
                    ObjectType = $objectType; ObjectName = $objectName; FilePath = $file; ChangedOn = $changedOn
                    FieldName  = $name; ChangeType = "Field Added (New Object)"
                    OldRawType = $null; OldEDT = $null
                    NewRawType = $newFields[$name].Type; NewEDT = $newFields[$name].ExtendedDataType
                }
            }
            Write-Host "  Processed: $file (NEW OBJECT - did not exist at $FromCommit - $($newFields.Count) field(s) added - changed on $changedOn)" -ForegroundColor DarkGray
        } catch { Write-Warning "Failed to parse new file: $file - $_" }
        continue
    }

    # Handle deleted files - everything is "deleted"
    if ($oldContent -and -not $newContent) {
        try {
            [xml]$oldXml = $oldContent
            $oldFields = Get-FieldsFromXml -Xml $oldXml
            foreach ($name in $oldFields.Keys) {
                $allChanges += [PSCustomObject]@{
                    ObjectType = $objectType; ObjectName = $objectName; FilePath = $file; ChangedOn = $changedOn
                    FieldName  = $name; ChangeType = "Field Deleted (Object Removed)"
                    OldRawType = $oldFields[$name].Type; OldEDT = $oldFields[$name].ExtendedDataType
                    NewRawType = $null; NewEDT = $null
                }
            }
            Write-Host "  Processed: $file (OBJECT REMOVED - no longer exists at $ToCommit - $($oldFields.Count) field(s) removed - changed on $changedOn)" -ForegroundColor DarkGray
        } catch { Write-Warning "Failed to parse old file: $file - $_" }
        continue
    }

    # Normal case - object exists at both commits, compare fields + structure
    if ($oldContent -and $newContent) {
        try {
            [xml]$oldXml = $oldContent
            [xml]$newXml = $newContent

            $oldFields = Get-FieldsFromXml -Xml $oldXml
            $newFields = Get-FieldsFromXml -Xml $newXml

            $changes = @(Compare-ObjectFields -OldFields $oldFields -NewFields $newFields `
                -ObjectName $objectName -ObjectType $objectType -FilePath $file)

            # Structural sections: Relations, Indexes (incl. cluster key changes),
            # FieldGroups, DeleteActions - whole-node comparison so nothing here is
            # silently missed just because field names/types/count didn't change.
            foreach ($section in $structuralSections.Keys) {
                $singularCategory = $structuralSections[$section]
                $oldNodes = Get-NamedChildElements -Xml $oldXml -ParentNodeName $section
                $newNodes = Get-NamedChildElements -Xml $newXml -ParentNodeName $section
                $changes += @(Compare-NamedNodes -OldNodes $oldNodes -NewNodes $newNodes `
                    -ObjectName $objectName -ObjectType $objectType -FilePath $file -Category $singularCategory)
            }

            # Scalar/leaf table-level properties (e.g. clustered index pointer, TableGroup, etc.)
            $oldProps = Get-SimpleTablePropertiesFromXml -Xml $oldXml
            $newProps = Get-SimpleTablePropertiesFromXml -Xml $newXml
            foreach ($propName in $newProps.Keys) {
                if ($oldProps.ContainsKey($propName) -and $oldProps[$propName] -ne $newProps[$propName]) {
                    $changes += [PSCustomObject]@{
                        ObjectType = $objectType; ObjectName = $objectName; FilePath = $file
                        FieldName  = "Property: $propName"; ChangeType = "Table Property Changed"
                        OldRawType = $oldProps[$propName]; OldEDT = $null
                        NewRawType = $newProps[$propName]; NewEDT = $null
                    }
                }
            }

            # Stamp ChangedOn onto every change record produced for this file
            # (Compare-ObjectFields / Compare-NamedNodes don't know about it, so add it here).
            $changes = $changes | ForEach-Object {
                $_ | Add-Member -NotePropertyName ChangedOn -NotePropertyValue $changedOn -Force -PassThru
            }

            # Split into field-level vs structural/other so the log line can't be
            # misread as "field count is the same, so what does total changes:1 mean?"
            $fieldLevelChangeTypes = @("Field Added", "Field Deleted", "Data Type Changed", "Mandatory Flag Changed")
            $fieldLevelChanges     = @($changes | Where-Object { $_.ChangeType -in $fieldLevelChangeTypes })
            $structuralChanges     = @($changes | Where-Object { $_.ChangeType -notin $fieldLevelChangeTypes })

            Write-Host "  Processed: $file (fields: $($oldFields.Count) -> $($newFields.Count) | field-level changes: $($fieldLevelChanges.Count) | other (index/relation/property) changes: $($structuralChanges.Count) | changed on $changedOn)" -ForegroundColor DarkGray
            if ($fieldLevelChanges.Count -gt 0) {
                $fieldBreakdown = ($fieldLevelChanges | Group-Object ChangeType | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ", "
                Write-Host "    -> FIELD CHANGES: $fieldBreakdown" -ForegroundColor Yellow
            }
            if ($structuralChanges.Count -gt 0) {
                $structuralBreakdown = ($structuralChanges | Group-Object ChangeType | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ", "
                Write-Host "    -> OTHER (non-field) CHANGES: $structuralBreakdown" -ForegroundColor DarkGray
            }

            $allChanges += $changes
        } catch {
            Write-Warning "Failed to parse/compare: $file - $($_.Exception.Message)"
        }
    }
}

# ---- Build the business-friendly report ----

# Defensive filter: drop any malformed entries (shouldn't happen now, but protects
# downstream Sort-Object/ContainsKey calls from throwing on unexpected nulls)
$allChanges = @($allChanges | Where-Object { $_ -and $_.ChangeType })

$friendlyChangeTypeMap = @{
    "Field Added"                     = "New Field Added"
    "Field Deleted"                   = "Field Removed"
    "Data Type Changed"               = "Data Type Changed"
    "Mandatory Flag Changed"          = "Mandatory Setting Changed"
    "Field Added (New Object)"        = "New Field Added (New Object Created)"
    "Field Deleted (Object Removed)"  = "Field Removed (Object Deleted)"
    "Relation Added"                  = "Relation Added"
    "Relation Deleted"                = "Relation Removed"
    "Relation Modified"               = "Relation Changed"
    "Index Added"                     = "Index Added"
    "Index Deleted"                   = "Index Removed"
    "Index Modified"                  = "Index Changed (fields, clustering, and/or uniqueness)"
    "FieldGroup Added"                = "Field Group Added"
    "FieldGroup Deleted"              = "Field Group Removed"
    "FieldGroup Modified"             = "Field Group Changed"
    "DeleteAction Added"              = "Delete Action Added"
    "DeleteAction Deleted"            = "Delete Action Removed"
    "DeleteAction Modified"           = "Delete Action Changed"
    "Table Property Changed"          = "Table Property Changed"
}

$priorityMap = @{
    "Field Added"                     = "Info"
    "Field Added (New Object)"        = "Info"
    "Field Deleted"                   = "Action Required"
    "Field Deleted (Object Removed)"  = "Action Required"
    "Data Type Changed"               = "Action Required"
    "Mandatory Flag Changed"          = "Review Suggested"
    "Relation Deleted"                = "Action Required"
    "Relation Added"                  = "Review Suggested"
    "Relation Modified"               = "Review Suggested"
    "Index Deleted"                   = "Action Required"
    "Index Modified"                  = "Action Required"
    "Index Added"                     = "Info"
    "FieldGroup Deleted"              = "Review Suggested"
    "FieldGroup Added"                = "Info"
    "FieldGroup Modified"             = "Review Suggested"
    "DeleteAction Deleted"            = "Action Required"
    "DeleteAction Added"              = "Review Suggested"
    "DeleteAction Modified"           = "Action Required"
    "Table Property Changed"          = "Action Required"
}
$prioritySortOrder = @{ "Action Required" = 1; "Review Suggested" = 2; "Info" = 3 }

$friendlyReport = foreach ($c in $allChanges) {
    $oldFriendly = ConvertTo-FriendlyType -RawType $c.OldRawType -Edt $c.OldEDT
    $newFriendly = ConvertTo-FriendlyType -RawType $c.NewRawType -Edt $c.NewEDT

    $friendlyChangeType = if ($friendlyChangeTypeMap.ContainsKey($c.ChangeType)) { $friendlyChangeTypeMap[$c.ChangeType] } else { $c.ChangeType }
    $priority = if ($priorityMap.ContainsKey($c.ChangeType)) { $priorityMap[$c.ChangeType] } else { "Info" }

    $description = switch -Wildcard ($c.ChangeType) {
        "Field Added*" {
            "New field '$($c.FieldName)' ($newFriendly) was added to $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Field Deleted*" {
            "Field '$($c.FieldName)' (was $oldFriendly) was removed from $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Data Type Changed" {
            "Field '$($c.FieldName)' in $($c.ObjectType) '$($c.ObjectName)' changed from '$oldFriendly' to '$newFriendly'."
        }
        "Mandatory Flag Changed" {
            "Field '$($c.FieldName)' in $($c.ObjectType) '$($c.ObjectName)' mandatory setting changed from '$($c.OldMandatory)' to '$($c.NewMandatory)'."
        }
        "Relation Added" {
            "$($c.FieldName) was added on $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Relation Deleted" {
            "$($c.FieldName) was removed from $($c.ObjectType) '$($c.ObjectName)'. Review dependent forms/processes that relied on this relation."
        }
        "Relation Modified" {
            "$($c.FieldName) definition changed on $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Index Added" {
            "$($c.FieldName) was added on $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Index Deleted" {
            "$($c.FieldName) was removed from $($c.ObjectType) '$($c.ObjectName)'."
        }
        "Index Modified" {
            "$($c.FieldName) changed on $($c.ObjectType) '$($c.ObjectName)' - this includes clustered index / key changes. Verify which index and whether it affects performance or uniqueness."
        }
        "FieldGroup*" {
            "$($c.FieldName) changed on $($c.ObjectType) '$($c.ObjectName)'."
        }
        "DeleteAction*" {
            "$($c.FieldName) changed on $($c.ObjectType) '$($c.ObjectName)'. Review cascade delete behavior."
        }
        "Table Property Changed" {
            "$($c.FieldName) on $($c.ObjectType) '$($c.ObjectName)' changed from '$($c.OldRawType)' to '$($c.NewRawType)'."
        }
        default {
            "Field '$($c.FieldName)' in $($c.ObjectType) '$($c.ObjectName)' was modified."
        }
    }

    [PSCustomObject]@{
        "Object Type"   = $c.ObjectType
        "Object Name"   = $c.ObjectName
        "Field Name"    = $c.FieldName
        "Change Type"   = $friendlyChangeType
        "Priority"      = $priority
        "Previous Type" = if ($oldFriendly) { $oldFriendly } elseif ($c.OldRawType) { $c.OldRawType } else { "(new)" }
        "New Type"      = if ($newFriendly) { $newFriendly } elseif ($c.NewRawType) { $c.NewRawType } else { "(removed)" }
        "Changed On"    = if ($c.ChangedOn) { $c.ChangedOn } else { "Unknown" }
        "Description"   = $description
        "File Path"     = $c.FilePath
    }
}

$friendlyReport = @($friendlyReport | Sort-Object { $prioritySortOrder[$_.Priority] }, "Object Type", "Object Name")

# ---- Build a display-only version that collapses brand-new objects ----
# When a whole object is new, listing every one of its fields individually is
# noise (25+ rows for one new table). Collapse those into a single summary row
# per object. Everything else (deletions, type changes, structural changes on
# EXISTING objects) stays fully detailed since those are what actually need review.
# NOTE: this collapsing is display-only - $friendlyReport itself (used for the
# Summary / Priority breakdown counts below) is untouched, so those counts still
# reflect the true number of underlying field-level changes.
$newObjectRows = @($friendlyReport | Where-Object { $_."Change Type" -like "New Field Added (New Object Created)*" })
$otherRows     = @($friendlyReport | Where-Object { $_."Change Type" -notlike "New Field Added (New Object Created)*" })

$collapsedNewObjectRows = $newObjectRows | Group-Object "Object Name" | ForEach-Object {
    $first = $_.Group[0]
    [PSCustomObject]@{
        "Object Type"   = $first."Object Type"
        "Object Name"   = $_.Name
        "Field Name"    = "(all fields)"
        "Change Type"   = "New Object Created"
        "Priority"      = "Info"
        "Previous Type" = "(new)"
        "New Type"      = "-"
        "Changed On"    = $first."Changed On"
        "Description"   = "New object created with $($_.Count) field(s). See git history for full field list if needed."
        "File Path"     = $first."File Path"
    }
}

$displayReport = @($otherRows + $collapsedNewObjectRows) | Sort-Object { $prioritySortOrder[$_.Priority] }, "Object Type", "Object Name"

# ---- Print report as a table directly in the pipeline log ----
# (CSV export is disabled for now since the file isn't reachable off the build
# agent without an extra "Publish Artifact" pipeline step - printing to the log
# instead so the report is visible without any pipeline changes.)

$reportGeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss (K)"

Write-Host "`n================================ FIELD & METADATA CHANGE REPORT ================================" -ForegroundColor Cyan
Write-Host "Report generated: $reportGeneratedAt" -ForegroundColor Cyan
Write-Host "Commit range:     $FromCommit -> $ToCommit" -ForegroundColor Cyan
Write-Host "Repo path:        $RepoPath" -ForegroundColor Cyan
Write-Host ""

if ($displayReport.Count -eq 0) {
    Write-Host "No reportable changes found." -ForegroundColor Yellow
} else {
    $tableText = $displayReport |
        Select-Object "Object Type", "Object Name", "Field Name", "Change Type", "Priority", "Changed On", "Previous Type", "New Type" |
        Format-Table -AutoSize |
        Out-String -Width 4096

    Write-Host $tableText

    Write-Host "-------------------------------------- Details --------------------------------------" -ForegroundColor Cyan
    foreach ($row in $displayReport) {
        Write-Host "  [$($row.Priority)] $($row.'Object Type') / $($row.'Object Name') - $($row.'Field Name')" -ForegroundColor White
        Write-Host "      Changed on: $($row.'Changed On')" -ForegroundColor Gray
        Write-Host "      $($row.Description)" -ForegroundColor Gray
        Write-Host "      File: $($row.'File Path')" -ForegroundColor DarkGray
    }
}

Write-Host "==================================================================================================" -ForegroundColor Cyan

# ---- Quick view: field-level changes only (on existing objects) ----
# Isolates just Field Added / Field Deleted / Data Type Changed / Mandatory Flag Changed
# on objects that already existed - i.e. the core "did a field change" question - separate
# from structural noise (index/relation changes) and brand-new object creation.
$fieldLevelOnly = @($otherRows | Where-Object {
    $_."Change Type" -in @("New Field Added", "Field Removed", "Data Type Changed", "Mandatory Setting Changed")
})

Write-Host "`n-------------------------------- FIELD-LEVEL CHANGES ONLY (existing objects) --------------------------------" -ForegroundColor Magenta
if ($fieldLevelOnly.Count -eq 0) {
    Write-Host "  None - no field additions/removals/type changes on existing objects in this window." -ForegroundColor Yellow
} else {
    $fieldLevelOnly |
        Select-Object "Object Type", "Object Name", "Field Name", "Change Type", "Changed On", "Previous Type", "New Type" |
        Format-Table -AutoSize |
        Out-String -Width 4096 |
        Write-Host
}
Write-Host "-----------------------------------------------------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "Report generated: $reportGeneratedAt" -ForegroundColor Cyan

Write-Host "`nSummary:" -ForegroundColor Green
if ($newObjectRows.Count -gt 0) {
    $newObjectCount = ($newObjectRows | Group-Object "Object Name").Count
    Write-Host "  New objects created: $newObjectCount (totaling $($newObjectRows.Count) new field(s) - see collapsed rows above)" -ForegroundColor Yellow
}
$friendlyReport | Where-Object { $_."Change Type" -notlike "New Field Added (New Object Created)*" } | Group-Object "Change Type" | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow
}
Write-Host "`nBreakdown by priority:" -ForegroundColor Green
$highPriorityCount = 0
$infoCount = 0
$friendlyReport | Group-Object Priority | Sort-Object { $prioritySortOrder[$_.Name] } | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow
    if ($_.Name -eq "Action Required") { $highPriorityCount = $_.Count }
    if ($_.Name -eq "Info") { $infoCount = $_.Count }
}

# ---- Email the report via SendGrid - only when there is something to report ----
# (Send-ChangeReportEmail itself no-ops safely if SendGridKey/EmailFrom/EmailTo
# weren't all supplied, so this call is always safe to leave in place.)
if ($friendlyReport.Count -gt 0) {
    $emailHtml = ConvertTo-ReportHtml -DisplayReport $displayReport -FieldLevelOnly $fieldLevelOnly `
        -NewObjectRows $newObjectRows -HighPriorityCount $highPriorityCount -InfoCount $infoCount `
        -ReportGeneratedAt $reportGeneratedAt -Branch $Branch

    $emailSubject = "D365 Metadata Change Report - $reportGeneratedAt"

    Send-ChangeReportEmail -ApiKey $SendGridKey -FromAddress $EmailFrom -ToAddresses $EmailTo `
        -Subject $emailSubject -HtmlBody $emailHtml
} else {
    Write-Host "No reportable changes - email skipped." -ForegroundColor DarkGray
}

# When ready to go back to a downloadable file, re-enable this line and add a
# "Publish Pipeline Artifact" (or "Publish Build Artifacts") task after this
# PowerShell step in the pipeline, pointing at $(OutputPath):
# $friendlyReport | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
# Write-Host "`nFull report saved to: $OutputPath" -ForegroundColor Green

# Fail the pipeline step if you want deletions/type-changes/structural changes to require manual review:
# $breaking = $friendlyReport | Where-Object { $_.Priority -eq "Action Required" }
# if ($breaking.Count -gt 0) {
#     Write-Host "##vso[task.logissue type=warning]$($breaking.Count) high-priority change(s) detected. Review the log above."
# }