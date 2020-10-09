##############################################
# $Id$
# Written by Markus Feist, 2020
package main;

use strict;
use warnings;
use HttpUtils;
use SetExtensions;

sub LLPDU8P01_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = "LLPDU8P01_Define";
    $hash->{UndefFn}  = "LLPDU8P01_Undef";
    $hash->{SetFn}    = "LLPDU8P01_Set";
    $hash->{GetFn}    = "LLPDU8P01_Get";
    $hash->{AttrFn}   = "LLPDU8P01_Attr";
    $hash->{RenameFn} = "LLPDU8P01_Rename";
    $hash->{AttrList} = "expert:0,4 " . "stateFormat " . $readingFnAttributes;
    Log3 "LLPDU8P01", 5, "LLPDU8P01_Initialize finished.";
}

sub LLPDU8P01_Define($$) {
    my ( $hash, $def ) = @_;
    my @a          = split( "[ \t][ \t]*", $def );
    my $paramCount = int(@a);
    my ( $name, $type, $ip, $intervall, $username, $password ) = @a;
    Log3 $name, 5, "$name LLPDU8P01: define $name, $type, $ip";

    if ( ( $paramCount < 6 ) && ( $paramCount > 3 ) ) {

        #TODO: Konfigurationsdatei lesen
        Log3 $name, 1, "LLPDU8P01: Configfile not implemented yet.";
        return "Error Configfile not implemented yet.";
    }
    $username  = "admin" if ( !defined($username) );
    $password  = "admin" if ( !defined($password) );
    $intervall = 10      if ( !defined($intervall) );
    $intervall =~ s/,/./g;
    return
"Usage: define <name> LLPDU8P01 <_ParentName_CHANNEL/IP-Adress/HostName> <Intervall for Check> [<Username> <Password> | <File with Username/Password>] "
      if (
        !defined($ip)
        || (
            ( $paramCount > 3 )
            && (   !defined($username)
                || !defined($password) )
        )
      );

    if ( substr( $ip, 0, 1 ) eq "_" ) {    # define a channel
        if ( defined( $hash->{device} ) && defined( $hash->{chanNo} ) ) {
            my $oldParentHash = $defs{ $hash->{device} };
            delete $oldParentHash->{"channel_$hash->{chanNo}"};
        }
        my ( $parentName, $chn ) = $ip =~ /_(.*)_(\d*)/g;
        my $parentHash = $modules{LLPDU8P01}{defptr}{$parentName};
        return "please define a device with Name:" . $parentName . " first"
          if ( !$parentHash );
        $parentName                   = $parentHash->{NAME};
        $hash->{device}               = $parentName;
        $hash->{chanNo}               = $chn;
        $parentHash->{"channel_$chn"} = $name;
    }
    else {
        $modules{LLPDU8P01}{defptr}{$name} = $hash;
        $hash->{"hostname"}                = $ip;
        $hash->{".username"}               = LLPDU8P01_decrypt($username);
        $hash->{".password"}               = LLPDU8P01_decrypt($password);
        $hash->{"intervall"}               = $intervall;
        InternalTimer( gettimeofday() + $intervall,
            "LLPDU8P01_CheckStatusTimer", $hash )
          if ( $intervall > 0 );
        $username = LLPDU8P01_encrypt($username);
        $password = LLPDU8P01_encrypt($password);
        $hash->{DEF} = "$ip $username $password $intervall"
    }
    return undef;
}

sub LLPDU8P01_Rename($$$) {    #############################
    my ( $name, $oldName ) = @_;
    my $hash = $defs{$name};
    return if ( $hash->{TYPE} ne "LLPDU8P01" );
    if ( defined( $hash->{chanNo} ) ) {    # we are channel, inform the device
        my $devName = $hash->{device};
        my $devHash = $defs{$devName};
        $devHash->{ "channel_" . $hash->{chanNo} } = $name;
    }
    else {    # we are a device - inform channels if exist
        foreach ( grep ( /^channel_/, keys %{$hash} ) ) {
            next if ( !$_ );
            my $chnHash = $defs{ $hash->{$_} };
            $chnHash->{device} = $name;
            my $chnNo = $chnHash->{chanNo};
            $chnHash->{"DEF"} = "_${name}_${chnNo}";
        }
    }
}

