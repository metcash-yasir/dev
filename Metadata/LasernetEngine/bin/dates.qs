var milliSecondsPerDay = 1000 * 60 * 60 * 24;

//:private
function getIsoWeekOne(year)
{
	var fourthJan = new Date(year, 0, 4);
	var fourthJanDay = fourthJan.getDay() - 1;
	if (fourthJanDay == -1)
		fourthJanDay = 6;
	var dateOfMondayInWeekOne = new Date();
	dateOfMondayInWeekOne.setTime(fourthJan.getTime() + (-fourthJanDay * milliSecondsPerDay));
	return dateOfMondayInWeekOne;
}

//:private
function ISOWeekNumberAndYear(dt)
{
	var week1;
	var isoYear = dt.getFullYear();
	if (dt > new Date(isoYear, 11, 29))
	{
		week1 = getIsoWeekOne(isoYear + 1);
		if (dt < week1)
		{
			week1 = getIsoWeekOne(isoYear);
		}
		else
		{
			isoYear++;
		}
	}
	else
	{
		week1 = getIsoWeekOne(isoYear);
		if (dt < week1)
		{
			week1 = getIsoWeekOne(--isoYear);
		}
	}
	
	return (isoYear * 100) + Math.floor(((dt.getTime() - week1.getTime()) / milliSecondsPerDay / 7)) + 1;
}

//:group Dates
function ISOWeekNumber(dt)
{
	return ISOWeekNumberAndYear(dt) % 100;
}

//:group Dates
function ISOYear(dt)
{
	return Math.floor(ISOWeekNumberAndYear(dt) / 100);
}

//:group Dates
function CurrentISOWeekNumber()
{
	return ISOWeekNumber(new Date());
}

//:group Dates
function CurrentISOYear()
{
	return ISOYear(new Date());
}