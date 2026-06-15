//:group Zip
function zipDirectory(directoryPath)
{
	return zipFilesInDirectory(directoryPath, /.*/, '');
}

//:group Zip
function zipFilesInDirectory(directoryPath, includeMatch, excludeMatch)
{
	var zipper = new Zip();
	zipper.newZipFile();
	zipFilesInDirectoryInternal(zipper, directoryPath, '', includeMatch, excludeMatch);
	return zipper.getZipFile();
}

//:private
function zipFilesInDirectoryInternal(zipper, directory, basepath, includeMatch, excludeMatch)
{
	var dir = new Dir(directory);
	if ((directory.mid(directory.length - 1, 1) != '\\') && (directory.mid(directory.length - 1, 1) != '/'))
		directory = directory + '\\';

	var filelist = dir.entryList('*', Dir.All);
	var idx;
	for (idx = 0; idx < filelist.length; idx++)
	{
		if (File.isFile(directory + filelist[idx]))
		{
			if ((filelist[idx].match(includeMatch) != undefined) && (filelist[idx].match(excludeMatch) == undefined))
				zipper.addFileFromDisk(directory + filelist[idx], basepath + filelist[idx]);
		}
	}
	
	for (idx = 0; idx < filelist.length; idx++)
	{
		if (File.isDir(directory + filelist[idx]) && filelist[idx] != '.' && filelist[idx] != '..')
		{
			zipFilesInDirectoryInternal(zipper, directory + filelist[idx] + '\\', basepath + filelist[idx] + '\\', includeMatch, excludeMatch);
		}
	}	
}
