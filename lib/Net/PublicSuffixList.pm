package Net::PublicSuffixList;
use v5.26;
use strict;
use experimental qw(signatures);

use warnings;
no warnings;

use Carp                  qw(carp);
use File::Basename        qw(basename dirname);
use File::Path            qw(make_path);
use File::Spec::Functions qw(catfile);
use Net::IDN::Encode      qw(domain_to_ascii domain_to_unicode);

our $VERSION = '0.99_02';

=encoding utf8

=head1 NAME

Net::PublicSuffixList - The Mozilla Public Suffix List

=head1 SYNOPSIS

	use Net::PublicSuffixList;

	my $psl = Net::PublicSuffixList->new;

	my $host = 'amazon.co.uk';

	# get all the suffixes in host (like, uk and co.uk)
	my $suffixes = $psl->suffixes_in( $host );

	# get the longest suffix
	my $suffix   = $psl->longest_suffix_in( $host );

	my $hash     = $psl->split_host( $host );

=head1 DESCRIPTION

I mostly wrote this because I was working on L<App::url> and needed a
way to figure out which part of a URL was the registered part and which
was the top-level domain.

The Public Suffix List is essentially a self-reported collection of the
top-level, generic, country code, or whatever domains.

There are other modules that try to do this, but they come with packaged
(old) versions of the Public Suffix List or have limited functionality.

This module can fetch the most current one for you, use one that you
provide locally, or even let you completely make it up. You can add
entries you want but don't show up in the list, and remove ones you don't
think should be there.

Hostname and suffix matching is case-insensitive. Internationalized
names are handled transparently: rules and hosts may be passed in
either Unicode or punycode form, and the module stores both forms so
lookups match regardless of spelling.

=over 4

=item new

Create the new object and specify how you'd like to get the data. The
network file is about 220Kb, so you might want to fetch it once, store
it, and then use C<local_path> to use it.

The constructor first tries to use a local file. If you've disabled
that with C<no_local> or the file doesn't exist, it moves on to trying
the network. If you've disabled the network with C<no_net>, then it
complains but still returns the object. You can still construct your
own list with C<add_suffix>.

Possible keys:

	list_url    # the URL for the suffix list
	local_path  # the path to a local file that has the suffix list
	no_net      # do not use the network
	no_local    # do not use a local file
	cache_dir   # location to save the fetched file

=cut

sub new ( $class, %args ) {
	my $self = bless {}, $class;
	$self->_init( \%args );
	}

sub _init ( $self, $args ) {
	my %args = ( $self->defaults->%*, $args->%* );
	$self->{max_depth} = 0;

	while( my($k, $v) = each %args ) {
		$self->{$k} = $v;
		if( $k eq 'local_path' ) {
			$self->{local_file} = basename( $v );
			}
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
			return $self;
			}
		};

	my $ref = $self->$method();

	$self->parse_list( $ref );

	$self;
	}

=item defaults

A hash of the default values for everything.

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

=item parse_list( STRING_REF )

Take a scalar reference to the contents of the public suffix list,
find all the suffices and add them to the object.

=cut

