# Copyright (c) 2015, 2016 Wind River Systems, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This perl module handles various HAC server transactions and
# provides useful utility functions

package HelixUtils;

use strict;

use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

use Env;

$VERSION     = 1.3;
@ISA         = qw(Exporter);
@EXPORT      = qw( setLogLvl setLogOptions logMsg execCmd hacGetCSRFToken hacGenerateNamedTarget hacGetKeyExpiration hacGetDeviceStatus hacGetWRSToken getDefaultSdkVer getDefaultSdkName setDefaultSdkCfgData getDefaultSdkCfgData getDefaultHacServer getDefaultBoardName getDefaultHttpsProxy setDefaultHttpsProxy useHttpsProxy parseDevMgrData );
@EXPORT_OK   = ();
%EXPORT_TAGS = ( DEFAULT => [qw( &setLogLvl &setLogOptions &logMsg &execCmd &hacGetCSRFToken &hacGenerateNamedTarget &hacGetKeyExpiration &hacGetDeviceStatus &hacGetWRSToken &getDefaultSdkVer &getDefaultSdkName &setDefaultSdkCfgData &getDefaultSdkCfgData &getDefaultHacServer &getDefaultBoardName &getDefaultHttpsProxy &setDefaultHttpsProxy &useHttpsProxy &parseDevMgrData )] );

use JSON::PP;

#  ****** NOTE ABOUT USE OF HTTPS_PROXY ****** 
#
#  On some systems the Curl commands used to register with the HAC
#  server may require the specification of an HTTPS proxy... To
#  implement the use of the proxy the setDefaultHttpsProxy() routine
#  will define the HTTPS_PROXY shell enviornment variable so that it
#  will be exported to all child processes / sub-tasks executed from
#  within the script. Specification of th enviornment variable will
#  allow curl and any other calls to pick up the proxy definition
#  without requiring shell command specific modifications as long as
#  the commands know to check the HTTPS_PROXY enviornment variable.

my $logLvl = 0;

# Flag to indicate if the logMsg() API should exit on when a message
# is flagged fatal
my $logExtOnFatalF = 1;

# The stream to use for log messages, if specified. Will override
# local behavior.
my $logOutStream;
undef $logOutStream;

# The expected location for SDK name and version data
my $sdkVerFile = "/etc/default/sdkVersion.txt";
my $sdkNameFile = "/etc/default/sdkName.txt";
my $sdkDevCfgFile = "/etc/default/device_mgr.cfg";
my $backupSdkDevCfgFile = "/etc/default/device_mgr.bak";
my $serverCfgFile = "/etc/default/hacServer.cfg";
my $backupServerCfgFile = "/etc/default/hacServer.bak";
my $sysBoardNameFile = "/sys/devices/virtual/dmi/id/board_name";
my $httpsProxyCfgFile = "/etc/default/hacProxy.cfg";

my $tmpFile = "/tmp/regTgtCookies.txt";

# A routine to execute a command and return the results. First arg is
# the shell command string to evaluate. A scalar reference can be
# passed as a 2nd arg to get return status
sub execCmd
{
    my $cmd = shift;
    my $status = shift;

    # Always capture stderr
    my @rslt = `$cmd 2>&1`;
    chomp @rslt;

    ${ $status } = $? if defined $status;

    logMsg( "> $cmd\n  >>status[ $? ]\n" . join( "\n  ", @rslt ) . "\n",
	    { lvl => 2 } );

    # Let the caller decide if they want a scalar or an array
    return wantarray ? @rslt : join( "\n", @rslt );
}

# A routine to set the log level used by logMsg()
sub setLogLvl
{
    $logLvl = shift;
}

# Routine to set the logMsg() function options
sub setLogOptions
{
    my $options = shift;

    if ( exists ${ $options }{ lvl } )
    {
	$logLvl = ${ $options }{ lvl };
    }

    if ( exists ${ $options }{ fatalFlag } )
    {
	$logExtOnFatalF = ${ $options }{ fatalFlag };
    }

    if ( exists ${ $options }{ out } )
    {
	$logOutStream = ${ $options }{ out };
    }
}

