package Net::PublicSuffixList;
use v5.26;
use strict;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use warnings;
no warnings;

use Carp                  qw(carp);
use File::Basename        qw(dirname);
use File::Path            qw(make_path);
use File::Spec::Functions qw(catfile);

our $VERSION = '0.001_01';

=encoding utf8

=head1 NAME

Net::PublicSuffixList - The Mozilla Public Suffix List

=head1 SYNOPSIS

	use Net::PublicSuffixList;

=head1 DESCRIPTION

=over 4

=item new

Possible keys:

	list_url    # the URL for the suffix list
	local_path  # the path to a local file that has the suffix list
	no_net      # do not use the network
	no_local    # do not use a local file
	cache_dir   # location to save the fetched file

=cut

sub new ( $class, %args ) {
	my $self = bless {}, $class;
	$self->init( \%args );
	}

=item init

=cut

sub init ( $self, $args ) {
	my %args = $self->defaults->%*, $args->%*;

	while( my($k, $v) = each %args ) {
		$self->{$k} = $v;
		}

	my $method = do {
		if( ! $self->{no_local} and -e $self->local_path ) {
			'fetch_list_from_local'
			}
		elsif( ! $self->{no_net} ) {
			'fetch_list_from_net'
			}
		else {
			carp "No way to fetch list! Check your settings for no_local or no_net";
			}
		};

	my $ref = $self->$method();

	$self->parse_list( $ref );

	$self;
	}

=item * defaults


=cut

sub defaults ( $self ) {
	state $hash = {
		list_url   => $self->default_url,
		local_path => $self->default_local_path,
		no_net     => 0,
		no_local   => 0,
		cache_dir  => catfile( $ENV{HOME}, '.publicsuffixlist' ),
		};
	$hash;
	}

=item * parse_list( STRING_REF )

Take a scalar reference to the contents of the public suffix list,
find all the suffices and add them to the object.

=cut

sub parse_list ( $self, $list ) {
	unless( ref $list eq 'SCALAR' ) {
		carp "Argument is not a scalar reference";
		return;
		}
	open my $string_fh, '<:utf8', $list;
	while( <$string_fh> ) {
		chomp;
		next if( /\A\s*\z/ || m|\A\s*//| );
		s/\A\Q*.//;
		$self->add_suffix( $_ );
		}
	$self;
	}

=item * add_suffix( STRING )

Add STRING to the known public suffices. This returns the object itself.

=cut

sub add_suffix ( $self, $suffix ) { $self->{suffix}{$suffix}++; $self }

=item * remove_suffix( STRING )

Remove the STRING as a known public suffices. This returns the object
itself.

=cut

sub remove_suffix ( $self, $suffix ) { delete $self->{suffix}{$suffix}; $self }

=item * suffix_exists( STRING )

Return true if STRING is a known public suffix.

=cut

sub suffix_exists ( $self, $suffix ) { exists $self->{suffix}{$suffix} }

=item * suffixes_in_host( HOST )

Return an array reference of the publix suffixes in HOST, sorted from
shortest to longest.

=cut

sub suffixes_in_host ( $self, $host ) {
	my @parts = reverse split /\./, $host;
	my @suffixes =
		map  { $_->[0] }
		grep { $_->[1] }
		map  { [ $_, $self->suffix_exists( $_ ) ] }
    	map  { join '.', reverse @parts[0..$_] }
    	0 .. $#parts;

	\@suffixes;
	}

=item * longest_suffix_in_host( HOST )

Return the longest public suffix in HOST.

=cut

sub longest_suffix_in_host ( $self, $host ) {
	$self->suffixes_in_host( $host )->@[-1];
	}

=item * split_host( HOST )

Returns a hash reference with these keys:

	host    the input value
	suffix  the longest public suffix
    short   the input value with the public suffix
              (and leading dot) removed

=cut

sub split_host ( $self, $host ) {
	my $suffix = $self->longest_suffix_in_host( $host );
	my $short  = $host =~ s/\Q.$suffix\E\z//r;

	return	{
		host   => $host,
		suffix => $suffix,
		short  => $short
		}
	}

=item * fetch_list_from_net

Fetch the public suffix list plaintext file from the path returned
by C<local_path>. Returns a scalar reference to the text of the raw
UTF-8 octets.

=cut

sub fetch_list_from_local ( $self ) {
	return if $self->{no_local};
	open my $fh, '<:raw', $self->local_path;
	my $data = do { local $/; <$fh> };
	$self->{source} = 'local_file';
	\$data;
	}

=item * fetch_list_from_net

Fetch the public suffix list plaintext file from the URL returned
by C<url>. Returns a scalar reference to the text of the raw
UTF-8 octets.

=cut

sub fetch_list_from_net ( $self ) {
	return if $self->{no_net};
	state $rc = require Mojo::UserAgent;
	state $ua = Mojo::UserAgent->new;

	my $path = catfile( $self->{cache_dir}, $self->default_local_file );
	my $local_last_modified = (stat $path)[9];
	my $headers = {};

	if( $self->{cache_dir} ) {
		make_path $self->{cache_dir};
		if( $local_last_modified ) {
			$headers->{'If-Modified-Since'} = Mojo::Date->new($local_last_modified);
			}
		}

	my $tx = $ua->get( $self->url() => $headers );

	my $body;
	if( $tx->result->code eq '304' ) {
		open my $fh, '<:raw', $path;
		$body = do { local $/; <$fh> };
		close $fh;
		$self->{source} = 'net_cached';
		}
	elsif( $tx->result->code eq '200' ) {
		$body = eval { $tx->result->body };

		my $date = Mojo::Date->new(
			$tx->result->headers->last_modified,
			$tx->result->headers->date,
			0
			);

		if( $self->{cache_dir} ) {
			open my $fh, '>:raw', $path;
			print { $fh } $body;
			close $fh;
			utime $date->epoch, $date->epoch, $path;
			}

		$self->{source} = 'net';
		}

	return \$body;
	}

=item * url

Return the configured URL for the public suffix list.

=cut

sub url ( $self ) {
	$self->{list_url} // $self->default_url
	}

=item * default_url

Return the default URL for the public suffix list.

=cut

sub default_url ( $self ) {
	'https://publicsuffix.org/list/public_suffix_list.dat'
	}

=item * local_path

Return the configured local path for the public suffix list.

=cut

sub local_path ( $self ) {
	$self->{local_path} // $self->default_local_path
	}

=item * default_local_path

Return the default local path for the public suffix list.

=cut

sub default_local_path ( $self ) {
	my $this_file = __FILE__;
	my $this_dir  = dirname( $this_file );
	my $file = catfile( $this_dir, $self->default_local_file );
	}

=item * local_file

Return the configured filename for the public suffix list.

=cut

sub local_file ( $self ) {
	$self->{local_file} // $self->default_local_file
	}

=item * default_local_file

Return the default filename for the public suffix list.

=cut

sub default_local_file ( $self ) {
	'public_suffix_list.dat'
	}

=item * TO_JSON

This hook method allows JSON modules to turn the suffix list into
JSON.

=cut

sub TO_JSON ( $self ) {
	$self->{suffix}
	}

=back

=head1 TO DO


=head1 SEE ALSO

L<Domain::PublicSuffix>, L<Mozilla::PublicSuffix>, L<IO::Socket::SSL::PublicSuffix>

=head1 SOURCE AVAILABILITY

This source is in Github:

	http://github.com/briandfoy/net-publicsuffixlist

=head1 AUTHOR

brian d foy, C<< <bdfoy@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2020, brian d foy, All Rights Reserved.

You may redistribute this under the terms of the Artistic License 2.0.

=cut

1;
