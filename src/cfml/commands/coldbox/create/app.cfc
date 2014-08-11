/**
*  Create a blank ColdBox app from one of our app skeletons.  By default it will create
*  in your current directory.  Use the "pwd" command to find out what directory you're currently in.
* .
*  You can choose what app skeleton to use as well as override the directory it's created in.
*  The built-in app skeletons are located in the .CommandBox/cfml/skeletons/ directory and include:
*  .
*  - Advanced
*  - AdvancedScript (default)
*  - Simple
*  - SuperSimple
* .
* {code:bash}
* coldbox create app myApp
* {code}
* .
* Use the "installColdBox" parameter to install the latest stable version of ColdBox from ForgeBox
* {code:bash}
* coldbox create app myApp --installColdBox
* {code}
* .
* Use the "installTestBox" parameter to install the latest stable version of TestBox from ForgeBox
* {code:bash}
* coldbox create app myApp --installColdBox --installTestBox
* {code}
* .
**/
component extends="commandbox.system.BaseCommand" aliases="" excludeFromHelp=false {
	
	/**
	* The location of our skeletons
	*/
	property name="skeletonLocation";

	// DI
	property name="packageService" 	inject="PackageService";
	property name='parser' 			inject='Parser';
	
	/**
	* Constructor
	*/
	function init(){
		super.init();
		variables.skeletonLocation = expandPath( '/commandbox/skeletons/' );
		return this;
	}
	
	/**
	 * @name.hint The name of the app you want to create
	 * @skeleton.hint The name of the app skeleton to generate 
	 * @directory.hint The directory to create the app in.  Defaults to your current working directory.
	 * @init.hint "init" the directory as a package if it isn't already
	 * @installColdBox.hint Install the latest stable version of ColdBox from ForgeBox
	 * @installTestBox.hint Install the latest stable version of TestBox from ForgeBox
	 **/
	function run(
		required name,
		skeleton='AdvancedScript',
		directory=getCWD(),
		boolean init=true,
		boolean installColdBox=false,
		boolean installTestBox=false
	) {
					
		// This will make the directory canonical and absolute		
		arguments.directory = fileSystemUtil.resolvePath( arguments.directory );
		// get the right skeleton
		var skeletonZip = skeletonLocation & arguments.skeleton & '.zip';
		
		// Validate directory
		if( !directoryExists( arguments.directory ) ) {
			return error( 'The directory [#arguments.directory#] doesn''t exist.' );			
		}
		// Validate skeleton
		if( !fileExists( skeletonZip ) ) {
			var options = directoryList( path=skeletonLocation, listInfo='name', sort="name" );
			return error( "The app skeleton [#skeletonZip#] doesn't exist.  Valid options are #replaceNoCase( arrayToList( options, ', ' ), '.zip', '', 'all' )#" );			
		}
		
		// Unzip the skeleton!
		zip
			action="unzip"
			destination="#arguments.directory#"
			file="#skeletonZip#";
	
		print.line()
			.greenLine( '#skeleton# Application successfully created in [#arguments.directory#]' );
		
		// Check for the @appname@ in .project files
		if( fileExists( "#arguments.directory#/.project" ) ){
			var sProject = fileRead( "#arguments.directory#/.project" );
			sProject = replaceNoCase( sProject, "@appName@", arguments.name, "all" );
			file action='write' file='#arguments.directory#/.project' mode ='755' output='#sProject#';
		}

		// Init, if not a package as a Box Package
		if( arguments.init && !packageService.isPackage( arguments.directory ) ) {
			var originalPath = getCWD(); 
			// init must be run from CWD
			shell.cd( arguments.directory );
			runCommand( 'init "#parser.escapeArg( arguments.name )#" "#parser.escapeArg( replace( arguments.name, ' ', '', 'all' ) )#"' ); 
			shell.cd( originalPath );
		}
		
		// Install the ColdBox platform
		if( arguments.installColdBox ) {
			
			// Flush out stuff from above
			print.toConsole();
			
			packageService.installPackage(
				ID = 'coldbox',
				directory = arguments.directory,
				save = true,
				saveDev = false,
				production = true,
				currentWorkingDirectory = arguments.directory
			);
		}

		// Install TestBox
		if( arguments.installTestBox ) {
			
			// Flush out stuff from above
			print.toConsole();
			
			packageService.installPackage(
				ID = 'testbox',
				directory = arguments.directory,
				save = false,
				saveDev = true,
				production = true,
				currentWorkingDirectory = arguments.directory
			);
		}
		
	}

}