# A routine to print output / control where it goes relative to the
# log level which is set for the program. Log level for the program
# may be:
#   -1 = No output
#    0 = Errors only
#    1 = Verbose messages
#    2 = Debug
#    3 = Debug+
#
#  First argument is a string to be logged. 
#
#  Second argument (optional) is a hash containing the log message
#  settings. The hash may contain:
#   { 
#     out = <>,          # <> is some type of file handle
#     lvl => [ 0 - 2 ],  # Use log level specified
#     fatal => 1,        # Die after reporting the error
#     debug => 1         # Debug log level
#   }
#    -- If the level is not specified the message is assumed to be log level 0. 
#    -- { lvl } will be the log level of the message
#    -- When { fatal } is defined the message is printed to stderr and 
#       the program exits with error status
#    -- { out } may be used to specify a file descriptor to send output 
#       which overrides the default. Out will be closed before exiting 
#       the program.
#    -- { debug } may be specified instead of lvl => 2 to indicate a debug 
#       message
#
#  NOTE: If the debug flag is set all messages are output regardless
#  of the log level
sub logMsg
{
    my $msg = shift;
    my $args = shift;
    my $lvl = 0;

    if ( exists ${ $args }{ lvl } )    
    {
	$lvl = ${ $args }{ lvl };
    }
    elsif ( exists ${ $args }{ debug } ) 
    {
	$lvl = 2;
    }

    # Pick STDOUT or STDERR based on message level
    #   lvl = -1, no output
    #   lvl = 0, STDERR
    #   lvl > 0, STDOUT
    #   if ${ $args }{ out }, then use specified descriptor
    my $out = *STDERR;

    if ( defined $logOutStream )
    {
	$out = $logOutStream;
    }
    elsif ( exists ${ $args }{ out } )
    {
	$out = ${ $args }{ out };
    }
    else
    {
	$out = *STDOUT if ( $lvl > 0 );
    }
    
    if ( exists ${ $args }{ fatal } ||
	 ( ( $logLvl > -1 ) && ( $lvl <= $logLvl ) ) )
    {
	print $out "$msg";
    }
    
    if ( exists ${ $args }{ fatal } )
    {
	close( $out ) if ( exists ${ $args }{ out } );
	exit( -1 ) if ( $logExtOnFatalF );
    }
}

# Routine to execute a CURL request to the HAC server 
# Arg 1: Curl Command
# Returns: Hash of decoded JSON data
sub execServerRequest
{
    my $cmd = shift;
    my $r;

    my $data = execCmd( $cmd, \$r );

    if ( $r || ( $data =~ m|^\s*$| ) )
    {
	# If the server returns an error string in the JSON data there
	# will be a nested hash when it gets parsed, so we need to
	# return a structre that higher-level functions can handle
	# consistently
	return { error => { failed => 1 } };
    }
    
    $data = decode_json( $data );    
    
    return $data;
}


# Routine to get the CRSF token from the HAC server
#  Arg 1: HAC server
#  Arg 2: SCALAR REF to result status, 0 = success, else ERROR
#  Arg 3: SCALAR REF for error string
#  Returns: CSRF token string
sub hacGetCSRFToken
{
    my $hacServer = shift;
    my $rslt = shift;
    my $rsltStr = shift;

    # HAC server request command
    my $cmd = 
	"curl -f https://$hacServer/csrfToken -k -s -S " . 
	"-c $tmpFile -b $tmpFile 2>&1";
    
    # Error to return if the request fails
    my $errMsg = "ERROR: Getting CSRF token failed!";

    my $href = execServerRequest( $cmd );
    my %data = %{ $href };

    if ( exists $data{ error } )
    {
	if ( exists $data{ error }{ message } )
	{
	    ${ $rsltStr } = $data{ error }{ message };
	}
	else
	{
	    ${ $rsltStr } = $errMsg;
	}

	${ $rslt } = -1;
	return "";
    }

    ${ $rslt } = 0;
    return $data{ _csrf };
}