sub LLPDU8P01_Undef($$) {
    my ( $hash, $name ) = @_;
    Log3 $name, 5, "$name LLPDU8P01: Undef $name";
    RemoveInternalTimer( $hash, "LLPDU8P01_CheckStatusTimer" );
    my $chn = $hash->{chanNo};
    if ( defined($chn) ) {    # delete a channel
        CancelExtensionsCancel($hash);
        my $devName = $hash->{device};
        my $devHash = $defs{$devName};
        delete $devHash->{"channel_$chn"} if ($devName);
    }
    else {                    # delete a device
        CommandDelete( undef, $hash->{$_} )
          foreach ( grep( /^channel_/, keys %{$hash} ) );
        delete $modules{LLPDU8P01}{defptr}{ $hash->{DeviceID} };
    }
    return undef;
}

sub LLPDU8P01_Attr($$$$) {
    my ( $cmd, $name, $attrName, $attrValue ) = @_;

    if ( $cmd eq "set" ) {
        if ( $attrName eq "expert" ) {
            if ( $attrValue !~ /^[04]$/ ) {
                Log3 $name, 3,
"$name LLPDU8P01: Invalid parameter attr $name $attrName $attrValue";
                return "Invalid value $attrValue allowed 0,4";
            }
        }
    }
    return undef;
}

sub LLPDU8P01_Get ($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    if ( $cmd eq "status" ) {
        LLPDU8P01_CheckStatus( LLPDU801_GetDevHash($hash), $name );
        return undef;
    }
    else {
        return "Unknown argument $cmd, choose one of status:noArg";
    }
}

sub LLPDU801_GetChannels($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    if ( defined( $hash->{chanNo} ) ) {
        return ( $hash->{chanNo} );
    }
    else {
        return split /,/, $args[0];
    }
}

sub LLPDU801_GetDevHash($) {
    my ($hash) = @_;
    if ( defined( $hash->{chanNo} ) ) {
        my $devName = $hash->{device};
        return $defs{$devName};
    }
    else {
        return $hash;
    }
}

sub LLPDU8P01_Set ($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "clear" ) {
        if ( $args[0] eq "readings" ) {
            for ( keys %{ $hash->{READINGS} } ) {
                readingsDelete( $hash, $_ ) if ( $_ ne 'state' );
            }
            return undef;
        }
        else {
            return "Unknown value $args[0] for $cmd, choose one of readings";
        }
    }
    elsif ( $cmd eq "statusRequest" ) {
        LLPDU8P01_CheckStatus( LLPDU801_GetDevHash($hash), $name );
        return undef;
    }
    elsif ( $cmd eq "on" ) {
        my @channels = LLPDU801_GetChannels( $hash, $name, $cmd, @args );
        Log3 $name, 5, "$name LLPDU8P01: on Command for @channels";
        my $devHash = LLPDU801_GetDevHash($hash);
        LLPDU8P01_SetSocketsState( $devHash, $name, "set_on", @channels );
        LLPDU8P01_SetSockets( $devHash, $name, 0, @channels );
        return undef;
    }
    elsif ( $cmd eq "off" ) {
        my @channels = LLPDU801_GetChannels( $hash, $name, $cmd, @args );
        Log3 $name, 5, "$name LLPDU8P01: off Command for @channels";
        my $devHash = LLPDU801_GetDevHash($hash);
        LLPDU8P01_SetSocketsState( $devHash, $name, "set_off", @channels );
        LLPDU8P01_SetSockets( $devHash, $name, 1, @channels );
        return undef;
    }
    elsif ( $cmd eq "onoff" ) {
        my @channels = LLPDU801_GetChannels( $hash, $name, $cmd, @args );
        Log3 $name, 5, "$name LLPDU8P01: onoff Command for @channels";
        my $devHash = LLPDU801_GetDevHash($hash);
        LLPDU8P01_SetSocketsState( $devHash, $name, "set_onoff", @channels );
        LLPDU8P01_SetSockets( $devHash, $name, 2, @channels );
        return undef;
    }
    elsif ( $cmd eq "autocreate" ) {
        for ( my $channel = 0 ; $channel < 8 ; $channel++ ) {
            my $devHash = LLPDU801_GetDevHash($hash);
            my $devName = $devHash->{NAME};
            if ( !defined( $devHash->{"channel_$channel"} ) ) {
                Log3 $name, 5,
                  "$name LLPDU8P01: Create Channel $channel for $devName";
                my $cmdret = CommandDefine( undef,
                    "${devName}_$channel LLPDU8P01 _${devName}_$channel" );
                if ($cmdret) {
                    Log3 $name, 1,
"$name LLPDU8P01: Autocreate: An error occurred while creating channel $channel: $cmdret";
                }
                else {
                    CommandAttr( undef,
                        "${devName}_$channel room $hash->{TYPE}" );
                }
            }
        }
    }
    elsif ( $cmd eq "getConfig" ) {
        my $hostname  = $hash->{"hostname"};
        my $httpparam = {
            url         => "http://$hostname/config_PDU.htm",
            timeout     => 20,
            httpversion => "1.1",
            hash        => $hash,
            method      => "GET",
            user        => $hash->{".username"},
            pwd         => $hash->{".password"},
            callback    => \&LLPDU8P01_NonblockingGet_Callback_Config
        };
        HttpUtils_NonblockingGet($httpparam);
        return undef;
    }
    elsif ( defined( $hash->{chanNo} ) ) {
        return SetExtensions(
            $hash,
            "clear:readings statusRequest:noArg on:noArg off:noArg onoff:noArg",
            $name,
            $cmd,
            @args
        );
    }
    else {
        return
"Unknown argument $cmd, choose one of clear:readings statusRequest:noArg on:multiple,0,1,2,3,4,5,6,7 off:multiple,0,1,2,3,4,5,6,7 onoff:multiple,0,1,2,3,4,5,6,7 autocreate:noArg getConfig:noArg";
    }
}

