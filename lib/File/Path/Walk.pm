
package File::Path::Walk;

use strict;
use warnings;

use IO::Dir;

sub new {
	my ($class, %callbacks) = @_;

	my $self = bless \%callbacks, $class;

	$self->{list} = {};

	return $self;
}

sub walk {
	my ($self, $path) = @_;

	return $self->_walk($self->{basepath} = $path);
}

sub diff {
	my ($self, $path) = @_;

	my %oldlist = %{$self->{list}};
	my $oldpath = $self->{basepath};

	$self->_walk($path);

	my %newlist = %{$self->{list}};
	my $newpath = $path;

	s{^$oldpath/*}{} for(keys %oldlist);
	s{^$newpath/*}{} for(keys %newlist);

	my $diff = { added => [], removed => [] };

	for my $key (keys %newlist) {
		push @{$diff->{added}}, $key unless $oldlist{$key};
	}

	for my $key (keys %oldlist) {
		push @{$diff->{removed}}, $key unless $newlist{$key};
	}

	return $diff;
}

sub _walk {
	my ($self, $path) = @_;

	$path =~ s{/*$}{} if(length $path >= 2);

	# Entry should exist, don't handle entries twice.
	return if ! -e $path or $self->{list}->{$path}++;

	# Skip if filter callback is set and doesn't return true.
	return if $self->{filter} and !&{$self->{filter}}($path);

	# "entry" callback is for all entries.
	&{$self->{entry}}($path) if(ref $self->{entry});

	# Handle symbolic links.
	if(-l $path) {
		&{$self->{link}}($path) if(ref $self->{link});
		return $self->walk(readlink $path);
	}

	# Handle directories.
	if(-d $path) {
		&{$self->{directory}}($path) if(ref $self->{directory});

		my $directory = new IO::Dir($path);
		return unless defined $directory;

		while(defined(my $entry = $directory->read)) {
			next if($entry eq '.' or $entry eq '..');

			my $path = $path . '/' . $entry;

			$self->walk($path);
		}

		$directory->close;
	}

	# Handle simple files.
	else {
		&{$self->{file}}($path) if(ref $self->{file});
	}
}

sub list {
	my ($self) = @_;

	my @list = keys %{$self->{list}};
	%{$self->{list}} = ();

	return @list;
}

1

__END__

=head1 NAME

File::Path::Walk - Directory walker module.

=head1 SYNOPSIS

	my $walk = new File::Path::Walk(entry => sub { print $_[0], "\n" });

	$walk->walk($ENV{HOME});

	print "Total: ", scalar($walk->list), "\n";

=head1 DESCRIPTION

This is another directoy walker module. It's similar to L<File::DirWalk>, but
doesn't support as many callbacks and is quite a bit faster:

	Rate                       File::DirWalk File::Path::Walk
	File::DirWalk    1.21/s               --             -96%
	File::Path::Walk 33.9/s            2705%               --

If you need B<really> fast directory walking (and don't mind about ugly module
interfaces) use F<File::Find> instead.

=head1 METHODS

=over 4

=item B<new>( CALLBACKS )

The constructor takes a hash with callbacks you want to use, each of which will
be called with the path of the current directory entry as argument. The
supported callbacks are "entry" (called for all entries), "link" (symbolic
links), "directory" (directories), "file" (normal files).

=item B<walk>( PATH )

Starts the directory walking. Beside calling the given callbacks, there's also
an internal list of found entries. This list is kept between subsequent calls
to B<walk>, unless it's reset by calling the B<list> method (see below). The
callbacks will be called only once for every entry. This means that if you call
B<walk> multiple times without resetting the internal list, the callbacks will
only be called for files that are new in the given directory.

=item B<list>

Resets the internal list of found entries and returns its contents.

=cut
