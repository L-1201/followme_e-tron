#Parking radar by Sidi Liang
var Radar = {
    #//Class for any Parking Radar (currently only support terrain detection) which scans in a sector
    #//height: height of installation above ground;installCoordX: X coord of installation; installCoordY: Y coord of installation; maxRange: max radar range; maxWidth: width of the sector
    #//For follow me EV: height 0.3m; installCoordX:0m; installCoordY:3.8m; maxRange:3m;maxWidth:3m
    #//To start scanning: myRadar.init();
    #//To Stop: myRadar.stop();
    new: func(height, installCoordX, installCoordY, maxRange, maxWidth) {
        return { parents:[Radar, followme.Appliance.new()], height: height, installCoordX:installCoordX, installCoordY:installCoordY, maxRange:maxRange, maxWidth:maxWidth};
    },
    height: 0.3, #METERS
    installCoordX: 0, #METERS
    installCoordY: 3.8, #METERS
    maxRange: 3, #METERS
    maxWidth: 3, #METERS
    radarTimer: nil,
    updateInterval:0.25,#SEC
    searchAngle: 0, #RAD, half of the search angle
    tanSearchAngle: 0,

    vehiclePosition: nil,
    coord: nil,
    vehicleHeading: nil,

    backLonRange: nil,
    backLatRange: nil,
    widthLonRange:nil,
    widthLatRange:nil,

    warningTimer: nil,
    #warningFlag: 0,
    warningInterval: 2,
    warningSound: "parking_radar.wav",
    lastDis: 0,

    init: func(){
        me.searchAngle = math.acos(me.maxRange / math.sqrt((2/me.maxWidth)*(2/me.maxWidth) + me.maxRange*me.maxRange));
        me.tanSearchAngle = math.tan(me.searchAngle);
        me.getCoord();
        me.backLatRange = me.calculateLatChange(me.maxRange);
        me.backLonRange = me.calculateLonChange(me.maxRange, me.coord);
        me.widthLatRange = me.calculateLatChange(me.maxWidth);
        me.widthLonRange = me.calculateLonChange(me.maxWidth, me.coord);
        if(me.radarTimer == nil) me.radarTimer = maketimer(me.updateInterval, func me.update());
        if(me.warningTimer == nil) me.warningTimer = maketimer(me.warningInterval, func me.warn());
        me.radarTimer.start();
        print("Parking radar initialized!");
        playAudio("parking_radar_init.wav");
    },
    stop: func(){
        print("Parking radar stopped!");
        me.warningTimer.stop();
        me.radarTimer.stop();
    },
    toggle: func(){
        if(me.radarTimer == nil or me.radarTimer.isRunning == 0){
            me.init();
        }else{
            me.stop();
        }
    },

    getCoord: func(){
        me.vehicleHeading = props.getNode("/orientation/heading-deg",1).getValue();
        me.vehiclePosition = geo.aircraft_position();
        me.coord = geo.Coord.new(me.vehiclePosition);
        me.coord.apply_course_distance(geo.normdeg(me.vehicleHeading-90), me.installCoordX);
        me.coord.apply_course_distance(me.vehicleHeading, -me.installCoordY);
        #var model = geo.put_model(getprop("sim/aircraft-dir")~"/Nasal/waypoint.ac", me.coord);
    },
    calculateLonChange: func(meters, coord){
        var earthLength = 2 * 6378137 * math.pi; #equator
        var lat2EarthLength = earthLength * math.cos(math.abs(coord.lat()));
        var lonChange = meters * (360/lat2EarthLength);
        return math.abs(lonChange);
    },
    calculateLatChange: func(meters){
        return meters * 0.000008983152841195214;
    },
    calculateMeterChangebyLat: func(lat){
        return lat / 0.000008983152841195214;
    },
    getElevByCoord: func(coord){
        return geo.elevation(coord.lat(), coord.lon());
    },
    position_change: func(position_val,value){
        if(position_val+value>180)
            position_val += value-360;
        else if(position_val+value<-180)
            position_val += value+360;
        else
            position_val += value;
        return position_val;
    },
    judgeElev: func(targetElev){
        myElev = me.getElevByCoord(me.coord);
        if((myElev + me.height) < targetElev){
            return 1;
        }else{
            return 0;
        }
    },
    warn: func(){
        me.warningTimer.restart(me.warningInterval);
        playAudio(me.warningSound);
    },
    warnControl: func(meters){
        if(meters == 10000){
            me.warningTimer.stop();
            return;
        }
        if(!me.warningTimer.isRunning) me.warningTimer.start();
        if(meters <= 0.5){
            me.warningInterval = 0.2;
            me.warningSound = "parking_radar_long.wav";
            print("Caution! Something behind at less than 0.5 meters!");
            return;
        }else{
            me.warningSound = "parking_radar.wav";
        }
        meters = sprintf("%.3f", meters);
        if(meters != me.lastDis) me.warningInterval = (meters)/me.maxRange;
        print("Caution! Something behind at approximatly "~meters~" meters");
        me.lastDis = meters;
    },
    sample: func(stepLat, stepLon, searchLat, searchLon){ # returns an elevtion
        var latChange  = math.sin(me.vehicleHeading * D2R);
        var lonChange  = -math.cos(me.vehicleHeading * D2R);
        var sampleCoord = geo.Coord.new();
        sampleCoord.set_latlon(me.position_change(searchLat,stepLat*latChange), me.position_change(searchLon,stepLon*lonChange));
        #var model = geo.put_model(getprop("sim/aircraft-dir")~"/Nasal/waypoint.ac", sampleCoord.lat(), sampleCoord.lon(), me.coord.alt());
        return sampleCoord;
    },
    update: func(){
        me.getCoord();
        var searchDis = 0.01;#Meters
        var searchStep = 0;#Meters
        while(searchDis <= me.maxRange){
            var searchWidth = math.abs(searchDis * me.tanSearchAngle);
            var searchWidthLat = me.calculateLatChange(searchWidth);
            var searchWidthLon = me.calculateLonChange(searchWidth, me.coord);
            var searchCoord = geo.Coord.new();
            searchCoord.set_latlon(me.coord.lat(), me.coord.lon());
            searchCoord.apply_course_distance(me.vehicleHeading, 0-searchDis);
            for(var i = 0; i >= (0 - searchWidthLat); i -= searchWidthLat/1.5){
                #print(me.widthLatRange/2);
                var percentage = (0-i)/(searchWidthLat/2); #use approximate value to reduce cost
                var stepLon = 0 - searchWidthLon * percentage;
                var targetCoord = me.sample(i, stepLon, searchCoord.lat(), searchCoord.lon());
                targetElev = me.getElevByCoord(targetCoord);
                if(me.judgeElev(targetElev)){
                    var meters = me.coord.distance_to(targetCoord);
                    #var model = geo.put_model(getprop("sim/aircraft-dir")~"/Nasal/waypoint.ac", targetCoord.lat(), targetCoord.lon(), me.coord.alt());
                    me.warnControl(meters);
                    return;
                }
            }
            for(var i = 0; i <= searchWidthLat; i += searchWidthLat/1.5){
                var percentage = i/(searchWidthLat/2); #use approximate value to reduce cost
                var stepLon = searchWidthLon * percentage;
                var targetCoord = me.sample(i, stepLon, searchCoord.lat(), searchCoord.lon());
                targetElev = me.getElevByCoord(targetCoord);
                if(me.judgeElev(targetElev)){
                    var meters = me.coord.distance_to(targetCoord);
                    #var model = geo.put_model(getprop("sim/aircraft-dir")~"/Nasal/waypoint.ac", targetCoord.lat(), targetCoord.lon(), me.coord.alt());
                    me.warnControl(meters);
                    return;
                }
            }
            searchStep += 0.1;
            searchDis += searchStep;
        }
        #print("All clear");
        me.warnControl(10000);
    },
};

var parkingRadar = Radar.new(0.3, 0, 3.8, 3, 3);
