#!/usr/bin/perl

#############################################################################
#                                                                           #
# This script was initially developed by Infoxchange for internal use       #
# and has kindly been made available to the Open Source community for       #
# redistribution and further development under the terms of the             #
# GNU General Public License v2: http://www.gnu.org/licenses/gpl.html       #
# Copyright 2015 Infoxchange                                                #
#                                                                           #
#############################################################################
#                                                                           #
# This script is supplied 'as-is', in the hope that it will be useful, but  #
# neither Infoxchange nor the authors make any warranties or guarantees     #
# as to its correct operation, including its intended function.             #
#                                                                           #
# Or in other words:                                                        #
#       Test it yourself, and make sure it works for YOU.                   #
#                                                                           #
#############################################################################
# Author: George Hansper                     e-mail:  george@hansper.id.au  #
#############################################################################

use strict;
use Getopt::Std;

use LWP;
use LWP::UserAgent;

use Time::HiRes qw (gettimeofday tv_interval);

my $rcs_id = 'v1.0 $Id$';

my %optarg;
my $getopt_result;

my $hp_host = 'localhost';
my $snmp_community = 'public';
my $snmp_port = 161;                # default port
my $timeout = 10;			# Default timeout
my $t_warn = 10;
my $t_crit = 20;

my $ilo_ip = '';
my $encl_ip="";
my $encl_slot="";
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};
my $exit = 0;
my $ssl_verify_hostname = 0;

my @message = ();
my @perf_message = ();

my @exit = qw/OK: WARNING: CRITICAL: UNKNOWN:/;

my $expected_server = 'HP-ILO-Server|Allegro-Software-RomPager';

$getopt_result = getopts('VvhH:p:t:c:e:W:C:', \%optarg) ;

sub printv($) {
	if ( defined($optarg{v} ) ) {
		print STDERR $_[0];
	}
}

sub HELP_MESSAGE() {
	my $cmd = $0;
	$cmd =~ s{.*/}{};
	print <<EOF;
Usage:
	$cmd [-v] [-H hostname] [-p smmp_port] [-c community] [-t time_out] [-e regex] [-W warn] [-C crit]

	-H  ... Hostname or IP (default: $hp_host)
	-p  ... SNMP Port number (default: ${snmp_port})
	-c  ... SNMP Community string (default: $snmp_community)
	-t  ... Seconds before connection times out (default: $timeout)
	-e  ... Expected regex for HTTP Header 'Server' (default: $expected_server )
	        (case insensitive matching used)
	-W  ... Warning  if ILO HTTP response takes more than warn seconds (default: $t_warn)
	-C  ... Critical if ILO HTTP response takes more than crit seconds (default: $t_crit)
	-v  ... verbose output
EOF
}

sub VERSION_MESSAGE() {
	print "perl: $^V\n$0: $rcs_id\n";
}

if ( $optarg{h} ) {
	HELP_MESSAGE();
	exit 0;
}

if ( $optarg{V} ) {
	VERSION_MESSAGE();
	exit 0;
}

if ( defined($optarg{H} ) ) {
	$hp_host = $optarg{H};
}

# Is port number numeric?
if ( defined($optarg{p}) ) {
	$snmp_port = $optarg{p};
	if ( $snmp_port !~ /^[0-9][0-9]*$/ ) {
		print STDERR <<EOF;
		Port must be a decimal number, eg "-p 161"
EOF
	exit 1;
	}
}

if ( defined($optarg{c} ) ) {
	$snmp_community = $optarg{c};
}

if ( defined($optarg{t}) ) {
	$timeout = $optarg{t};
}

if ( defined($optarg{W}) ) {
	$t_warn = $optarg{W};
}

if ( defined($optarg{C}) ) {
	$t_crit = $optarg{C};
}

if ( defined($optarg{e}) ) {
	$expected_server = $optarg{e};
}

