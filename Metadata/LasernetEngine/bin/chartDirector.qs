//:group ChartDirector
function createChart()
{
	var chartType;
	var posX;
	var posY;
	var width;
	var height;
	var labelFontSize = 10;
	var yIntervals = 5;
	var margin = 300; // The total margin for the pie from both sides (eg. 50 is 25 on each side).
	var labelsJobInfo = "Chart_Labels";
	var dataJobInfo = "Chart_Data";
	var xTitleJobInfo = "Chart_XTitle";
	var yTitleJobInfo = "Chart_YTitle";
	var antiAliasing = Chart.NoAntiAlias;

	if (arguments.length < 5)
		return false;
	else
	{
		chartType = arguments[0];
		posX = arguments[1];
		posY = arguments[2];
		width = arguments[3];
		height = arguments[4];
	}

  var argNum = 5

	if (arguments.length > argNum && arguments[argNum] != -1)
		labelFontSize = arguments[argNum];
	argNum++;

	if (arguments.length > argNum && arguments[argNum] != -1)
		yIntervals = arguments[argNum];
	argNum++;

	if (arguments.length > argNum && arguments[argNum] != -1)
		margin = arguments[argNum];
	argNum++;
	
	if (arguments.length > argNum && arguments[argNum] != "")
		labelsJobInfo = arguments[argNum];
	argNum++;
		
	if (arguments.length > argNum && arguments[argNum] != "")
		dataJobInfo = arguments[argNum];
	argNum++;
		
	if (arguments.length > argNum && arguments[argNum] != "")
		xTitleJobInfo = arguments[argNum];
	argNum++;

	if (arguments.length > argNum && arguments[argNum] != "")
		yTitleJobInfo = arguments[argNum];
	argNum++;

	if (arguments.length > argNum && arguments[argNum] != -1)
		antiAliasing = arguments[argNum];
	argNum++;

	chartType = chartType.toLowerCase();
	
	if (chartType.left(3) == "pie")
		createPieChart(
			chartType,
			posX, 
			posY, 
			width, 
			height, 
			margin, 
			labelsJobInfo, 
			dataJobInfo, 
			job.getJobInfo(xTitleJobInfo), 
			job.getJobInfo(yTitleJobInfo),
			antiAliasing,
			labelFontSize
		);
	else
		createXYChart(
			chartType,
			posX, 
			posY, 
			width, 
			height, 
			margin, 
			labelsJobInfo, 
			dataJobInfo, 
			job.getJobInfo(xTitleJobInfo), 
			job.getJobInfo(yTitleJobInfo),
			antiAliasing,
			labelFontSize,
			yIntervals
		);
	
	return true;
}

//:private
function createXYChart(chartType, posX, posY, width, height, margin, labelsJobInfo, dataJobInfo, xTitle, yTitle, antiAliasing, axisLabelFontSize, yIntervals)
{
	var xyChart = new XYChart(width, height);

	xyChart.setPlotArea(margin/2, margin/2, width - margin, height - margin);

	var xAxis = xyChart.xAxis();
	var yAxis = xyChart.yAxis();
	
	var labelsArray = new StringArray();
	for (i=0; i < job.getJobInfoCount(labelsJobInfo); i++)
		labelsArray.addString(job.getJobInfo(labelsJobInfo, i));
	
	var dataArray = new DoubleArray();
	var highestDataValue = 0;
	for (i=0; i < job.getJobInfoCount(dataJobInfo); i++)
	{
		var value = Number(job.getJobInfo(dataJobInfo, i));
		dataArray.addDouble(value);
		if (highestDataValue < value)
			highestDataValue = value;
	}

	if (chartType.find("spline") != -1)
		var layer1 = xyChart.addSplineLayer(dataArray)
	else if (chartType.find("stepline") != -1)
		var layer1 = xyChart.addStepLineLayer(dataArray)
	else if (chartType.find("line") != -1)
		var layer1 = xyChart.addLineLayer(dataArray)
	else if (chartType.find("bar") != -1)
		var layer1 = xyChart.addBarLayer(dataArray)
	else if (chartType.find("area") != -1)
		var layer1 = xyChart.addAreaLayer(dataArray)
	else if (chartType.find("trend") != -1)
		var layer1 = xyChart.addTrendLayer(dataArray)

	xAxis.setTitle(xTitle, "Arialbi.ttf", 12);
	yAxis.setTitle(yTitle, "Arialbi.ttf", 12);
	
	xAxis.setLabels(labelsArray);

  // Set axis scaling
  yAxis.setMinTickInc(highestDataValue / yIntervals);

	if (chartType.find("3d") != -1)
		layer1.set3D();

	//xyChart.swapXY(true);
	
	xAxis.setLabelStyle("Arial.ttf", axisLabelFontSize);
	yAxis.setLabelStyle("Arial.ttf", axisLabelFontSize);
	
	// Set Anti-Aliasing
	xyChart.setAntiAlias((antiAliasing != Chart.NoAntiAlias), antiAliasing);

	pages[CurrentPage].printChart(posX, posY, xyChart);

	return true;
}

//:private
function createPieChart(chartType, posX, posY, width, height, margin, labelsJobInfo, dataJobInfo, xTitle, yTitle, antiAliasing, labelFontSize)
{
	var pieChart = new PieChart(width, height);
	
	var pieSize;
	if (width < height)
		pieSize = (width - margin) / 2;
	else
		pieSize = (height - margin) / 2;
	
	pieX = width/2;
	pieY = height/2;
	
	pieChart.setPieSize(pieX, pieY, pieSize);
	
/*
	var depthArray = new DoubleArray();
	depthArray.addDouble(100);
	depthArray.addDouble(60);
	depthArray.addDouble(30);
	depthArray.addDouble(10);
*/
	if (chartType.find("3d") != -1)
		pieChart.set3D();
//	else if (depthType == 2)
//		pieChart.set3D(depthArray);
	
	var labelsArray = new StringArray();
	for (i=0; i < job.getJobInfoCount(labelsJobInfo); i++)
		labelsArray.addString(job.getJobInfo(labelsJobInfo, i));
	
	var dataArray = new DoubleArray();
	for (i=0; i < job.getJobInfoCount(dataJobInfo); i++)
		dataArray.addDouble(job.getJobInfo(dataJobInfo, i));
	
	pieChart.setData(dataArray, labelsArray)

	pieChart.setLabelStyle("Arial.ttf", labelFontSize);

	// Set Anti-Aliasing
	pieChart.setAntiAlias((antiAliasing != Chart.NoAntiAlias), antiAliasing);
	
	pages[CurrentPage].printChart(posX, posY, pieChart);

	return true;
}
