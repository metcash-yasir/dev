var monthNames = new Array(12);
monthNames['jan'] = '01';
monthNames['feb'] = '02';
monthNames['mar'] = '03';
monthNames['apr'] = '04';
monthNames['maj'] = '05';
monthNames['jun'] = '06';
monthNames['jul'] = '07';
monthNames['aug'] = '08';
monthNames['sep'] = '09';
monthNames['okt'] = '10';
monthNames['nov'] = '11';
monthNames['dec'] = '12';


// Convert from dd-MMM-yyyy to yyyy-MM-dd
function convertDate()
{
	var d = CurrentRearrange.text.toLowerCase();

	var d = d.substring(0, 1);
	var m = monthNames[d.substring(3, 5)];
	var y = d.substring(7,10);
	
	return y + "-" + m + "-" + d
}