# Routine to generate a named target on the HAC server
sub hacGenerateNamedTarget
{
    my $hacServer = shift;
    my $boardName = shift;
    my $sdkName = shift;
    my $sdkVer = shift;
    my $tokenCSRF = shift;

    my $rslt = shift;
    my $rsltStr = shift;    

   # Generate a target with the specified name
   my $cmd = 
	"curl -f -X POST -k " .
	"-H \"x-csrf-token: $tokenCSRF\" " .
	"https://$hacServer/api/v1/registration " .
	"-H \"Content-Type: application/json\" " .
	"-d '" .
	encode_json( { name => $boardName, SDKKey => $sdkName, 
		       SDKVersion => $sdkVer } ) . "' ".
	"-c $tmpFile -b $tmpFile -s -S 2>&1";
    
    # Error to return if the request fails
    my $errMsg = "ERROR: Creating target [ $boardName ] " . 
	"on server [ $hacServer ] failed!";

    my $href = execServerRequest( $cmd );
    my %data = %{ $href };

    if ( exists $data{ error } )
    {
	if ( exists $data{ error }{ message } )
	{
	    ${ $rsltStr } = $data{ error }{ message };
	}
	else
	{
	    ${ $rsltStr } = $errMsg if ( $rsltStr );
	}

	${ $rslt } = -1;
	return "";
    }

    ${ $rslt } = 0;
    return ( $data{ registrationKey }, $data{ uid }, $data{ serverURL } );
}

# Routine to get a token expiration time
sub hacGetKeyExpiration
{
    my $hacServer = shift;
    my $devRegKey = shift;
    my $tokenCSRF = shift;

    my $rslt = shift;
    my $rsltStr = shift;    

    # HAC server request command
    my $cmd = 
	"curl -f -X GET -k -H \"x-csrf-token: $tokenCSRF\" " .
	"https://$hacServer/api/v1/registration/$devRegKey " .
	"-H \"Content-Type: application/json\" " .
	" -c $tmpFile -b $tmpFile -s -S 2>&1";    

    # Error to return if the request fails
    my $errMsg = "ERROR: Can't get expiration key time!";

    my $href = execServerRequest( $cmd );
    my %data = %{ $href };

    if ( exists $data{ error } )
    {
	if ( exists $data{ error }{ message } )
	{
	    ${ $rsltStr } = $data{ error }{ message };
	}
	else
	{
	    ${ $rsltStr } = $errMsg if ( $rsltStr );
	}

	${ $rslt } = -1;
	return "";
    }

    ${ $rslt } = 0;
    return ( $data{ status }, $data{ expire_in } );
}

# Routine to get query status of a device
sub hacGetDeviceStatus
{
    my $hacServer = shift;
    my $devId = shift;
    my $tokenCSRF = shift;

    my $rslt = shift;
    my $rsltStr = shift;

    # HAC server request command
    my $cmd = 
	"curl -f -X POST -k -s -S " .
	"-H \"x-csrf-token: $tokenCSRF\" " .
	"https://$hacServer/api/v1/registration/actions " .
	"-H \"Content-Type: application/json\" " .
	"-d '" .
	encode_json( { action => "getDeviceStatus", deviceId => "$devId" } ) .
	"' -c $tmpFile -b $tmpFile 2>&1"; 

    # Error to return if the request fails
    my $errMsg = 
	"ERROR: Querying Device [ $devId ] on " .
	"server [ $hacServer ] failed!";

    my $href = execServerRequest( $cmd );
    my %data = %{ $href };

    if ( exists $data{ error } )
    {
	if ( exists $data{ error }{ message } )
	{
	    ${ $rsltStr } = $data{ error }{ message };
	}
	else
	{
	    ${ $rsltStr } = $errMsg if ( $rsltStr );
	}

	${ $rslt } = -1;
	return "";
    }

    ${ $rslt } = 0;
    return $data{ status };
}