sub check_http ($) {
  my $ilo = $_[0];
  my $lwp_user_agent = LWP::UserAgent->new;
  $lwp_user_agent->timeout($timeout);
  $lwp_user_agent->ssl_opts( verify_hostname => $ssl_verify_hostname );
  $lwp_user_agent->default_header('Connection' => 'close');

  my $url = "https://${ilo}/";
  my $http_request = HTTP::Request->new(GET => $url);

  my $start_req = [gettimeofday()];
  my $http_response = $lwp_user_agent->request($http_request);
  my $end_req = [gettimeofday()];
  my $t_request = tv_interval($start_req,$end_req);
  push @perf_message,sprintf("time=%05.4f",$t_request);

  printv "---------------\n" . $http_response->protocol . " " . $http_response->status_line;
  printv "--- Request headers";
  printv $http_request->headers_as_string;

  printv "--- Response headers";
  printv $http_response->headers_as_string;
  #printv $http_response->server."\n";
  if ( $http_response->header( 'Title' ) =~ /ilo/i ) {
    push @message,$http_response->header( 'Title' );
  }
  if ( $http_response->code eq '401' && $http_response->header('WWW-Authenticate' ) ) {
    push @message, 'Autheniticated HTTP server found'.$http_response->server;
    # OK
  } elsif ( ! $http_response->is_success) {
    $exit |= 2;
    push @message, 'HTTP Error: '. $http_response->status_line;
  } elsif ( defined($http_response->server) && $http_response->server =~ /${expected_server}/i ) {
    push @message, 'HP ILO found: '.$http_response->server;
    # OK
  } elsif ( $http_response->header('Title') =~ /HP Integrated Lights-Out/ ) {
    push @message,$http_response->header( 'Title' );
    push @message, 'HP ILO found';
    # OK
  } elsif ( $http_response->server eq '' ) {
    $exit |= 1;
    push @message, 'HTTP Header not found: Server';
  } else {
    $exit |= 1;
    push @message, 'HTTP Server is '.$http_response->server." (Should match /${expected_server}/ )";
  }
  if ( $t_request > $t_crit ) {
    $exit |= 2;
    push @message, sprintf('(!!) HTTP reponse took %.1fs (> %.1fs)',$t_request,${t_crit});
  } elsif ( $t_request > $t_warn ) {
    $exit |= 1;
    push @message, sprintf('(!) HTTP reponse took %.1fs (> %.1fs)',$t_request,${t_warn});
  }
}

#########################################################################
# ILO IP address
#########################################################################
#$file = "snmpget -c $snmp_community -v 2c localhost:161 enterprises.232.9.2.5.1.1.5.2|";
my %oids = ( ILO => ".1.3.6.1.4.1.232.9.2.5.1.1.5.2",
	     Encl => ".1.3.6.1.4.1.232.2.2.13.1.1.3.1",
	     Slot => ".1.3.6.1.4.1.232.2.2.14.1.0",
#	     DRAC => ".1.3.6.1.4.1.674.10892.1.1900.30.1.9.1.1.1",
	 );
my $file = "snmpget -c $snmp_community -v 2c -On -t " . int(($timeout+2)/3) . " -r 2 $hp_host:$snmp_port ".join(" ",values(%oids))." 2>&1 |";
if ( open(SNMPGET,$file) ) {
	my @snmpget =  ( <SNMPGET> );
	close SNMPGET;
	printv(join("",@snmpget));
	chomp @snmpget;
	($ilo_ip) = grep( { if ( /$oids{ILO} = IpAddress:\s*(\S+)/i ) { $_ = $1; } } ( @snmpget ) );
	($encl_ip) = grep( { if ( /$oids{Encl} = STRING:\s*(\S+)/i ) { $_ = $1; } } ( @snmpget ) );
	($encl_slot) = grep( { if ( /$oids{Slot} = INTEGER:\s*(\S+)/i ) { $_ = $1; } } ( @snmpget ) );
	if ( defined($ilo_ip) && $ilo_ip ne '' ) {
		$message[0] = "ILO=$ilo_ip";
		if ( defined($encl_ip) && $encl_ip ne '' ) {
			$encl_ip =~ s/^"|"$//g;
			push @message,'Chassis='.$encl_ip;
		}
		if ( defined($encl_slot) && $encl_slot ne '' ) {
			push @message,'Slot='.$encl_slot;
		}
		check_http($ilo_ip);
	} elsif ( $snmpget[0] =~ /No Such Instance/i ) {
		$message[0] = "ILO=not available";
		$message[1] = "SNMP not configured - run /sbin/hpsnmpconfig";
		push @perf_message,'time=U';
		$exit |= 1;

	} else {
		$message[0] = "ILO=not available";
		$message[1] = join(" ",@snmpget);
		push @perf_message,'time=U';
		$exit |= 2;
	}
} else {
	print STDERR "Could not run $file: $!\n";
	$message[0] = "ILO=not available";
	$message[1] = "Could not connect to $hp_host:$snmp_port snmpget: $!";
	push @perf_message,'time=U';
	$exit |= 2;
}

#########################################################################

if ( $exit == 3 ) {
	$exit = 2;
} elsif ( $exit > 3 || $exit < 0 ) {
	$exit = 3;
}

print "$exit[$exit] " . join(", ",@message)."|".join(" ",@perf_message) . "\n";
exit($exit);
