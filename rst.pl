#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib/'; ## DEVELOPMENT

use CLI::Application;
use File::Path::Walk;
use IO::File;

our $VERSION = '0.01';

my $application = new CLI::Application(
	name => 'rst',
	version => $VERSION,
	options => [
		[ [ qw( a all ) ], 'include all files in search', 0 ],
		[ [ qw( f file-list ) ], 'only print names of files found', 0 ],
		[ [ qw( l list-result ) ], 'list files that match', 0 ],
		[ [ qw( i ignore-case) ], 'ignore case', 0 ],
		[ [ qw( g file-filter ) ], 'only search files matching this expression', 1 ],
	],
);

$application->prepare(@ARGV);

$application->dispatch('search');

sub search : Command : Fallback {
	my ($application) = @_;

	my ($query, @target) = $application->arguments;

	if($application->option('file-filter') && !$query) {
		$application->option('file-list' => 1);
	}

	die "No query.\n" unless $query or $application->option('file-list');

	@target = _get_targets($application, @target);
	s{^\./}{} for(@target);

	# -f: print files that would have been searched and exit.
	if($application->option('file-list')) {
		$, = $\ = "\n";
		print @target;
		exit;
	}

	my $re = $application->option('ignore-case') ? qr/$query/i : qr/$query/;

	for my $target (@target) {
		_search_file($application, $target, $re);
	}
}

sub _get_targets {
	my ($application, @target) = @_;

	my @expanded;
	my $path = new File::Path::Walk(
		filter => _make_filter($application),
		file => sub { push @expanded, $_[0] },
	);

	# If there were targets given on the command line, expand and use them.
	if(@target) {
		$path->walk($_) for(@target);
	}
	
	# Otherwise, get everything from the current directory and below.
	else {
		$path->walk('.');
	}

	return @expanded;
}


sub _make_filter {
	my ($application) = @_;

	my $re = $application->option('file-filter');
	$re = qr/$re/ if $re;

	return sub {
		my $path = shift;

		return if _scm_directory($path);
		return if _swap_file($path);
		return if _binary($path);

		# Expression for paths (-g).
		return if -f $path and $re and $path !~ /$re/;

		return 1;
	};
}


sub _search_file {
	my ($application, $path, $re) = @_;

	my $io = new IO::File($path, '<');

	my @match;
	my $lineno = 0;

	for my $line ($io->getlines) {
		++$lineno;
		chomp $line;

		if($line =~ $re) {
			push @match, [ $lineno, $line ];
		}
	}

	if(@match) {
		if($application->option('list-result')) {
			print "$path\n";
		}
		else {
			print _color_file($path), "\n";

			for my $match (@match) {
				my ($lineno, $line) = @$match;
				print $lineno, ': ', _color_match($line, $re), "\n";
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
		$line =~ s/($re)/\x1B[${code}m$1\x1B[0m/g;
	}

	return $line;
}


# Ignore common SCM directories.
sub _scm_directory { $_[0] =~ m{^(?:\.?/)?(?:CVS|\.svn|\.git)/?$} }

# Ignore Vim swap files.
sub _swap_file { $_[0] =~ m{^(?:\.?/)?\..*\.sw[po]$} }

# Ignore binaries.
sub _binary {
	$_[0] =~ m{\.(?:o|so|a)$}
}
