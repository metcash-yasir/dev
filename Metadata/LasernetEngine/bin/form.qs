//******************************************************************************
// Public functions:
//******************************************************************************

 //-----------------------------------------------------------------------------
 // AddOverlay
 //-----------------------------------------------------------------------------
// Adds the given overlay to all pages - remember to include ".emf"
// Best used on Sheet End Modifier
// (replace is optional, default = false)
// (editoronly is optional, default = false)
//:group Form
function addOverlay(overlayname, replace, editoronly)
{
	var idx;
	for (idx = 1; idx <= grab.numberOfPages; idx++)
	{	
		if (arguments.length < 2)
			pages[idx].addOverlay(overlayname, false, false);
		else if (arguments.length < 3)
			pages[idx].addOverlay(overlayname, replace, false);
		else
			pages[idx].addOverlay(overlayname, replace, editoronly);
	}	
}

 //-----------------------------------------------------------------------------
 // AddPageOverlay
 //-----------------------------------------------------------------------------
// Adds the given overlay to the current page - remember to include ".emf"
// Best used on Page End Modifier
// (replace is optional, default = false)
// (editoronly is optional, default = false)
//:group Form
function addPageOverlay(overlayname, replace, editoronly)
{
	if (arguments.length < 2)
		pages[CurrentPage].addOverlay(overlayname, false, false);
	else if (arguments.length < 3)
		pages[CurrentPage].addOverlay(overlayname, replace, false);
	else
		pages[CurrentPage].addOverlay(overlayname, replace, editoronly);
}

 //-----------------------------------------------------------------------------
 // AddSubform
 //-----------------------------------------------------------------------------
// Adds the given subform to all pages
// Best used on Sheet End Modifier
// (replace is optional, default = false)
// (editoronly is optional, default = false)
//:group Form
function addSubform(subformname, replace, editoronly)
{
	var idx;
	for (idx = 1; idx <= grab.numberOfPages; idx++)
	{	
		if (arguments.length < 2)
			pages[idx].addSubform(subformname, false, false);
		else if (arguments.length < 3)
			pages[idx].addSubform(subformname, replace, false);
		else
			pages[idx].addSubform(subformname, replace, editoronly);
	}	
}

 //-----------------------------------------------------------------------------
 // AddPageSubform
 //-----------------------------------------------------------------------------
// Adds the given subform to the current page
// Best used on Page End Modifier
// (replace is optional, default = false)
// (editoronly is optional, default = false)
//:group Form
function addPageSubform(subformname, replace, editoronly)
{
	if (arguments.length < 2)
		pages[CurrentPage].addSubform(subformname, false, false);
	else if (arguments.length < 3)
		pages[CurrentPage].addSubform(subformname, replace, false);
	else
		pages[CurrentPage].addSubform(subformname, replace, editoronly);
}


 //-----------------------------------------------------------------------------
 // AddPrinterProfile
 //-----------------------------------------------------------------------------
//:group Form
function addPrinterProfile(portname, profilename)
{
	var idx;
	for (idx = 1; idx <= grab.numberOfPages; idx++)
	{
			pages[idx].addPrinterProfile(portname, profilename, true);
	}
}

 //-----------------------------------------------------------------------------
 // AddPagePrinterProfile
 //-----------------------------------------------------------------------------
//:group Form
function addPagePrinterProfile(portname, profilename)
{
	pages[CurrentPage].addPrinterProfile(portname, profilename, true);
}

 //-----------------------------------------------------------------------------
 // Sum
 //-----------------------------------------------------------------------------
// Sums any number of arguments
// The arguments may be of the following types
// ScriptInputRearrange
// ScriptOutputRearrange
// Arrays of rearranges (typical)
// numbers
//:group Form
function Sum()
{
	var sum = 0;
	var i;
	for (i = 0; i < arguments.length; i++)
	{
		if (arguments[i] == null)
		{
			return 0;
		}
		else if (typeof(arguments[i]) == "number") // this is a number
		{
			sum += arguments[i];
		}
		else if (typeof(arguments[i]) == "object") // some kind of object, hopefully one of ours
		{
			if (typeof(arguments[i].length) == "number")
				sum += SumArray(arguments[i]);
			else if (typeof(arguments[i].number) == "number") // ScriptInputRearrange, ScriptOutputRearrange or any object with a .number property
				sum += arguments[i].number;
		}
	}
	return returnNumber(sum);
}

 //-----------------------------------------------------------------------------
 // SumPage
 //-----------------------------------------------------------------------------
