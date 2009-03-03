#!/usr/bin/env perl

use strict;
use warnings;

use IO::File;
use IO::Pager;
use IO::Dir;
use Getopt::LL::Simple qw( -f -l -i -g=s -c -e );

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

if(!$ARGV{'-c'} && !$ARGV{'-l'} && !$ARGV{'-e'}) {
	$STDOUT = new IO::Pager(*STDOUT);
}

my @match;

for(@target) {
	push @match, $_ if(_search_file($_, $re));
}

if($ARGV{'-e'}) {
	my $cmd = $ENV{EDITOR} || $ENV{VISUAL} || 'vi';
	system $cmd, @match;
}


sub _get_targets {
	my (@target) = @_;

	my @expanded;

	push @target, '.' unless @target;
	push @expanded, -d $_ ? _find($_) : $_ for(@target);

	return @expanded;
}


sub _find {
	my ($path) = @_;

	my @result;

	my $filter = sub { $_[0] !~ m{(?:^|/)(?:CVS|\.svn|\.git)(?:/|$)} };

	my $re;
	if($ARGV{'-g'}) {
		$re = qr/$ARGV{'-g'}/o;
	}

	my $adder = sub {
		my $file = $_[0];

		$file =~ s{/+}{/}g;

		# Ignore Vim swap files.
		return if $path =~ m{^(?:\.?/)?\..*\.sw[po]$};

		return if $re and $file !~ $re;

		push @result, $file;
	};

	_walk($path, $filter, $adder);

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

	if(@match && !$ARGV{'-e'}) {
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

	return ~~ @match;
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


sub _walk {
	my ($path, $filter, $adder) = @_;

	return unless -r $path;

	# Handle directories.
	if(-d _) {
		# Skip if directory filter callback doesn't return true.
		return unless &{$filter}($path);

		my $directory = new IO::Dir($path);

		while(defined(my $entry = $directory->read)) {
			next if $entry =~ /^\.{1,2}$/;

			_walk($path . '/' . $entry, $filter, $adder);
		}

		$directory->close;
	}

	# Handle simple files.
	elsif(-f _) {
		&{$adder}($path);
	}
}
