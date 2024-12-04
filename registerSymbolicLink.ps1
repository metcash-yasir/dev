$AOSMetadataPath = "K:\AOSService\PackagesLocalDirectory"

$RepoPath = "K:\repos"
$RepoMetadataPath = $RepoPath + "\Metadata"
$RepoModelFolders = Get-ChildItem $RepoMetadataPath -Directory
foreach ($ModelFolder in $RepoModelFolders)
{
	$Target = "$RepoMetadataPath\$ModelFolder"
	New-Item -ItemType SymbolicLink -Path "$AOSMetadataPath" -Name "$ModelFolder" -Value "$Target"
}

<#K:\AOSService\PackagesLocalDirectory"#>