# Routine to get query status of a device
sub hacGetWRSToken
{
    my $hacServer = shift;
    my $usrName = shift;
    my $usrPassword = shift;
    my $tokenCSRF = shift;

    my $rslt = shift;
    my $rsltStr = shift;    

    # HAC server request command
    my $cmd = 
	"curl -f -X POST -k -u $usrName:$usrPassword https://$hacServer/api/v1/authorize " .
        "-H \"Content-Type: application/json\" -H \"x-csrf-token: $tokenCSRF\" " .
        "-c $tmpFile -b $tmpFile -s -S 2>&1";

    # Error to return if the request fails
    my $errMsg = "ERROR: Getting WRS token failed!";

    my $href = execServerRequest( $cmd );
    my %data = %{ $href };

    if ( exists $data{ error } )
    {
	if ( exists $data{ error }{ message } )
	{
	    ${ $rsltStr } = $data{ error }{ message };
	}
	else
	{
	    ${ $rsltStr } = $errMsg;
	}

	${ $rslt } = -1;
	return "";
    }

    ${ $rslt } = 0;
    return $data{ token };
}

# Routine to read the SDK version from the standard file
sub getDefaultSdkVer 
{
    my $f;
    open( $f, "<", $sdkVerFile ) or
	return;
	
    my $data = <$f>;
    close( $f );

    # File should be only 1 line, which has the version of the SDK
    chomp( $data );

    return $data;
}

# Routine to read the SDK and board name from the standard file
sub getDefaultSdkName
{
    my $sdkName;
    my $boardName;

    undef $sdkName;
    undef $boardName;

    my $f;
    if ( open( $f, "<", $sdkNameFile ) )
    {
	my @data = <$f>;
	close( $f );
	chomp( @data );
	
	if ( 1 <= scalar @data )
	{
	    $sdkName = $data[ 0 ];
	}
	
	if ( 2 == scalar @data )
	{
	    $boardName = $data[ 1 ];
	}
    }

    return ( $sdkName, $boardName );
} 

# Routine to write the SDK config to the default file
sub setDefaultSdkCfgData
{
    my $cfgData = shift;

    # Backup any existing config file
    if ( -e $sdkDevCfgFile )
    {
	execCmd( "mv $sdkDevCfgFile $backupSdkDevCfgFile" );
    }

    my $f;
    open( $f, ">", $sdkDevCfgFile ) or
	return -1;
    
    # The device manager is fussy about the end of the file... Remove
    # any/all white space and append a single newline
    $cfgData =~ s|[\s\n\r]+$||;

    print $f $cfgData . "\n";
    
    close( $f );
    return 0;
} 

# Routine to read and return the SDK config from the default file
sub getDefaultSdkCfgData 
{
    my $cfgData = shift;
    my $data;

    my $f;
    open( $f, "<", $sdkDevCfgFile ) or
	return -1;
    
    $data = <$f>;
    close( $f );

    chomp( $data );

    ${ $cfgData } = $data;
    return 0;
} 

# Routine to get the default HAC server name
sub getDefaultHacServer 
{
    my $f;
    my $data;
    undef $data;

    if ( open( $f, "<", $serverCfgFile ) )
    {
	$data = <$f>;
	chomp( $data );
	close( $f );
    }

    return $data;
}

# Routine to get the default board name that has been specified, or
# generate one from the MAC of a network interface
sub getDefaultBoardName
{

    my ( $sdkName, $boardName ) = getDefaultSdkName();

    unless ( $boardName )
    {
	# Append the last 3 octets of a mac to the board name
	my $data = execCmd( "/sbin/ifconfig" );
	
	my $ha = $data;
	$ha =~ s|.*HWaddr (([A-Fa-f0-9]{2}:){3})(([A-Fa-f0-9]{2}:?){3}).*|$3|sm;
	$ha =~ s|:||g;

	my $prefix = "board";
	my $f;

	if ( open( $f, "<", $sysBoardNameFile ) )
	{
	    $prefix = <$f>;
	    close( $f );

	    chomp( $prefix );

	    # Remove leading & ending white space
	    $prefix =~ s|^\s+||;
	    $prefix =~ s|\s+$||;

	    # Turn white space to '_'
	    $prefix =~ s|\s+|_|g;
	}

	$boardName = $prefix . "_" . $ha;
    }

    return $boardName;
}

