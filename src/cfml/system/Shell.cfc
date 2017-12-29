/**
*********************************************************************************
* Copyright Since 2005 ColdBox Platform by Ortus Solutions, Corp
* www.coldbox.org | www.ortussolutions.com
********************************************************************************
* @author Brad Wood, Luis Majano, Denny Valliant
* The CommandBox Shell Object that controls the shell
*/
component accessors="true" singleton {

	// DI
	property name="commandService" 		inject="CommandService";
	property name="readerFactory" 		inject="ReaderFactory";
	property name="print" 				inject="print";
	property name="cr" 					inject="cr@constants";
	property name="formatterUtil" 		inject="Formatter";
	property name="logger" 				inject="logbox:logger:{this}";
	property name="fileSystem"			inject="FileSystem";
	property name="WireBox"				inject="wirebox";
	property name="LogBox"				inject="logbox";
	property name="InterceptorService"	inject="InterceptorService";
	property name="ModuleService"		inject="ModuleService";
	property name="Util"				inject="wirebox.system.core.util.Util";
	property name="JLineHighlighter"	inject="JLineHighlighter";


	/**
	* The java jline reader class.
	*/
	property name="reader";
	/**
	* The shell version number
	*/
	property name="version";
	/**
	* The loader version number
	*/
	property name="loaderVersion";
	/**
	* Bit that tells the shell to keep running
	*/
	property name="keepRunning" default="true" type="Boolean";
	/**
	* Bit that is used to reload the shell
	*/
	property name="reloadShell" default="false" type="Boolean";
	/**
	* Clear screen after reload
	*/
	property name="doClearScreen" default="false" type="Boolean";
	/**
	* The Current Working Directory
	*/
	property name="pwd";
	/**
	* The default shell prompt
	*/
	property name="shellPrompt";
	/**
	* This value is either "interactive" meaning the shell stays open waiting for user input
	* or "command" which means a single command will be run and then the shell will be exiting.
	* This differentiation may be useful for commands who want to be careful not to leave threads running
	* that they expect to finish since the JVM will terminiate immedatley after the command finishes.
	* This could also be useful to reduce the amount of extra text that's output such as the CommandBox
	* banner which isn't really needed for a one-off command, especially if the output of that command needs
	* to be fed into another OS command.
	*/
	property name="shellType" default="interactive";


	/**
	 * constructor
	 * @inStream.hint input stream if running externally
	 * @outputStream.hint output stream if running externally
	 * @userDir.hint The user directory
	 * @userDir.inject userDir@constants
	 * @tempDir.hint The temp directory
	 * @tempDir.inject tempDir@constants
 	**/
	function init(
		any inStream,
		any outputStream,
		required string userDir,
		required string tempDir,
		boolean asyncLoad=true
	){
		variables.currentThread = createObject( 'java', 'java.lang.Thread' ).currentThread();
		
		// Possible byte order marks
		variables.BOMS = [
			chr( 254 ) & chr( 255 ),
			chr( 255 ) & chr( 254 ),
			chr( 239 ) & chr( 187 ) & chr( 191 ),
			chr( 00 ) & chr( 254 ) & chr( 255 ),
			chr( 255 ) & chr( 254 ) & chr( 00 )
		];

		// Version is stored in cli-build.xml. Build number is generated by Ant.
		// Both are replaced when CommandBox is built.
		variables.version = "@build.version@+@build.number@";
		variables.loaderVersion = "@build.LoaderVersion@";
		// Init variables.
		variables.keepRunning 	= true;
		variables.reloadshell 	= false;
		variables.pwd 			= "";
		variables.reader 		= "";
		variables.shellPrompt 	= "";
		variables.userDir 	 	= arguments.userDir;
		variables.tempDir 		= arguments.tempDir;

		// Save these for onDIComplete()
		variables.initArgs = arguments;

		// If reloading the shell
		if( structKeyExists( request, 'lastCWD' ) ) {
			// Go back where we were
			variables.pwd= request.lastCWD;
		} else {
			// Store incoming current directory
			variables.pwd = variables.userDir;
		}

		setShellType( 'interactive' );
		
    	return this;
	}

	/**
	 * Finish configuring the shell
	 **/
	function onDIComplete() {
		// Create reader console and setup the default shell Prompt
		variables.reader 		= readerFactory.getInstance( argumentCollection = variables.initArgs  );
		variables.shellPrompt 	= print.green( "CommandBox> ");

		// Create temp dir & set
		setTempDir( variables.tempdir );

		getInterceptorService().configure();
		getModuleService().configure();

		getModuleService().activateAllModules();

		// load commands
		if( variables.initArgs.asyncLoad ){
			thread name="commandbox.loadcommands#getTickCount()#"{
				variables.commandService.configure();
			}
		} else {
			variables.commandService.configure();
		}
	}


	/**
	 * Exists the shell
	 **/
	Shell function exit() {
    	variables.keepRunning = false;

		return this;
	}

	/**
	 * Set's the OS Exit code to be used
	 **/
	Shell function setExitCode( required string exitCode ) {
		createObject( 'java', 'java.lang.System' ).setProperty( 'cfml.cli.exitCode', arguments.exitCode );
		return this;
	}


	/**
	 * Sets reload flag, relaoded from shell.cfm
	 * @clear.hint clears the screen after reload
 	 **/
	Shell function reload( Boolean clear=true ){

		setDoClearScreen( arguments.clear );
		setReloadshell( true );
    	setKeepRunning( false );

    	return this;
	}

	/**
	 * Returns the current console text
 	 **/
	string function getText() {
    	return variables.reader.getCursorBuffer().toString();
	}

	/**
	 * Sets the shell prompt
	 * @text.hint prompt text to set, if empty we use the default prompt
 	 **/
	Shell function setPrompt( text="" ) {
		if( !len( arguments.text ) ){
			variables.shellPrompt = print.green( "CommandBox:#listLast( getPWD(), "/\" )#> " );
		} else {
			variables.shellPrompt = arguments.text;
		}
		//variables.reader.setPrompt( variables.shellPrompt );
		return this;
	}

	/**
	 * ask the user a question and wait for response
	 * @message.hint message to prompt the user with
	 * @mask.hint When not empty, keyboard input is masked as that character
	 * @defaultResponse Text to populate the buffer with by default that will be submitted if the user presses enter without typing anything
	 * @keepHistory True to remeber the text typed in the shell history
	 *
	 * @return the response from the user
 	 **/
	string function ask( message, string mask='', string defaultResponse='', keepHistory=false ) {

		try {
			
			enableHighlighter( false );
			
			// Some things are best forgotten
			if( !keepHistory ) {
				enableHistory( false );
			}
			
			// read reponse while masking input
			var input = variables.reader.readLine(
				// Prompt for the user
				arguments.message,
				// Optionally mask their input
				len( arguments.mask ) ? javacast( "char", left( arguments.mask, 1 ) ) : javacast( "null", '' ),
				// This won't work until we can upgrade to Jline 2.14
				// Optionally pre-fill a default response for them
				len( arguments.defaultResponse ) ? javacast( "String", arguments.defaultResponse ) : javacast( "null", '' )
			);
			
		} catch( org.jline.reader.UserInterruptException var e ) {
			throw( message='CANCELLED', type="UserInterruptException");
		} finally{
			// Reset back to default prompt
			setPrompt();
			// Turn history back on
			enableHistory();
			enableHighlighter( true );
		}

		return input;
	}

	/**
	 * Ask the user a question looking for a yes/no response
	 * @message.hint message to prompt the user with
	 *
	 * @return the response from the user as a boolean value
 	 **/
	boolean function confirm( required message ){
		var answer = ask( "#message# : " );
		if( isNull( answer ) ){ return false; }
		if( trim( answer ) == "y" || ( isBoolean( answer ) && answer ) ) {
			return true;
		}
		return false;
	}

	function getMainThread() {
		return variables.currentThread;
	}

	/**
	 * Wait until the user's next keystroke, returns the key pressed
	 * @message.message An optional message to display to the user such as "Press any key to continue."
	 *
	 * @return character of key pressed or key binding name.
 	 **/
	string function waitForKey( message='' ) {
		var key = '';
		if( len( arguments.message ) ) {
			printString( arguments.message );
		}
		
		var terminal = getReader().getTerminal();
		
		var keys = createObject( 'java', 'org.jline.keymap.KeyMap' );
		var capability = createObject( 'java', 'org.jline.utils.InfoCmp$Capability' );
		var bindingReader = createObject( 'java', 'org.jline.keymap.BindingReader' ).init( terminal.reader() );

		// left, right, up, down arrow
		keys.bind( capability.key_left.name(), keys.key( terminal, capability.key_left ) );
		keys.bind( capability.key_right.name(), keys.key( terminal, capability.key_right ) );
		keys.bind( capability.key_up.name(), keys.key( terminal, capability.key_up ) );
		keys.bind( capability.key_down.name(), keys.key( terminal, capability.key_down ) );
		
		// Home/end
		keys.bind( capability.key_home.name(), keys.key( terminal, capability.key_home ) );
		keys.bind( capability.key_end.name(), keys.key( terminal, capability.key_end ) );
		
		// delete key/delete line/backspace
		keys.bind( capability.key_dc.name(), keys.key( terminal, capability.key_dc ) );
		keys.bind( capability.key_backspace.name(), keys.key( terminal, capability.key_backspace ) );
		
		keys.bind( capability.key_ic.name(), keys.key( terminal, capability.key_ic ) );
		
		// Page up/down
		keys.bind( capability.key_npage.name(), keys.key( terminal, capability.key_npage ) );
		keys.bind( capability.key_ppage.name(), keys.key( terminal, capability.key_ppage ) );
		
		// Function keys
		keys.bind( capability.key_f1.name(), keys.key( terminal, capability.key_f1 ) );
		keys.bind( capability.key_f2.name(), keys.key( terminal, capability.key_f2 ) );
		keys.bind( capability.key_f3.name(), keys.key( terminal, capability.key_f3 ) );
		keys.bind( capability.key_f4.name(), keys.key( terminal, capability.key_f4 ) );
		keys.bind( capability.key_f5.name(), keys.key( terminal, capability.key_f5 ) );
		keys.bind( capability.key_f6.name(), keys.key( terminal, capability.key_f6 ) );
		keys.bind( capability.key_f7.name(), keys.key( terminal, capability.key_f7 ) );
		keys.bind( capability.key_f8.name(), keys.key( terminal, capability.key_f8 ) );
		keys.bind( capability.key_f9.name(), keys.key( terminal, capability.key_f9 ) );
		keys.bind( capability.key_f10.name(), keys.key( terminal, capability.key_f10 ) );
		keys.bind( capability.key_f11.name(), keys.key( terminal, capability.key_f11 ) );
		keys.bind( capability.key_f12.name(), keys.key( terminal, capability.key_f12 ) );

		// Everything else
		keys.setnomatch( 'self-insert' );

		// This doesn't seem to work on Windows
		keys.bind( 'delete', keys.del() );
		
		keys.bind( 'escape', keys.esc() );
		keys.setAmbiguousTimeout( 50 );
		
		var binding = bindingReader.readBinding( keys );
		if( binding == 'self-insert' ) {
			key = bindingReader.getLastBinding();
		} else {
			key = binding;
		}
		
		// Reset back to default prompt
		setPrompt();

		return key;
	}

	/**
	 * clears the console
	 *
	 * @note Almost works on Windows, but doesn't clear text background
	 *
 	 **/
	Shell function clearScreen() {
		reader.clearScreen();
   		variables.reader.getTerminal().writer().flush();
		return this;
	}

	/**
	 * Get's terminal width
  	 **/
	function getTermWidth() {
       	return variables.reader.getTerminal().getWidth();
	}

	/**
	 * Get's terminal height
  	 **/
	function getTermHeight() {
       	return variables.reader.getTerminal().getHeight();
	}

	/**
	 * Alias to get's current directory or use getPWD()
  	 **/
	function pwd() {
    	return variables.pwd;
	}

	/**
	* Get the temp dir in a safe manner
	*/
	string function getTempDir(){
		return variables.tempDir;
	}

	/**
	 * sets and renews temp directory
	 * @directory.hint directory to use
  	 **/
	Shell function setTempDir( required directory ){

       // Create it if it's not there.
       if( !directoryExists( arguments.directory ) ) {
	        directoryCreate( arguments.directory );
       }

    	// set now that it is created.
    	variables.tempdir = arguments.directory;

    	return this;
	}

	/**
	 * Changes the current directory of the shell and returns the directory set.
	 * @directory.hint directory to CD to.  Please verify it exists before calling.
  	 **/
	String function cd( directory="" ){
		variables.pwd = arguments.directory;
		request.lastCWD = arguments.directory;
		// Update prompt to reflect directory change
		setPrompt();
		return variables.pwd;
	}

	/**
	 * Prints a string to the reader console with auto flush
	 * @string.hint string to print (handles complex objects)
  	 **/
	Shell function printString( required string ){
		if( !isSimpleValue( arguments.string ) ){
			systemOutput( "[COMPLEX VALUE]\n" );
			writedump(var=arguments.string, output="console");
			arguments.string = "";
		}
    	variables.reader.getTerminal().writer().print( arguments.string );
    	variables.reader.getTerminal().writer().flush();

    	return this;
	}

	/**
	 * Runs the shell thread until exit flag is set
	 * @input.hint command line to run if running externally
  	 **/
    Boolean function run( input="", silent=false ) {

		// init reload to false, just in case
        variables.reloadshell = false;

		try{
	        // Get input stream
	        if( arguments.input != "" ){
	        	 arguments.input &= chr(10);
	        	var inStream = createObject( "java", "java.io.ByteArrayInputStream" ).init( arguments.input.getBytes() );
	        	variables.reader.setInput( inStream );
	        }

	        // setup bell enabled + keep running flags
	        // variables.reader.setBellEnabled( true );
	        variables.keepRunning = true;

	        var line ="";
	        if( !arguments.silent ) {
				// Set default prompt on reader
				setPrompt();
			}

			// while keep running
	        while( variables.keepRunning ){
	        	// check if running externally
				if( arguments.input != "" ){
					variables.keepRunning = false;
				}
				
				try {
					
					// Shell stops on this line while waiting for user input
			        if( arguments.silent ) {
			        	line = variables.reader.readLine( javacast( "char", ' ' ) );
					} else {
			        	line = variables.reader.readLine( variables.shellPrompt );
					}
					
				// User hits Ctrl-C.  Don't let them exit the shell.
				} catch( org.jline.reader.UserInterruptException var e ) {
					variables.reader.getTerminal().writer().print( variables.print.yellowLine( 'Use the "exit" command or Ctrl-D to leave this shell.' ) );
		    		variables.reader.getTerminal().writer().flush();
		    		continue;
		    		
				// User hits Ctrl-D.  Murder the shell dead.
				} catch( org.jline.reader.EndOfFileException var e ) {
					variables.reader.getTerminal().writer().print( variables.print.boldGreenLine( 'Goodbye!' ) );
		    		variables.reader.getTerminal().writer().flush();
					variables.keepRunning = false;
		    		continue; 
				}
				
	        	// If the standard input isn't avilable, bail.  This happens
	        	// when commands are piped in and we've reached the end of the piped stream
	        	if( !isDefined( 'line' ) ) {
	        		return false;
	        	}

	        	// Clean BOM from start of text in case something was piped from a file
	        	BOMS.each( function( i ){
	        		if( line.startsWith( i ) ) {
	        			line = replace( line, i, '' );
	        		}
	        	} );

	            // If there's input, try to run it.
				if( len( trim( line ) ) ) {
					callCommand( command=line, initialCommand=true );
				}

	        } // end while keep running

		} catch( any e ){
			SystemOutput( e.message & e.detail );
			printError( e );
		}

		return variables.reloadshell;
    }

	/**
	* Shutdown the shell and close/release any resources associated.
	* This isn't gunartuneed to run if the shell is closed, but it 
	* will run for a reload command
	*/
	function shutdown() {
		variables.reader.getTerminal().close();
	}

	/**
	* Call this method periodically in a long-running task to check and see
	* if the user has hit Ctrl-C.  This method will throw an UserInterruptException
	* which you should not catch.  It will unroll the stack all the way back to the shell
	*/
	function checkInterrupted() {
		var thisThread = createObject( 'java', 'java.lang.Thread' ).currentThread();

		// Has the user tried to interrupt this thread?
		if( thisThread.isInterrupted() ) {
			// This clearn the interrupted status. i.e., "yeah, yeah, I'm on it!"
			thisThread.interrupted();
			throw( 'UserInterruptException', 'UserInterruptException', '' );
		}
	}

	/**
	* @filePath The path to the history file to set
	* 
	* Use this wrapper method to change the history file in use by the shell.
	*/
	function setHistory( filePath ) {
		
		var LineReader = createObject( "java", "org.jline.reader.LineReader" );
		
		// Save current file
		variables.reader.getHistory().save();
		// Swap out the file setting
		variables.reader.setVariable( LineReader.HISTORY_FILE, filePath );
		// Load in the new file
		variables.reader.getHistory().load();
		
	}

	/**
	* @enable Pass true to enable, false to disable
	* 
	* Enable or disables history in the shell
	*/
	function enableHistory( boolean enable=true ) {
		
		var LineReader = createObject( "java", "org.jline.reader.LineReader" );
		
		// Swap out the file setting
		variables.reader.setVariable( LineReader.DISABLE_HISTORY, !enable );
	}

	/**
	* @enable Pass true to enable, false to disable
	* 
	* Enable or disables highlighting in the shell
	*/
	function enableHighlighter( boolean enable=true ) {
		if( enable ) {
			// Our CommandBox parser/command-aware highlighter
			variables.reader.setHighlighter( createDynamicProxy( JLineHighlighter, [ 'org.jline.reader.Highlighter' ] ) );			
		} else {
			// A dummy highlighter, or at least one that never seems to do anything...
			variables.reader.setHighlighter( createObject( 'java', 'org.jline.reader.impl.DefaultHighlighter' ) );
		}
	}

	/**
	 * Call a command
 	 * @command.hint Either a string containing a text command, or an array of tokens representing the command and parameters.
 	 * @returnOutput.hint True will return the output of the command as a string, false will send the output to the console.  If command outputs nothing, an empty string will come back.
 	 * @piped.hint Any text being piped into the command.  This will overwrite the first parameter (pushing any positional params back)
 	 * @initialCommand.hint Since commands can recursivley call new commands via this method, this flags the first in the chain so exceptions can bubble all the way back to the beginning.
 	 * In other words, if "foo" calls "bar", which calls "baz" and baz errors, all three commands are scrapped and do not finish execution.
 	 **/
	function callCommand(
		required any command,
		returnOutput=false,
		string piped,
		boolean initialCommand=false )  {

		// Commands a loaded async in interactive mode, so this is a failsafe to ensure the CommandService
		// is finished.  Especially useful for commands run onCLIStart.  Wait up to 5 seconds.
		var i = 0;
		while( !CommandService.getConfigured() && ++i<50 ) {
			sleep( 100  );
		}

		// Flush history buffer to disk. I could do this in the quit command
		// but then I would lose everything if the user just closes the window
		variables.reader.getHistory().save();
		
		try{

			if( isArray( command ) ) {
				if( structKeyExists( arguments, 'piped' ) ) {
					var result = variables.commandService.runCommandTokens( arguments.command, piped );
				} else {
					var result = variables.commandService.runCommandTokens( arguments.command );
				}
			} else {
				var result = variables.commandService.runCommandLine( arguments.command );
			}

		// This type of error is recoverable-- like validation error or unresolved command, just a polite message please.
		} catch ( commandException var e) {
			// If this is a nested command, pass the exception along to unwind the entire stack.
			if( !initialCommand ) {
				rethrow;
			} else {
				printError( { message : e.message, detail: e.detail } );
			}
		// This type of error means the user hit Ctrl-C, during a readLine() call. Duck out and move along.
		} catch ( UserInterruptException var e) {
			// If this is a nested command, pass the exception along to unwind the entire stack.
			if( !initialCommand ) {
				rethrow;
			} else {
    			variables.reader.getTerminal().writer().flush();
				variables.reader.getTerminal().writer().println();
				variables.reader.getTerminal().writer().print( variables.print.boldRedLine( 'CANCELLED' ) );
			}
		
		} catch (any e) {
			
			// If this is a nested command, pass the exception along to unwind the entire stack.
			if( !initialCommand ) {
				rethrow;
			// This type of error means the user hit Ctrl-C, when not in a readLine() call (and hit my custom signal handler).  Duck out and move along.
			} else if( e.getPageException().getRootCause().getClass().getName() == 'java.lang.InterruptedException' ) {
    			variables.reader.getTerminal().writer().flush();
				variables.reader.getTerminal().writer().println();
				variables.reader.getTerminal().writer().print( variables.print.boldRedLine( 'CANCELLED' ) );			
			// Anything else is completely unexpected and means boom booms happened-- full stack please.
			} else {
				printError( e );
			}
		}

		// Return the output to the caller to deal with
		if( arguments.returnOutput ) {
			if( isNull( result ) ) {
				return '';
			} else {
				return result;
			}
		}

		// We get to output the results ourselves
		if( !isNull( result ) && !isSimpleValue( result ) ){
			if( isArray( result ) ){
				return variables.reader.getTerminal().writer().printColumns( result );
			}
			result = variables.formatterUtil.formatJson( serializeJSON( result ) );
			printString( result );
		} else if( !isNull( result ) && len( result ) ) {
			printString( result );
			// If the command output text that didn't end with a line break one, add one
			var lastChar = mid( result, len( result ), 1 );
			if( ! ( lastChar == chr( 10 ) || lastChar == chr( 13 ) ) ) {
				variables.reader.getTerminal().writer().println();
			}
		} else {
			variables.reader.getTerminal().writer().println();
		}

		return '';
	}

	/**
	 * print an error to the console
	 * @err.hint Error object to print (only message is required)
  	 **/
	Shell function printError( required err ){
		setExitCode( 1 );

		// If CommandBox blows up while starting, the interceptor service won't be ready yet.
		if( getInterceptorService().getConfigured() ) {
			getInterceptorService().announceInterception( 'onException', { exception=err } );
		}

		variables.logger.error( '#arguments.err.message# #arguments.err.detail ?: ''#', arguments.err.stackTrace ?: '' );

		variables.reader.getTerminal().writer().print( variables.print.whiteOnRedLine( 'ERROR (#variables.version#)' ) );
		variables.reader.getTerminal().writer().println();
		variables.reader.getTerminal().writer().print( variables.print.boldRedText( variables.formatterUtil.HTML2ANSI( arguments.err.message, 'boldRed' ) ) );
		variables.reader.getTerminal().writer().println();

		if( structKeyExists( arguments.err, 'detail' ) ) {
			variables.reader.getTerminal().writer().print( variables.print.boldRedText( variables.formatterUtil.HTML2ANSI( arguments.err.detail ) ) );
			variables.reader.getTerminal().writer().println();
		}
		if( structKeyExists( arguments.err, 'tagcontext' ) ){
			var lines = arrayLen( arguments.err.tagcontext );
			if( lines != 0 ){
				for( var idx=1; idx <= lines; idx++) {
					var tc = arguments.err.tagcontext[ idx ];
					if( idx > 1 ) {
						variables.reader.getTerminal().writer().print( print.boldCyanText( "called from " ) );
					}
					variables.reader.getTerminal().writer().print( variables.print.boldCyanText( "#tc.template#: line #tc.line##variables.cr#" ));
					if( len( tc.codeprinthtml ) ){
						variables.reader.getTerminal().writer().print( variables.print.text( variables.formatterUtil.HTML2ANSI( tc.codeprinthtml ) ) );
					}
				}
			}
		}
		if( structKeyExists( arguments.err, 'stacktrace' ) ) {
			variables.reader.getTerminal().writer().print( arguments.err.stacktrace );
		}

		variables.reader.getTerminal().writer().println();
		variables.reader.getTerminal().writer().flush();

		return this;
	}

}
