#!/usr/bin/perl -w

use strict;
use warnings;

use Cwd;
use IO::Pty;
use IO::Pty::Easy;
use Net::Telnet;

################################################################################

my $cfg = {

    # server
    host => "192.168.100.2",
    port => 23,

    # credentials
    username => "username",
    password => "password",

    # directories
    sendpath => "/opt/tmw/send",
    recvpath => "/opt/tmw/recv",

    # timeout
    timeout => 20,

    # logging
    verbose => 0,

};


my $ts;

sub tmwng_log
{
    my ($fmt, @args) = @_;

use POSIX qw(strftime);
    printf(STDERR "%s $fmt\n", strftime("[%F %T]", localtime), @args);
}

sub tmwng_login
{
    $ts->output_field_separator("\r");
    $ts->output_record_separator("\r");
    
    $ts->waitfor('/name =>/i');
    $ts->print( $cfg->{username} );
    $ts->waitfor('/word =>/i');
    $ts->print( $cfg->{password} );
    $ts->waitfor('/uage =>/i');
    $ts->print('#zsd');

    $ts->waitfor('/logon_ok_mail/i');
    $ts->errmode('return');

    tmwng_log("Authentication completed");
}

sub ls_files_by_date
{
    my $root = shift;

    my @list = ();

    opendir(DIR, $root);
    while (my $file = readdir(DIR)) {
	next unless (-f "$root/$file");
	push @list, "$root/$file";
    }
    closedir(DIR);

    return sort {(stat $a)[9] <=> (stat $b)[9]} @list;
}

sub tmwng_send_files
{
    tmwng_log("Sending files ($cfg->{sendpath})...");

    my @files_to_send = ls_files_by_date($cfg->{sendpath});
    unless (@files_to_send) {
	my $nullfile = "$cfg->{sendpath}/null";
	open(FILE, ">$nullfile") and close(FILE);
	push @files_to_send, $nullfile;
    }

    my $sz_command = sprintf(
	"/usr/bin/sz -u %s %s %s",
	$cfg->{verbose} ? "-v" : "-q",			#1
	join(' ', @files_to_send),			#2
	$cfg->{verbose} ? "2>>/tmp/tmwng_sz.log" : ""	#3
    );

    my $pty = IO::Pty::Easy->new();
    $pty->spawn("cd $cfg->{sendpath}; $sz_command");

    while ($pty->is_active)
    {
	my $data;

	$data = $pty->read(0);
	if (defined $data and length($data)) {
	    $ts->put(String => $data, Binmode => 1, Telnetmode => 0);
	}
    
	$data = $ts->get( Timeout => 0 );
	if (defined $data and length($data)) {
	    $pty->write($data);
	}
    }
    $pty->close;

    tmwng_log("Sending files OK");
}

sub tmwng_recv_files
{
    tmwng_log("Receiving files ($cfg->{recvpath})...");

    my $rz_command = sprintf(
	"/usr/bin/rz %s %s",
	$cfg->{verbose} ? "-v" : "-q",
	$cfg->{verbose} ? "2>>/tmp/tmwng_rz.log" : ""
    );

    my $pty = IO::Pty::Easy->new();
    $pty->spawn("cd $cfg->{recvpath}; $rz_command");

    while ($pty->is_active)
    {
	my $data;

	$data = $pty->read(0);
	if (defined $data and length($data)) {
	    $ts->put(String => $data, Binmode => 1, Telnetmode => 0);
	}

	$data = $ts->get( Timeout => 0 );
	if (defined $data and length($data)) {
	    $pty->write($data);
	}
    }

    $pty->close;

    tmwng_log("Receiving files OK");
}

sub tmwng_configure
{
    foreach my $arg (@ARGV) {
	unless ($arg =~ /^--(.*)=(.*)$/) {
	    return tmwng_usage();
	}

	my ($key, $value) = split(/=/, $arg);
	if ($key =~ /^--(host|port|username|password|sendpath|recvpath|timeout|verbose)$/) {
	    $cfg->{$1} = $value; next;
	}

	return tmwng_usage();
    }

    tmwng_log("Configuration");

    $cfg->{sendpath} = Cwd::abs_path($cfg->{sendpath});
    $cfg->{recvpath} = Cwd::abs_path($cfg->{recvpath});

    while (my ($key, $value) = each %$cfg) {
	tmwng_log(" - $key = $value");
    }
}

sub tmwng_usage
{
    printf(STDERR "USAGE:\n");
    printf(STDERR "    $0 [options...]\n");
    printf(STDERR "\n");
    printf(STDERR "OPTIONS:\n");
    printf(STDERR "    --host       = <SRV> (адрес ДИОНИС'а)\n");
    printf(STDERR "    --username   = <USR> (имя пользователя системы)\n");
    printf(STDERR "    --password   = <PSW> (пароль для входа в систему)\n");
    printf(STDERR "    --sendpath   = <DIR> (каталог для отправки, def=%s\n", $cfg->{sendpath});
    printf(STDERR "    --recvpath   = <DIR> (каталог для получения, def=%s\n", $cfg->{recvpath});
    printf(STDERR "    --timeout    = <NUM> (число попыток ожидания маркеров, def=%d\n", $cfg->{timeout});
    printf(STDERR "    --verbose    = <0|1> (вести журнал отправки/получения, def=%s\n", $cfg->{verbose} ? "on" : "off");
    exit(1);
}

################################################################################

tmwng_configure();

$ts = new Net::Telnet (
    Host => $cfg->{host}, Port => $cfg->{port},
    Timeout => 10, Binmode => 1, Telnetmode => 1,
) or die "$!";

$ts->open() or die "$!";

tmwng_log("Connection opened");

tmwng_login();

my $idle_loops = 0;
while ( ($idle_loops < $cfg->{timeout}) and not $ts->eof() ) {

    # ожидаем маркера приёма/передачи для ZModem

    my ($prematch, $match) = $ts->waitfor(
	Match => '/\*\*\x18B0.0/', Timeout => 1
    );

    if (defined $match) {
	if ($match =~ /\*\*\x18B010/) {
	    tmwng_send_files(); next;
	}
	if ($match =~ /\*\*\x18B000/) {
	    tmwng_recv_files(); next;
	}
    }

    $idle_loops++;
}

tmwng_log("Connection %s", $ts->eof() ? "closed" : "timed out");

__END__
