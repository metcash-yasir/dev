<#
.SYNOPSIS
    Detects field-level metadata changes (Added / Deleted / Data Type Changed) between two
    git commits for D365 F&O AxTable, AxTableExtension, AxDataEntityView, and
    AxDataEntityViewExtension XML files.

.DESCRIPTION
    Designed to run as a post-deployment step in an Azure DevOps Release pipeline.
    Compares the metadata XML at $FromCommit vs $ToCommit and produces a CSV report
    listing every field-level change, per object, with the change type.

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
    Where to write the CSV report.

.EXAMPLE
    # Nightly pipeline usage - "whatever changed in the last 24 hours", no commit tracking needed
    .\Get-D365FieldLevelChanges.ps1 -RepoPath "K:\CoreBuildGITRepo" -SinceHours 24 -OutputPath "K:\Reports\FieldChanges.csv"

.EXAMPLE
    # Manual / ad-hoc usage with explicit commits
    .\Get-D365FieldLevelChanges.ps1 -RepoPath "K:\CoreBuildGITRepo" -FromCommit "abc123" -ToCommit "def456" -OutputPath "K:\Reports\FieldChanges.csv"
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

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
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
    @() | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
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

# ---- Main ----

Write-Host "Getting changed files between $FromCommit and $ToCommit..." -ForegroundColor Cyan

$changedFiles = git diff --name-only $FromCommit $ToCommit |
    Where-Object {
        $_ -match '/AxTable/|/AxTableExtension/|/AxDataEntityView/|/AxDataEntityViewExtension/' -and
        $_ -match '\.xml$'
    }

Write-Host "Found $($changedFiles.Count) changed metadata files" -ForegroundColor Cyan

$allChanges = @()

foreach ($file in $changedFiles) {

    $objectType = Get-ObjectType -FilePath $file
    $objectName = [System.IO.Path]::GetFileNameWithoutExtension($file) -replace '\.Metcash$', ''

    $oldContent = Get-FileContentAtCommit -Commit $FromCommit -FilePath $file
    $newContent = Get-FileContentAtCommit -Commit $ToCommit -FilePath $file

    # Handle new files (didn't exist before) - everything is "added"
    if (-not $oldContent -and $newContent) {
        try {
            [xml]$newXml = $newContent
            $newFields = Get-FieldsFromXml -Xml $newXml
            foreach ($name in $newFields.Keys) {
                $allChanges += [PSCustomObject]@{
                    ObjectType = $objectType; ObjectName = $objectName; FilePath = $file
                    FieldName  = $name; ChangeType = "Field Added (New Object)"
                    OldRawType = $null; OldEDT = $null
                    NewRawType = $newFields[$name].Type; NewEDT = $newFields[$name].ExtendedDataType
                }
            }
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
                    ObjectType = $objectType; ObjectName = $objectName; FilePath = $file
                    FieldName  = $name; ChangeType = "Field Deleted (Object Removed)"
                    OldRawType = $oldFields[$name].Type; OldEDT = $oldFields[$name].ExtendedDataType
                    NewRawType = $null; NewEDT = $null
                }
            }
        } catch { Write-Warning "Failed to parse old file: $file - $_" }
        continue
    }

    # Normal case - object exists at both commits, compare fields
    if ($oldContent -and $newContent) {
        try {
            [xml]$oldXml = $oldContent
            [xml]$newXml = $newContent

            $oldFields = Get-FieldsFromXml -Xml $oldXml
            $newFields = Get-FieldsFromXml -Xml $newXml

            $changes = @(Compare-ObjectFields -OldFields $oldFields -NewFields $newFields `
                -ObjectName $objectName -ObjectType $objectType -FilePath $file)

            Write-Host "  Processed: $file (old fields: $($oldFields.Count), new fields: $($newFields.Count), changes: $($changes.Count))" -ForegroundColor DarkGray

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
}

$priorityMap = @{
    "Field Added"                     = "Info"
    "Field Added (New Object)"        = "Info"
    "Field Deleted"                   = "High - Review Required"
    "Field Deleted (Object Removed)"  = "High - Review Required"
    "Data Type Changed"               = "High - Review Required"
    "Mandatory Flag Changed"          = "Medium - Review Required"
}
$prioritySortOrder = @{ "High - Review Required" = 1; "Medium - Review Required" = 2; "Info" = 3 }

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
        "Previous Type" = if ($oldFriendly) { $oldFriendly } else { "(new field)" }
        "New Type"      = if ($newFriendly) { $newFriendly } else { "(removed)" }
        "Description"   = $description
        "File Path"     = $c.FilePath
    }
}

$friendlyReport = @($friendlyReport | Sort-Object { $prioritySortOrder[$_.Priority] }, "Object Type", "Object Name")

# Export report
$friendlyReport | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nSummary:" -ForegroundColor Green
$friendlyReport | Group-Object "Change Type" | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow
}
Write-Host "`nBreakdown by priority:" -ForegroundColor Green
$friendlyReport | Group-Object Priority | Sort-Object { $prioritySortOrder[$_.Name] } | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow
}
Write-Host "`nFull report saved to: $OutputPath" -ForegroundColor Green

# Fail the pipeline step if you want deletions/type-changes to require manual review:
# $breaking = $friendlyReport | Where-Object { $_.Priority -eq "High - Review Required" }
# if ($breaking.Count -gt 0) {
#     Write-Host "##vso[task.logissue type=warning]$($breaking.Count) high-priority field change(s) detected. Review $OutputPath"
# }
