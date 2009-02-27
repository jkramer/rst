#!/usr/bin/env perl

use strict;
use warnings;

use IO::File;
use IO::Pager;
use Getopt::LL::Simple qw( -f -l -i -g=s -c );

our $VERSION = '0.01';

my ($query, @target) = @ARGV;

# If -g but no query is given, assume -f.
if($ARGV{'-g'} && !$query) {
	$ARGV{'-f'} = 1;
}

die "No query.\n" unless $query or $ARGV{'-f'};

# Get list of files to grep/print.
@target = _get_targets(@target);
s{^\./}{} for(@target);

# -f: print files that would have been searched and exit.
if($ARGV{'-f'}) {
	$, = $\ = "\n";
	print @target;
	exit;
}

my $re = $ARGV{'-i'} ? qr/$query/io : qr/$query/o;

if(!$ARGV{'-c'} && !$ARGV{'-l'}) {
	$STDOUT = new IO::Pager(*STDOUT);
}

_search_file($_, $re) for(@target);


sub _get_targets {
	my (@target) = @_;

	my @expanded;

	push @target, '.' unless @target;
	push @expanded, -d $_ ? _find($_) : $_ for(@target);

	return @expanded;
}


sub _find {
	my ($path) = @_;

	if(!open(FIND, "find $path -print0 2>/dev/null |")) {
		die "Can't run find. $!.\n";
	}

	local $/ = "\x0";

	my @result;
	my $re;

	$re = qr/$ARGV{'-g'}/o if($ARGV{'-g'});

	while(<FIND>) {
		chomp;
		next if -d $_;

		next if _scm_directory($_);
		next if _swap_file($_);
		next if _binary($_);

		next if $re and $_ !~ $re;

		push @result, $_;
	}

	return @result;
}


sub _search_file {
	my ($path, $re) = @_;

	my $io = new IO::File($path, '<');

	my @match;
	my $lineno = 0;

	open(FILE, '<', $path);

	for my $line (<FILE>) {
		++$lineno;
		chomp $line;

		push @match, [ $lineno, $line ] if($line =~ /$re/o);
	}

	close(FILE);

	if(@match) {
		if($ARGV{'-l'}) {
			print "$path\n";
		}
		elsif($ARGV{'-c'}) {
			for my $match (@match) {
				print "$path:$match->[0]:$match->[1]\n";
			}
		}
		else {
			print _color_file($path), "\n";

			for my $match (@match) {
				my ($lineno, $line) = @$match;
				printf("%5d: %s\n", $lineno, _color_match($line, $re));
			}

			print "\n";
		}
	}
}


sub _color_file {
	my ($file) = @_;

	my $code = $ENV{RST_COLOR_FILENAME};

	if($code) {
		$file = "\x1B[${code}m${file}\x1B[0m";
	}

	return $file;
}


sub _color_match {
	my ($line, $re) = @_;

	my $code = $ENV{RST_COLOR_MATCH};

	if($code) {
		$line =~ s/($re)/\x1B[${code}m$1\x1B[0m/go;
	}

	return $line;
}


# Ignore common SCM directories.
sub _scm_directory { $_[0] =~ m{(?:^|/)(?:CVS|\.svn|\.git)(?:/|$)} }

# Ignore Vim swap files.
sub _swap_file { $_[0] =~ m{^(?:\.?/)?\..*\.sw[po]$} }

# Ignore binaries.
sub _binary {
	$_[0] =~ m{\.(?:o|so|a)$}
}