sub LLPDU8P01_SetSockets($$$@) {
    my ( $hash, $name, $op, @outlets ) = @_;
    my $hostname = $hash->{"hostname"};
    my $request;

    foreach (@outlets) {
        $request = $request . "outlet$_=1&";
    }
    $request = $request . "op=$op&submit=Apply";
    my $httpparam = {
        url         => "http://$hostname/control_outlet.htm?$request",
        timeout     => 20,
        httpversion => "1.1",
        hash        => $hash,
        method      => "GET",
        user        => $hash->{".username"},
        pwd         => $hash->{".password"},
        callback    => \&LLPDU8P01_NonblockingGet_Callback_SetSockets
    };
    Log3 $name, 5, "$name LLPDU8P01: Requesturl $httpparam->{url}";
    HttpUtils_NonblockingGet($httpparam);
}

sub LLPDU8P01_SetSocketsState($$$@) {
    my ( $hash, $name, $value, @outlets ) = @_;
    Log3 $name, 5, "$name LLPDU8P01: SetSocketsState $value for @outlets";
    readingsBeginUpdate($hash);
    foreach (@outlets) {
        my $s = $_;
        Log3 $name, 5, "$name LLPDU8P01: SetSocketsState $value for $s";
        readingsBulkUpdate( $hash, "outlet${s}Stat", $value );
        my $channelHash = $hash->{"channel_$s"};
        $channelHash = $defs{$channelHash} if ( defined($channelHash) );
        readingsSingleUpdate( $channelHash, "state", $value, 1 )
          if ( defined($channelHash) );
    }
    readingsEndUpdate( $hash, 1 );
}

sub LLPDU8P01_NonblockingGet_Callback_SetSockets($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $code = $param->{code};
    Log3 $name, 4, "$name LLPDU8P01: Callback";
    if ( $err ne "" ) {
        Log3 $name, 1,
            "$name LLPDU8P01: error while statusrequest to "
          . $param->{url}
          . " - $err";
        readingsSingleUpdate( $hash, "state", "HTTP COMM ERROR $err", 1 );
    }
    elsif ( $code != 200 ) {
        Log3 $name, 1,
            "$name LLPDU8P01: http-error while statusrequest to "
          . $param->{url} . " - "
          . $param->{code};
        Log3 $name, 3, "$name LLPDU8P01: http-header: " . $param->{httpheader};
        Log3 $name, 3, "$name LLPDU8P01: http-data: " . $data;
        readingsSingleUpdate( $hash, "state", "HTTP ERROR $code", 1 );
    }
    else {
        Log3 $name, 4, "$name LLPDU8P01: command execute successfully.";
    }
    my $intervall = $hash->{"intervall"};
    if ( $intervall == 0 ) {
        Log3 $name, 3, "$name LLPDU8P01: No autmatic polling, call manual";
        foreach ( grep( /^outlet.*Delay/, keys %{ $hash->{READINGS} } ) ) {
            next if ( !$_ );
            my $test = $hash->{READINGS}{$_}{VAL};
            Log3 $name, 4, "$name LLPDU8P01: Scan $_ $test";
            $intervall = $test if ( defined($test) && ( $test > $intervall ) );
        }
        $intervall = 20 if ( $intervall == 0 );
        $intervall += 1;
        Log3 $name, 4,
          "$name LLPDU8P01: Statusrequest with intervall $intervall";
        InternalTimer( gettimeofday() + $intervall,
            "LLPDU8P01_CheckStatusTimer", $hash );
    }
}

