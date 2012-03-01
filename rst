#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw(:config gnu_getopt);

our $VERSION = '0.01';
our ($include, $exclude, $ignore, $filetype);


my %O;

GetOptions(\%O, qw(f l i e n c h t=s g=s G=s q)) or exit(-1);

die _help() if($O{h});


my ($query, @target) = @ARGV;

if($O{n}) {
	unshift @target, $query;
	undef $query;
}

# If -g but no query is given, assume -f.
if(($O{g} || $O{G}) && !$query) {
	$O{f} = 1;
}

die "No query.\n" unless $query or $O{f};

die "Unknown file type '$O{t}'.\n" if($O{t} && !_file_type($O{t}));

# Get list of files to grep/print.
@target = _get_targets(@target);
s{^\./}{} for(@target);

# -f: print files that would have been searched and exit.
if($O{f}) {
	if($O{e}) {
		_edit(grep { -T $_ } @target);
	}
	else {
		print $_, "\n" for(@target);
	}

	exit;
}

$query = quotemeta($query) if($O{q});
my $re = $O{i} ? qr/$query/i : qr/$query/;

if(!$O{c} && !$O{l} && !$O{e}) {
    require IO::Pager;
	$STDOUT = new IO::Pager(*STDOUT);
}

my @match = grep { _search_file($_, $re) } @target;


_edit(@match) if($O{e});

exit(int(@match) ? 0 : -1);


sub _edit {
	my $cmd = $ENV{EDITOR} || $ENV{VISUAL} || 'vi';
	system $cmd, @_ if(@_);
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

	$include = $O{g}
		? ($O{i} ? qr/$O{g}/i : qr/$O{g}/)
		: undef;

	$exclude = $O{G}
		? ($O{i} ? qr/$O{G}/i : qr/$O{G}/)
		: undef;

    if(exists $ENV{RST_IGNORE}) {
        $ignore = qr/$ENV{RST_IGNORE}/;
    }

    $filetype = $O{t} ? _file_type($O{t}) : undef;

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

	if(@match && !$O{e}) {
		if($O{l}) {
			print "$path\n";
		}
		elsif($O{c}) {
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

    my $target = $file;

    my @path;

    while(-l $target) {
        push @path, ($target = readlink($target));
    }

    if(@path) {
        $file .= join('', map { " -> $_" } @path);
    }

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

		# Skip CVS files (like this: ./perl/.#foobar.pl.1.229).
		return if $path =~ m{(?:^|/)\.\#[^/]*(?:\.\d+)+$};

        # Apply filetype filter.
        return if $filetype && $path !~ $filetype;

		# Apply include filter.
		return if $include && $path !~ $include;

		# Apply exclude filter.
		return if $exclude && $path =~ $exclude;

        # Apply ignore filter.
        return if $ignore && $path =~ $ignore;

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
  -t type    file type filter (currently known: perl, c, haskell, shell)
  -q         search for literal string instead of a regular expression
  -i         search case insensitive
  -e         open matching files in \$EDITOR
  -n         no query - use this if want to give paths as parameter but no
             regexp
  -c         compact (grep-like) output, no pager
  -h         print this help and exit
HELP
}


sub _file_type {
    my ($type) = @_;

    my $regex = {
        perl    => qr/\.(?:p[lm]|t)$/,
        c       => qr/\.[ch]$/,
        haskell => qr/\.l?hs$/,
        shell   => qr/\.[cz]?sh$/,
    };

    return $regex->{$type};
}
