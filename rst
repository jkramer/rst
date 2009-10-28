#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::LL::Simple qw( -f -l -i -g=s -c -e -n -h -G=s );

our $VERSION = '0.01';
our ($include, $exclude);

die _help() if($ARGV{'-h'});


my ($query, @target) = @ARGV;

if($ARGV{'-n'}) {
	unshift @target, $query;
	undef $query;
}

# If -g but no query is given, assume -f.
if(($ARGV{'-g'} || $ARGV{'-G'}) && !$query) {
	$ARGV{'-f'} = 1;
}

die "No query.\n" unless $query or $ARGV{'-f'};

# Get list of files to grep/print.
@target = _get_targets(@target);
s{^\./}{} for(@target);

# -f: print files that would have been searched and exit.
if($ARGV{'-f'}) {
	if($ARGV{'-e'}) {
		_edit(grep { -T $_ } @target);
	}
	else {
		print $_, "\n" for(@target);
	}

	exit;
}

my $re = $ARGV{'-i'} ? qr/$query/i : qr/$query/;

if(!$ARGV{'-c'} && !$ARGV{'-l'} && !$ARGV{'-e'}) {
    require IO::Pager;
	$STDOUT = new IO::Pager(*STDOUT);
}

my @match = grep { _search_file($_, $re) } @target;


_edit(@match) if($ARGV{'-e'});


sub _edit {
	my $cmd = $ENV{EDITOR} || $ENV{VISUAL} || 'vi';
	system $cmd, @_;
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

	$include = $ARGV{'-g'}
		? ($ARGV{'-i'} ? qr/$ARGV{'-g'}/i : qr/$ARGV{'-g'}/)
		: undef;

	$exclude = $ARGV{'-G'}
		? ($ARGV{'-i'} ? qr/$ARGV{'-G'}/i : qr/$ARGV{'-G'}/)
		: undef;

	_walk($path, \@result);

	return @result;
}


sub _search_file {
	my ($path, $re) = @_;

	return if -B $path;

	my @match;
	my $lineno = 0;

	if(!open(FILE, '<', $path)) {
        warn "Can't open $path. $!.\n";
        return;
    }

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
	my ($path, $result) = @_;

	return unless -e $path;

	# Handle directories.
	if(-d _) {

        # Skip SCM directories.
		return if $path =~ m{(?:^|/)(?:CVS|\.svn|\.git)(?:/|$)};

		# Recurse into directory.
		my $directory;

        opendir($directory, $path);

        for my $entry (readdir($directory)) {
			_walk($path . '/' . $entry, $result) if($entry !~ /^\.{1,2}$/);
		}

        closedir($directory);
	}

	# Handle simple files.
	elsif(-f _) {
		$path =~ s{/+}{/}g;

		# Ignore Vim swap files.
		return if $path =~ m{^(?:\.?/)?\..*\.sw[po]$};

		# Apply include filter.
		return if $include && $path !~ $include;

		# Apply exclude filter.
		return if $exclude && $path =~ $exclude;

        push @{$result}, $path;
	}
}


sub _help {
	return <<HELP;
Usage: $0 [-f|-l] [-g regexp] [-i] [-c] [-e] [-n] [regexp] [paths]

Options:
  -f         print a list of files that would have been searched
  -l         print only the names of matching files, not the matching lines
  -g regexp  filter files applying the regexp on their paths
  -G regexp  same as -g, but exclude matching files
  -i         search case insensitive
  -e         open matching files in \$EDITOR
  -n         no query - use this if want to give paths as parameter but no
             regexp
  -c         compact (grep-like) output, no pager
  -h         print this help and exit
HELP
}