sub LLPDU8P01_NonblockingGet_Callback_Config($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $code = $param->{code};
    Log3 $name, 4, "$name LLPDU8P01: Callback";
    if ( $err ne "" ) {
        Log3 $name, 1,
            "$name LLPDU8P01: error while statusrequest to "
          . $param->{url}
          . " - $err";
        readingsSingleUpdate( $hash, "state", "HTTP COMM ERROR $err", 1 );
    }
    elsif ( $code != 200 ) {
        Log3 $name, 1,
            "$name LLPDU8P01: http-error while statusrequest to "
          . $param->{url} . " - "
          . $param->{code};
        Log3 $name, 3, "$name LLPDU8P01: http-header: " . $param->{httpheader};
        Log3 $name, 3, "$name LLPDU8P01: http-data: " . $data;
        readingsSingleUpdate( $hash, "state", "HTTP ERROR $code", 1 );
    }
    else {
        Log3 $name, 5, "$name LLPDU8P01: getConfig successfull";
        Log3 $name, 5, "$name LLPDU8P01: http-header: " . $param->{httpheader};
        Log3 $name, 5, "$name LLPDU8P01: http-data: " . $data;
        readingsBeginUpdate($hash);
        for ( my $s = 0 ; $s < 8 ; $s++ ) {
            my $channelHash = $hash->{"channel_$s"};
            if ( defined($channelHash) ) {
                $channelHash = $defs{$channelHash};
                readingsBeginUpdate($channelHash);
            }
            if ( $data =~ /<input name="otlt$s" [^>]* value="([^"]*)"/ ) {
                readingsBulkUpdate( $hash,        "outlet${s}Name", $1 );
                readingsBulkUpdate( $channelHash, "outletName",     $1 )
                  if ( defined($channelHash) );
            }
            if ( $data =~ /<input name="ondly$s" [^>]* value="([^"]*)"/ ) {
                readingsBulkUpdate( $hash,        "outlet${s}OnDelay", $1 );
                readingsBulkUpdate( $channelHash, "outletOnDelay",     $1 )
                  if ( defined($channelHash) );
            }
            if ( $data =~ /<input name="ofdly$s" [^>]* value="([^"]*)"/ ) {
                readingsBulkUpdate( $hash,        "outlet${s}OffDelay", $1 );
                readingsBulkUpdate( $channelHash, "outletOffDelay",     $1 )
                  if ( defined($channelHash) );
            }
            readingsEndUpdate( $channelHash, 1 ) if ( defined($channelHash) );
        }
        readingsEndUpdate( $hash, 1 );
    }
    HttpUtils_Close($param);
}

sub LLPDU8P01_CheckStatus($$) {
    my ( $hash, $name ) = @_;
    my $hostname = $hash->{"hostname"};

    my $httpparam = {
        url         => "http://$hostname/status.xml",
        timeout     => 20,
        httpversion => "1.1",
        hash        => $hash,
        method      => "GET",
        callback    => \&LLPDU8P01_NonblockingGet_Callback_Status
    };
    HttpUtils_NonblockingGet($httpparam);
}