sub parse_list ( $self, $list ) {
	unless( ref $list eq 'SCALAR' ) {
		carp "Argument is not a scalar reference";
		return;
		}

	my( $line_ending ) = $$list =~ m/(\R)/;
	local $/ = $line_ending;

	open my $string_fh, '<:utf8', $list;

	while( <$string_fh> ) {
		chomp;
		next if( /\A\s*\z/ || m|\A\s*//| );
		$self->add_suffix( $_ );
		}
	$self;
	}

=item add_suffix( STRING )

Add STRING to the known public suffices. This returns the object itself.

Before this adds the suffix, it strips off leading C<*> and C<.*>
characters. Some sources specify C<*.foo.bar>, but this adds C<foo.bar>.

The suffix is folded to lowercase before storage, since DNS labels are
case-insensitive.

If the suffix contains non-ASCII characters, its punycode form is also
stored so that hosts arriving in either spelling match the same rule.
If the suffix contains C<xn--> labels, its Unicode form is likewise
stored. Both conversions go through L<Net::IDN::Encode>.

=cut

sub _forms ( $self, $suffix ) {
	$suffix = lc $suffix;
	$suffix =~ s/\A\.//;
	my $has_wildcard = $suffix =~ s/\A\*\.//; # only one level

	my $ascii;
	unless( $ascii = eval { domain_to_ascii( $suffix ) } ) {
		carp "The suffix <$suffix> is invalid";
		return;
		}

	unless( $ascii =~ /\A[a-z0-9-]+(?:\.[a-z0-9-]+)*\z/ ) {
		carp "The suffix <$suffix> is invalid";
		return;
		}

	my @forms = ( $suffix );
	push @forms, $ascii if $ascii ne $suffix;

	if( $suffix =~ /(?:\A|\.)xn--/ ) {
		my $unicode = eval { domain_to_unicode( $suffix ) };
		push @forms, $unicode if defined $unicode && $unicode ne $suffix;
		}

	@forms = map { "*.$_" } @forms if $has_wildcard;

	@forms;
	}

sub add_suffix ( $self, $suffix ) {
	my @forms = $self->_forms( $suffix );
	unless( @forms ) {
		carp "Invalid suffix <$suffix>";
		return $self;
		}

	foreach my $form ( @forms ) {
		$self->{suffix}{$form}++;
		my $depth = ( $form =~ tr/.// ) + 1;
		$self->{max_depth} = $depth if $depth > $self->{max_depth};
		}

	$self
	}

=item remove_suffix( STRING )

Remove STRING as a known public suffix. This returns the object itself.

STRING is normalised the same way as in L</add_suffix>: leading C<*>
and C<.> characters are stripped and the result is folded to
lowercase. If STRING has a punycode or Unicode counterpart, that form
is removed too, so a rule stored by either spelling can be removed by
passing either one.

=cut

sub remove_suffix ( $self, $suffix ) {
	foreach my $form ( $self->_forms( $suffix ) ) {
		delete $self->{suffix}{$form};
		}
	$self
	}

=item suffix_exists( STRING )

Return the invocant if the suffix exists, and the empty list otherwise.

STRING is normalised the same way as in L</add_suffix>, and its
punycode or Unicode counterpart is also checked. Any match returns the
invocant.

=cut

sub suffix_exists ( $self, $suffix ) {
	foreach my $form ( $self->_forms( $suffix ) ) {
		return $self if exists $self->{suffix}{$form};
		}
	return;
	}

=item suffixes_in( HOST )

Return an array reference of the public suffixes in HOST, sorted from
shortest to longest.

HOST is folded to lowercase before lookup. HOST should be a Perl
character string (not UTF-8 octets); pass Unicode hostnames with
C<\x{...}> escapes or decode with L<Encode/decode_utf8> first.

=cut

sub suffixes_in ( $self, $host ) {
	my @parts = reverse split /\./, lc($host);
	my $cap = $#parts;
	$cap = $self->{max_depth} - 1 if $self->{max_depth} && $self->{max_depth} - 1 < $cap;

	my @suffixes;
	foreach my $i ( 0 .. $cap ) {
		my $candidate = join '.', reverse @parts[0..$i];

		if( $self->suffix_exists( $candidate ) ) {
			push @suffixes, $candidate;
			next;
			}

		next if $i == 0; # a bare TLD has no label for the *

		my $parent = join '.', reverse @parts[0..$i-1];
		push @suffixes, $candidate if $self->suffix_exists( "*.$parent" );
		}

	\@suffixes;
	}

=item longest_suffix_in( HOST )

Return the longest public suffix in HOST.

=cut

sub longest_suffix_in ( $self, $host ) {
	$self->suffixes_in( $host )->@[-1];
	}

=item split_host( HOST )

Returns a hash reference with these keys:

	host    the input value
	suffix  the longest public suffix
    short   the input value with the public suffix
              (and leading dot) removed

HOST may be in Unicode or punycode form. The returned C<suffix> and
C<short> preserve the spelling of HOST: Unicode in yields Unicode
out, punycode in yields punycode out.

=cut

sub split_host ( $self, $host ) {
	my $suffix = $self->longest_suffix_in( $host );
	my $short  = $host =~ s/\Q.$suffix\E\z//ri;

	return	{
		host   => $host,
		suffix => $suffix,
		short  => $short
		}
	}

=item fetch_list_from_local

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

=item fetch_list_from_net

Fetch the public suffix list plaintext file from the URL returned
by C<url>. Returns a scalar reference to the text of the raw
UTF-8 octets.

If you've set C<cache_dir> in the object, this method attempts to
cache the response in that directory using C<default_local_file> as
the filename. This cache is different than C<local_file> although you
can use it as C<local_file>.

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

=item url

Return the configured URL for the public suffix list.

=cut

sub url ( $self ) {
	$self->{list_url} // $self->default_url
	}

=item default_url

Return the default URL for the public suffix list.

=cut

sub default_url ( $self ) {
	'https://publicsuffix.org/list/public_suffix_list.dat'
	}

=item local_path

Return the configured local path for the public suffix list.

=cut

sub local_path ( $self ) {
	$self->{local_path} // $self->default_local_path
	}

=item default_local_path

Return the default local path for the public suffix list.

=cut

sub default_local_path ( $self ) {
	my $this_file = __FILE__;
	my $this_dir  = dirname( $this_file );
	my $file = catfile( $this_dir, $self->default_local_file );
	}

=item local_file

Return the configured filename for the public suffix list.

=cut

sub local_file ( $self ) {
	$self->{local_file} // $self->default_local_file
	}

=item default_local_file

Return the default filename for the public suffix list.

=cut

sub default_local_file ( $self ) {
	'public_suffix_list.dat'
	}

=back

=head1 TO DO


=head1 SEE ALSO

L<Domain::PublicSuffix>, L<Mozilla::PublicSuffix>, L<IO::Socket::SSL::PublicSuffix>

L<https://publicsuffix.org/list/public_suffix_list.dat>

=head1 SOURCE AVAILABILITY

This source is in Github:

	https://github.com/briandfoy/net-publicsuffixlist

=head1 AUTHOR

brian d foy, C<< <briandfoy@pobox.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2020-2026, brian d foy, All Rights Reserved.

You may redistribute this under the terms of the Artistic License 2.0.

The public suffix list is Mozilla Public License 2.0

=cut

1;
