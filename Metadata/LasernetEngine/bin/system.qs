//******************************************************************************
// Public functions:
//******************************************************************************

 //-----------------------------------------------------------------------------
 // Sleep
 //-----------------------------------------------------------------------------
//:group System
function sleep(sleepDuration)
{
	Sleep(sleepDuration);
}

 //-----------------------------------------------------------------------------
 // CreateDirectory
 //-----------------------------------------------------------------------------
//:group System
function createDirectory(path)
{
	var re = /\\/g;
	path = path.replace(re, '/');
	var d = new Dir(path);
	if (!d.exists)
	{
		d.cdUp();
		var dir = path.substring(path.lastIndexOf('/') + 1);
		d.mkdir(dir);
	}
}

 //-----------------------------------------------------------------------------
 // CreateDirectories
 //-----------------------------------------------------------------------------
//:group System
function createDirectories(path)
{
	var re = /\\/g;
	path = path.replace(re, '/');
	var d = new Dir();
	d.mkdirs(path);
}

 //-----------------------------------------------------------------------------
 // loadJobInfoFromFile
 //-----------------------------------------------------------------------------
// Loads the contents of a file in to the a JobInfo with the given name
//:group System
function loadJobInfoFromFile(jobInfoName, filename, replace)
{
	var file = new File(filename);
	if (file.exists())
	{
		if (file.open(IO_ReadOnly))
		{
			var allfile = file.readAll();
			file.close();
			job.setJobInfoBinary(jobInfoName, allfile, replace);
			return true;
		}
	}
	return false;
}

 //-----------------------------------------------------------------------------
 // saveJobInfoToFile
 //-----------------------------------------------------------------------------
// Saves the contents of the given JobInfo into a file with the given filename
//:group System
function saveJobInfoToFile(jobInfoName, filename)
{
	File.writeBinary(filename, job.getJobInfoBinary(jobInfoName, 0));
}

 //-----------------------------------------------------------------------------
 // setJobInfo
 //-----------------------------------------------------------------------------
// Sets the value of a jobinfo.
// (replace is optional, default = true)
// (logLevel is optional, default = JobInfo)
//  logLevel can be:
//  JobInfo - Job Info events
//  Debug   - debug level events
//  NoLog   - no log
//  event IDs from 100 and up are free to use as custom events
//:group System
function setJobInfo(jobInfoName, value, replace, logLevel)
{
	if (arguments.length < 3)
        job.setJobInfo(jobInfoName, value);
    else if (arguments.length < 4)
        job.setJobInfo(jobInfoName, value, replace)
    else
        job.setJobInfo(jobInfoName, value, replace, logLevel);
}

 //-----------------------------------------------------------------------------
 // getJobInfo
 //-----------------------------------------------------------------------------
// Returns the value of a jobinfo at a given index
// (index is optional, defaults = 0)
//:group System
function getJobInfo(jobInfoName, index)
{
	if (arguments.length < 2)
        return job.getJobInfo(jobInfoName);
    else
        return job.getJobInfo(jobInfoName, index);
}

 //-----------------------------------------------------------------------------
 // addDestination
 //-----------------------------------------------------------------------------
// Adds a destination to a job.
// (replace is optional, default = true)
//:group System
function addDestination(destination, replace)
{
	if (arguments.length < 2)
        job.addDestination(destination);
    else
        job.addDestination(destination, replace);
}

 //-----------------------------------------------------------------------------
 // SplitException
 //-----------------------------------------------------------------------------
//:private
function splitException(exception)
{
	var splitRegExp = /(.+)\.(.+):(.*)/g;
	exception.match(splitRegExp);
	var result;
	result[0] = splitRegExp.cap(0);
	result[1] = splitRegExp.cap(1);
	result[2] = splitRegExp.cap(2);
}


 //*****************************************************************************
 // Constants:
 //*****************************************************************************

const IO_RAW		= 64;		// raw access (not buffered)
const IO_Async		= 128;		// asynchronous mode
const IO_ReadOnly	= 1;		// readable device
const IO_WriteOnly	= 2;		// writable device
const IO_ReadWrite	= 3;		// read+write device
const IO_Append		= 4;		// append
const IO_Truncate	= 8;		// truncate device
const IO_Translate	= 16;		// translate CR+LF
const IO_Text		= 16;		// translate CR+LF

const EID_SYSTEM = 0;
const EID_DEBUG = 1;
const EID_ERROR = 2;
const EID_WARNING = 3;
const EID_IMMEDIATE = 4;
const EID_NOLOG = 8;
const EID_JOB   = 10;
const EID_JOB_INFO = 12;
const EID_EVENT_LOG = 13;
const EID_SYSLOG = 14;
const EID_NOLOG = 8;
const EID_CUSTOM = 100;

const JobInfo = EID_JOB_INFO;
const EventLog = EID_EVENT_LOG;
const Syslog = EID_SYSLOG;
const Debug = EID_DEBUG;
const NoLog = EID_NOLOG;

// Color constants

var red = 0xff0000;
var green = 0x00ff00;
var blue = 0x0000ff;
var white = 0xffffff;
var black = 0x000000;

// Minus Position Constants
var mpFront = 0;
var mpBack  = 1;

// Logger variable compatibility
var logger = Logger;

 //*****************************************************************************
 // String QSA compatibility functions:
 //*****************************************************************************

if (!String.prototype.substr)
{
	String.prototype.substr = function(index, size)
	{
		if (arguments.length < 2)
			return this.substring(index);
		else
			return this.substring(index, index+size);
	}
}

String.prototype.isEmpty = function()
{
	return this.length == 0;
}

String.prototype.left = function(size)
{
	return this.substr(0, size);
}

String.prototype.lower = function()
{
	return this.toLowerCase();
}

String.prototype.mid = function(pos,size)
{
	if (arguments.length < 2)
		return this.substr(pos);
	else
		return this.substr(pos, size);
}

String.prototype.right = function(size)
{
	if (this.length < size)
		return this.substr(0);
	return this.substr(this.length-size);
}

String.prototype.upper = function()
{
	return this.toUpperCase();
}

String.prototype.find = function(str)
{
	return this.indexOf(str);
}