sub LLPDU8P01_NonblockingGet_Callback_Status($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $code = $param->{code};
    Log3 $name, 4, "$name LLPDU8P01: Callback";
    if ( $err ne "" ) {
        Log3 $name, 1,
            "$name LLPDU8P01: error while statusrequest to "
          . $param->{url}
          . " - $err";
        readingsSingleUpdate( $hash, "state", "HTTP COMM ERROR $err", 1 );
    }
    elsif ( $code != 200 ) {
        Log3 $name, 1,
            "$name LLPDU8P01: http-error while statusrequest to "
          . $param->{url} . " - "
          . $param->{code};
        Log3 $name, 3, "$name LLPDU8P01: http-header: " . $param->{httpheader};
        Log3 $name, 3, "$name LLPDU8P01: http-data: " . $data;
        readingsSingleUpdate( $hash, "state", "HTTP ERROR $code", 1 );
    }
    else {
        Log3 $name, 5, "$name LLPDU8P01: statusrequest successfull";
        Log3 $name, 5, "$name LLPDU8P01: http-header: " . $param->{httpheader};
        Log3 $name, 5, "$name LLPDU8P01: http-data: " . $data;
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "stateDevice", $1 )
          if ( $data =~ /<statBan>([^<]*)<\/statBan>/ );
        readingsBulkUpdate( $hash, "current", $1 )
          if ( $data =~ /<curBan>([^<]*)<\/curBan>/ );
        readingsBulkUpdate( $hash, "temperature", $1 )
          if ( $data =~ /<tempBan>([^<]*)<\/tempBan>/ );
        readingsBulkUpdate( $hash, "humidity", $1 )
          if ( $data =~ /<humBan>([^<]*)<\/humBan>/ );

        my $stateSocketsOn  = "";
        my $stateSocketsOff = "";
        for ( my $s = 0 ; $s < 8 ; $s++ ) {
            if ( $data =~ /<outletStat$s>([^<]*)<\/outletStat$s>/ ) {
                readingsBulkUpdate( $hash, "outlet${s}Stat", $1 );
                my $channelHash = $hash->{"channel_$s"};
                if ( defined($channelHash) ) {
                    $channelHash = $defs{$channelHash};
                    readingsSingleUpdate( $channelHash, "state", $1, 1 );
                }
                if ( $1 eq "on" ) {
                    $stateSocketsOn = $stateSocketsOn . "$s,";
                }
                else {
                    $stateSocketsOff = $stateSocketsOff . "$s,";
                }
            }
        }
        $stateSocketsOn  = substr( $stateSocketsOn,  0, -1 );
        $stateSocketsOff = substr( $stateSocketsOff, 0, -1 );
        readingsBulkUpdate( $hash, "state", $stateSocketsOn );
        readingsBulkUpdate( $hash, "on",    $stateSocketsOn );
        readingsBulkUpdate( $hash, "off",   $stateSocketsOff );
        readingsEndUpdate( $hash, 1 );
    }
    HttpUtils_Close($param);
}

sub LLPDU8P01_CheckStatusTimer($) {
    my ($hash)    = @_;
    my $name      = $hash->{"NAME"};
    my $intervall = $hash->{"intervall"};
    Log3 $name, 5, "$name LLPDU8P01: CheckStatusTimer called.";
    LLPDU8P01_CheckStatus( $hash, $name );
    Log3 $name, 5, "$name LLPDU8P01: CheckStatusTimer set InternalTimer.";
    InternalTimer( gettimeofday() + $intervall,
        "LLPDU8P01_CheckStatusTimer", $hash )
      if ( $intervall > 0 );
}

