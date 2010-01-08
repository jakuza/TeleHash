#!/usr/bin/perl

use Digest::SHA1 qw(sha1_hex);
use Socket;
use JSON::DWIW;
my $json = JSON::DWIW->new;

# create our local UDP listener port
my $iaddr = gethostbyname("0.0.0.0");
my $proto = getprotobyname('udp');
my $paddr = sockaddr_in(0, $iaddr); # pick local port at random
socket(SOCKET, PF_INET, SOCK_DGRAM, $proto)	or die "socket: $!";
bind(SOCKET, $paddr)						or die "bind: $!";

# send a hello to our seed
my $seed = $ARGV[0]||"telehash.org:42424";
my($ip,$port) = split(":",$seed);
my $sip = gethostbyname($ip);
my $saddr = sockaddr_in($port,$sip);
defined(send(SOCKET, "{}", 0, $saddr))		or die "hello failed to $seed: $!";

# get the first response and validate
my $buff;
my $caddr = recv(SOCKET, $buff, 8192, 0);
my($cport, $addr) = sockaddr_in($caddr);
my $sender = sprintf("%s:%d",inet_ntoa($addr),$cport);
my $j = $json->from_json($buff)				or die("json parse failed: $buff");
defined($j->{"_cb"} eq $sender)				or die("seed source $sender disagrees with it's callback ".$j->{"_cb"});
defined($j->{".cb"})						or die("first response was missing a callback command");

my $cb = $j->{".cb"};
printf "%s told us we are %s\n",$j->{"_cb"},$cb;

# quite temporary
require "./bixor.pl";
printf "our distance from the seed is %d\n",bix_sbit(bix_or(bix_new(sha1_hex($j->{"_cb"})),bix_new(sha1_hex($cb))));

# send a test .to
defined(send(SOCKET, sprintf("{'_cb':'%s','.to':'%s'}",$j->{".cb"},sha1_hex($j->{".cb"})), 0, $saddr))		or die ".to failed to $seed: $!";
recv(SOCKET, $buff, 8192, 0);
printf ".to test returned %s\n",$buff;
my $j = $json->from_json($buff)				or die("json parse failed: $buff");

# loop through all and say hello
for my $sipp (@{$j->{".see"}})
{
	next if($sipp eq $cb); # skip ourselves :)
	my($ip,$port) = split(":",$sipp);
	my $wip = gethostbyname($ip);
	my $waddr = sockaddr_in($port,$wip);
	my $jo = { "_cb"=>$cb, "hello"=>"world" }; 
	# send direct (should open our outgoing to them)
	defined(send(SOCKET, $json->to_json($jo), 0, $waddr))    or die "hello $sipp: $!";
	# send natr via seed in case they're behind a nat
	my $jo = { "_cb"=>$cb, ".natr"=>$sipp }; 
	defined(send(SOCKET, $json->to_json($jo), 0, $saddr))    or die ".natr $seed $!";
}

# now process any incoming msgs
while(my $waddr = recv(SOCKET, $buff, 8192, 0))
{
	printf "incoming: %s\n",$buff;
	next unless my $j = $json->from_json($buff);
	if($j->{".nat"})
	{
		my($ip,$port) = split(":",$j->{".nat"});
		my $nip = gethostbyname($ip);
		my $naddr = sockaddr_in($port,$nip);
		my $jo = { "_cb"=>$cb, "nat"=>"backatcha" }; 
    	defined(send(SOCKET, $json->to_json($jo), 0, $naddr))    or die "nat $ip:$port $!";
		next;
	}
}