// Usage: If the first parameter is a number
// that number is assumed to be which page to 
// sum on. Otherwise the CurrentPage is assumed
// The rest of the parameters may be arrays,
// or single rearranges or simple numbers
//:group Form
function SumPage()
{
	var idx 			= 0;
	var startIdx 	= 0;
	var sum 			= 0;
	var whichPage = CurrentPage;
	
	if (typeof(arguments[0]) == "number")
	{
		whichPage = arguments[0];
		startIdx = 1;
	}
		
	for (idx = startIdx; idx < arguments.length; idx++)
	{
		sum += numberOfItem(arguments[idx], whichPage);
	}
	return returnNumber(sum);
}

 //-----------------------------------------------------------------------------
 // SumSubtotal
 //-----------------------------------------------------------------------------
// Sums on all pages until and including the
// given or CurrentPage, which is the default if
// no page number is given as the first parameter
//:group Form
function SumSubtotal()
{
	var idx 			= 0;
	var startIdx 	= 0;
	var sum 			= 0;
	var whichPage = CurrentPage;

	if (typeof(arguments[0]) == "number")
	{
		whichPage = arguments[0];
		startIdx = 1;
	}
			
	if (whichPage < 1)
		return 0;
		
	for (idx = startIdx; idx < arguments.length; idx++)
	{
		sum += numberOfItem(arguments[idx], whichPage, 1);
	}
	return returnNumber(sum);
}


 //*****************************************************************************
 // Private functions:
 //*****************************************************************************

 //-----------------------------------------------------------------------------
 // NumberOfItem
 //-----------------------------------------------------------------------------
//:private
function numberOfItem(item, whichPage, startPage)
{
	var sum = 0;
	if (item == null)
	{
		return 0;
	}
	else if (typeof(item) == "object") // assume one of our objects
	{
		if (typeof(item.length) == "number")
		{
			if (arguments.length == 3)
				sum = SumArray(item, whichPage, startPage);
			else if (arguments.length == 2)
				sum = SumArray(item, whichPage);
			else
				sum = SumArray(item);
		}
		else if (typeof(item.page) == "number") // ScriptInputRearrange or ScriptOutputRearrange
		{
			if (arguments.length == 3)
			{	
				if (item.page >= startPage && item.page <= whichPage)
					sum = item.number;
			}
			else if (arguments.length == 2)
			{
				if (item.page == whichPage)
					sum = item.number;
			}
			else
			{
		  		sum = item.number;
			}
		}
	}
	else if (typeof(item) == "number") // this is a number
	{
		sum = item;
	}
	else // Assume something with a .number property
	{
		sum = item.number;
	}
	
	return sum;
}

 //-----------------------------------------------------------------------------
 // SumArray
 //-----------------------------------------------------------------------------
//:private
function SumArray(a /*Array */, whichPage, startPage)
{
	var sum  			= 0;
	var page 			= -1;
	var firstPage	= -1;
	if (arguments.length >= 2)
		page = whichPage;
	if (arguments.length == 3)
  		firstPage = startPage;

	return grab.sumArray(a, page, firstPage);
	  	
// 	var i = 0;
// 	for (i = 0; i < a.length; i++)
// 	{
// 		if (page > 0)
// 		{
// 		if (firstPage > 0)
// 		{
// 	  		if (a[i].page >= firstPage && a[i].page <= page)
// 	  			sum += a[i].number;
// 		}
// 		else
// 		{
// 	  		if (a[i].page == page)
// 	  			sum += a[i].number;
// 		}
// 		}
// 		else
// 			sum += a[i].number;
// 	}
// 	return sum;
}

//:group Form
function SumGroup(a)
{
	return grab.sumGroup(a, -1, -1);
}

//:group Form
function SumGroupPage(a, page, startpage)
{
	if (arguments.length < 3)
		return grab.sumGroup(a, page, -1);
	else
		return grab.sumGroup(a, page, startpage);
}

//:group Form
function SumRegion(a)
{
	return grab.sumRegion(a, -1, -1);
}

//:group Form
function SumRegionPage(a, page, startpage)
{
	if (arguments.length < 3)
		return grab.sumRegion(a, page, -1);
	else
		return grab.sumRegion(a, page, startpage);
}

//:group Form
function returnNumber(number)
{
	if (isNaN(number))
	{
		return "NaN";
	}
	else
	{
		return number;		
	}
}