# Routine to get the default HTTPS proxy, if specified in the config
# file
sub getDefaultHttpsProxy 
{ 
    my $cfgData = shift;
    my $data;

    my $f;
    open( $f, "<", $httpsProxyCfgFile ) or
	return -1;
    
    $data = <$f>;
    close( $f );

    chomp( $data );

    ${ $cfgData } = $data;
    return 0;
}

# Routine to set the default HTTPS proxy configation file
sub setDefaultHttpsProxy
{ 
    my $cfgData = shift;

    if ( defined( $cfgData ) )
    {
	
	my $f;
	open( $f, ">", $httpsProxyCfgFile ) or
	    return -1;
	
	print $f $cfgData . "\n";
	
	close( $f );
    }
    else
    {
	# If the argument is undefined we delete the proxy file
	unlink $httpsProxyCfgFile
	    if ( -e $httpsProxyCfgFile );
    }

    return 0;    
}

# Routine to configure the HTTPS Proxy enviornment variable that will
# get used by child processes
sub useHttpsProxy
{
    my $cfgData = shift;

    # Specify the environment variable which will be used by child
    # processes / sub shells for HTTPS_PROXY
    $ENV{'HTTPS_PROXY'} = "$cfgData";
}

# Routine to break down the Device Manager config data line and return
# the pieces in a hash
# Arg 1: The string of config data to parse
# Arg 2: Reference to a hash to put the parsed data in
sub parseDevMgrData
{
   my $devCfg = shift;
   my $cfgData = shift;

   # The content of the device manager file looks like this:
   #  WSS:128.224.74.23:443;GetUrl=/ws/8002;ID=GalGen2_Linux_de2e1427-211c-4a95-b933-cf35ff7006f6;Proxy=10.10.10.1:1234
   #  -- Note: ';Proxy=...' is optional
   
   # Split the line around ';' for the major parts: 
   #  SERVER, URL, DEVICEID, PROXY
   my ($server, $url, $deviceid, $proxy ) = split(';', $devCfg, 4);
   
   # Split the server into SCHEME, IP, PORT
   my ($serverScheme, $serverIP, $serverPort) = split(':', $server, 3);
   
   logMsg( "Device server scheme, IP, port: $serverScheme, $serverIP, $serverPort\n",
	   { debug => 1 } );
   
   # Crack the DEVICEID into the user assigned NAME and server assigned
   # ID PART.
   #
   # Note that we split around the right-most '_' character
   $deviceid =~ s|^ID=||;       # Get rid of 'ID='
   
   # Device name is everything before the right most '_'
   my $devName = $deviceid;
   $devName =~ s|(.*)_.*$|$1|;
   
   logMsg( "Device name: $devName\n", { debug => 1 }  );
   
   # Device ID from the server is everything after the right most '_'
   my $devID = $deviceid;
   $devID =~ s|.*_(.*)$|$1|;
   
   logMsg( "Device ID: $devID", { debug => 1 } );

   # Clean up the proxy info
   my $proxyServer;
   my $proxyPort;
       
   if ( $proxy )
   {
       $proxy =~ s|^Proxy=||;
       ( $proxyServer, $proxyPort ) = split(':', $proxy, 2);
       logMsg( "Proxy Server: $proxyServer, Proxy Port: $proxyPort",
	       { debug => 1 } );
   }
       
   ${ $cfgData }{ cfgLine } = $devCfg;
   ${ $cfgData }{ serverScheme } = $serverScheme;
   ${ $cfgData }{ serverIP } = $serverIP;
   ${ $cfgData }{ serverPort } = $serverPort;
   ${ $cfgData }{ deviceName } = $devName;
   ${ $cfgData }{ deviceId } = $devID;
   ${ $cfgData }{ fullDevID } = $deviceid;

   if ( $proxy )
   {
       ${ $cfgData }{ proxyServer } = $proxyServer ;
       ${ $cfgData }{ proxyPort } = $proxyPort;
   }

   return 0;
}

END
{
    # Clean up cookie files
    unlink $tmpFile;
}

# Must return a true value
1;