sub LLPDU8P01_encrypt($) {
    my ($decoded) = @_;
    my $key = getUniqueId();
    my $encoded;

    return $decoded if ( $decoded =~ /^crypt:(.*)/ );

    for my $char ( split //, $decoded ) {
        my $encode = chop($key);
        $encoded .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }

    return 'crypt:' . $encoded;
}
sub LLPDU8P01_decrypt($) {
    my ($encoded) = @_;
    my $key = getUniqueId();
    my $decoded;

    $encoded = $1 if ( $encoded =~ /^crypt:(.*)/ );

    for my $char ( map { pack( 'C', hex($_) ) } ( $encoded =~ /(..)/g ) ) {
        my $decode = chop($key);
        $decoded .= chr( ord($char) ^ ord($decode) );
        $key = $decode . $key;
    }

    return $decoded;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;

=pod
=item device
=item summary    modul to control LogiLink PDU8P01GW
=item summary_DE Modul zur Steuerung LogiLink PDU8P01GW
=begin html

<a name="LLPDU8P01"></a>
<h3>LLPDU8P01</h3>
<ul>
  The LLPDU8P01 is a fhem module for Logilink PDU8P01 and possible Intellinet 163682.<br>
  <br>

  <a name="LLPDU8P01define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LLPDU8P01 &lt;IP/Hostname&gt; &lt;Pollintervall&gt; &lt;Username/File with Logindata&gt; &lt;opt. Password&gt;</code><br>
    <br>
    IP/Hostname: IP/Hostname of the PDU8P01
    <br>
    Pollintervall: Intervall for polling State in Seconds
    <br>
    Username: Username or alternativ a file where to get username and password
    <br>
    Password optional: Password (if not defined username will be used as filename)
    <br>
    alternative:<br>
    <code>define &lt;name&gt; LLPDU8P01 &lt;_ParentName_Channel&gt;</code><br>
  </ul>
  <br>

  <a name="LLPDU8P01readings"></a>
  <b>Readings - Device</b>
  <ul>
    <li>current<br>Current measured</li>
    <li>humidity<br>Humidity measured</li>    
    <li>on<br>Sockets which are on</li>
    <li>off<br>Sockets which are off</li>
    <li>outlet0Stat - outlet7Stat<br>Status of outlet</li>
    <li>outlet0Name - outlet7Name<br>Name of outlet</li>
    <li>outlet0OnDelay - outlet7OnDelay<br>On delay of outlet</li>
    <li>outlet0OffDelay - outlet7OffDelay<br>Off delay of outlet</li>
    <li>temperature<br>Temperature measured</li>
    <li>state<br>Sockets which are on or last error</li>
    <li>stateDevice<br>Reported state of device</li>
  </ul>
  <b>Readings - Channel</b>
  <ul>
    <li>state<br>State of socket</li>
  </ul>
  <br>  
  <a name="LLPDU8P01set"></a>
  <b>Set - Device</b>
  <ul>
    <li><code>set &lt;name&gt; autocreate</code><a name="LLPDU8P01autocreate"></a><br>
    Creates not present channels</li>
    <li><code>set &lt;name&gt; clear readings</code><a name="LLPDU8P01clear"></a><br>
    Clears the readings</li>
    <li><code>set &lt;name&gt; off &lt;socketlist&gt;</code><a name="LLPDU8P01off"></a><br>
    Sets a list of Sockets to off</li>
    <li><code>set &lt;name&gt; on &lt;socketlist&gt;</code><a name="LLPDU8P01on"></a><br>
    Sets a list of Sockets to on</li>    
    <li><code>set &lt;name&gt; onoff &lt;socketlist&gt;</code><a name="LLPDU8P01onoff"></a><br>
    Sets a list of Sockets to off then on</li>        
    <li><code>set &lt;name&gt; statusRequest</code><a name="LLPDU8P01statusRequest"></a><br>
    Requests a status update</li>
    <li><code>set &lt;name&gt; getConfig</code><a name="LLPDU8P01getConfig"></a><br>
    Reads the configuration of the PDU</li>
  </ul>
  <br>
  <b>Set - Channel</b>
  <ul>
    <li><code>set &lt;name&gt; clear readings</code><br>
    Clears the readings</li>
    <li><code>set &lt;name&gt; statusRequest</code><br>
    Requests a status update</li>
    <li>The <a href="#setExtensions">set extensions</a> are supported by this module.</li>
  </ul>
  <br>  

  <a name="LLPDU8P01get"></a>
  <b>Get</b>
  <ul>
    <li><code>set &lt;name&gt; status</code><a name="LLPDU8P01status"></a><br>
    Requests a status update</li>
  </ul>
  <br>
  <br>

  <a name="LLPDU8P01attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>  
    <li>expert<br>Defines how many readings are show (0=only minimal info, 4=all).</li>        
  </ul>
</ul>

=end html
=begin html_DE

<a name="LLPDU8P01"></a>
<h3>LLPDU8P01</h3>
<ul>
  LLPDU8P01 ist ein FHEM-Modul f&uuml;r die Logilink PDU8P01 und da vermutlich baugleich f&uuml;r die Intellinet 163682.<br>
  <br>

  <a name="LLPDU8P01define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LLPDU8P01 &lt;IP/Hostname&gt; &lt;Pollintervall&gt; &lt;Username/File with Logindata&gt; &lt;opt. Password&gt;</code><br>
    <br>
    IP/Hostname: IP/Hostname der PDU8P01
    <br>
    Pollintervall: Intervall f&uuml;r das Polling in Sekunden
    <br>
    Username: Username oder alternativ eine Datei aus der Username und Passwort abgeholt werden.
    <br>
    Password optional: Passwort (wenn nicht gesetzt, wird der Username als Dateiname verwendet)
    <br>
    alternative:<br>
    <code>define &lt;name&gt; LLPDU8P01 &lt;_ParentName_Channel&gt;</code><br>
  </ul>
  <br>

  <a name="LLPDU8P01readings"></a>
  <b>Readings - Device</b>
  <ul>
    <li>current<br>Gemessene Stromst&auml;rke</li>
    <li>humidity<br>Gemessene Luftfeuchte</li>    
    <li>on<br>Angabe welche Steckdosen an sind.</li>
    <li>off<br>Angabe welche Steckdosen aus sind.</li>
    <li>outlet0Stat0 - outlet7Stat<br>Status der Steckdosen</li>
    <li>outlet0Name - outlet7Name<br>Name der Steckdose</li>
    <li>outlet0OnDelay - outlet7OnDelay<br>On delay der Steckdose</li>
    <li>outlet0OffDelay - outlet7OffDelay<br>Off delay der Steckdose</li>
    <li>temperature<br>Gemessene Temperatur</li>
    <li>state<br>Angabe welche Steckdosen an sind, oder der letzte Fehler</li>
    <li>stateDevice<br>Status des Ger&auml;tes</li>
  </ul>
  <b>Readings - Kan&auml;le</b>
  <ul>
    <li>state<br>Status der Steckdose</li>
  </ul>
  <br>  
  <a name="LLPDU8P01set"></a>
  <b>Set - Device</b>
  <ul>
    <li><code>set &lt;name&gt; autocreate</code><a name="LLPDU8P01autocreate"></a><br>
    Erzeugt nicht vorhandene Kan&auml;le</li>
    <li><code>set &lt;name&gt; clear readings</code><a name="LLPDU8P01clear"></a><br>
    L&ouml;scht die readings</li>
    <li><code>set &lt;name&gt; off &lt;socketlist&gt;</code><a name="LLPDU8P01off"></a><br>
    Setzt eine Liste von Steckdosen auf aus</li>
    <li><code>set &lt;name&gt; on &lt;socketlist&gt;</code><a name="LLPDU8P01on"></a><br>
    Setzt eine Liste von Steckdosen auf an</li>    
    <li><code>set &lt;name&gt; onoff &lt;socketlist&gt;</code><a name="LLPDU8P01onoff"></a><br>
    Setzt eine Liste von Steckdosen auf aus und dann an</li>        
    <li><code>set &lt;name&gt; statusRequest</code><a name="LLPDU8P01statusRequest"></a><br>
    Holt eine Statusabfrage ab</li>
    <li><code>set &lt;name&gt; getConfig</code><a name="LLPDU8P01getConfig"></a><br>
    Liest die Konfiguration der PDU</li>
  </ul>
  <br>
  <b>Set - Kan&auml;le</b>
  <ul>
    <li><code>set &lt;name&gt; clear readings</code><br>
    L&ouml;scht die readings</li>
    <li><code>set &lt;name&gt; statusRequest</code><br>
    Holt eine Statusabfrage ab</li>
    <li>Die <a href="#setExtensions">Set-Erweiterungen</a> werden von diesem Modul unterst&uuml;zt.</li>
    <li><code>set &lt;name&gt; onoff</code><br>
    Schaltet die Steckdose erst aus und dann an.</li>
  </ul>
  <br>  

  <a name="LLPDU8P01get"></a>
  <b>Get</b>
  <ul>
    <li><code>set &lt;name&gt; status</code><a name="LLPDU8P01status"></a><br>
    Holt eine Statusabfrage</li>
  </ul>
  <br>
  <br>

  <a name="LLPDU8P01attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>  
    <li>expert<br>Gibt an wieviele Readings angezeigt werden (0=nur minimal, 4=alle).</li>        
  </ul>
</ul>

=end html_DE
=cut
