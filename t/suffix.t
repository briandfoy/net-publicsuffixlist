use v5.26;
use utf8;
use Test::More 1;
use File::Spec::Functions qw(catfile);
use Mojo::Util            qw(dumper);

my $class = 'Net::PublicSuffixList';

my $warnings;
local $SIG{'__WARN__'} = sub { $warnings .= $_[0] };

subtest sanity => sub {
	use_ok( $class ) or BAIL_OUT( "$class did not compile" );
	can_ok( $class, 'new' );
	};

subtest bare => sub {
	$warnings = undef;

	my $obj = $class->new( no_local => 1, no_net => 1 );
	isa_ok( $obj, $class );
	ok( $obj->{no_local}, "no_local is true" );
	ok( $obj->{no_net}, "no_net is true" );
	like $warnings, qr/No way to fetch/, 'got fetch warning';

	ok( ! defined $obj->fetch_list_from_local, 'fetch_list_from_local returns undef for no_local = 1' );
	ok( ! defined $obj->fetch_list_from_net, 'fetch_list_from_net returns undef for no_net = 1' );
	};

subtest add_suffix => sub {
	$warnings = undef;

	my $obj = $class->new( no_net => 1, no_local => 1 );
	my $suffix = 'co.uk';
	isa_ok( $obj, $class );
	can_ok( $obj, 'suffix_exists', 'add_suffix' );
	like $warnings, qr/No way to fetch/, 'got fetch warning';

	ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );

	my $result = $obj->add_suffix( $suffix );
	isa_ok( $result, $class, 'add_suffix returns the object' );

	ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );

	subtest bad_suffixes => sub {
		foreach my $bad ( '', '*', '*foo', '*.*.com', 'foo bar', 'foo_bar', 'foo..bar' ) {
			$warnings = undef;
			my $result = $obj->add_suffix( $bad );
			isa_ok( $result, $class, "add_suffix returns the object for <$bad>" );
			like $warnings, qr/invalid/i, "got invalid warning for <$bad>";
			ok( ! $obj->suffix_exists( $bad ), "Suffix <$bad> does not exist" );
			}
		};
	};

subtest remove_suffix => sub {
	$warnings = undef;

	my $obj = $class->new( no_net => 1, no_local => 1 );
	my $suffix = 'au';
	isa_ok( $obj, $class );
	can_ok( $obj, 'suffix_exists', 'add_suffix', 'remove_suffix' );
	like $warnings, qr/No way to fetch/, 'got fetch warning';

	ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );

	my $result = $obj->add_suffix( $suffix );
	isa_ok( $result, $class, 'add_suffix returns the object' );

	ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );

	$result = $obj->remove_suffix( $suffix );
	isa_ok( $result, $class, 'remove_suffix returns the object' );
	ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> no longer exists" );

	};

subtest parse_list => sub {
	$warnings = undef;

	my $obj = $class->new( no_net => 1, no_local => 1 );
	can_ok( $obj, 'parse_list' );
	like $warnings, qr/No way to fetch/, 'got fetch warning';

	my @suffixes = qw( co.uk foo.bar com *.net );
	foreach my $suffix ( @suffixes ) {
		ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
		}

	my $body = join "\n", @suffixes;

	my $result = $obj->parse_list( \$body );
	isa_ok( $result, $class );

	foreach my $suffix ( @suffixes ) {
		ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );
		}
	};

subtest local_path => sub {
	my $local_file = 'test.dat';
	my $local_path = catfile( 'corpus', $local_file );
	ok( -e $local_path, "Local file <$local_path> exists" );

	my $obj = $class->new( no_net => 1, local_path => $local_path );
	isa_ok( $obj, $class );
	can_ok( $obj, 'local_path' );

	is( $obj->local_file, $local_file );
	is( $obj->local_path, $local_path );
	is( $obj->{source}, 'local_file' );

	my @good_suffixes = qw( net co.uk email badger koala.au );
	foreach my $suffix ( @good_suffixes ) {
		ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> exists" );
		}

	my @bad_suffixes = qw( com snoopy linus pie );
	foreach my $suffix ( @bad_suffixes ) {
		ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist" );
		}
	};

subtest suffixes => sub {
	my $local_file = 'test.dat';
	my $local_path = catfile( 'corpus', $local_file );
	ok( -e $local_path, "Local file <$local_path> exists" );

	my $obj = $class->new( no_net => 1, local_path => $local_path );
	isa_ok( $obj, $class );
	can_ok( $obj, 'suffixes_in' );

	my $host = 'wildfire.koala.au';

	subtest suffixes_in => sub {
		can_ok( $obj, 'suffixes_in' );
		my $suffixes = $obj->suffixes_in( $host );
		ok( $suffixes->@* == 2, "There are two suffixes in $host" );

		is( $suffixes->@[0], 'au',        'First suffix is right' );
		is( $suffixes->@[1], 'koala.au',  'Second suffix is right' );
		};

	subtest longest_suffix_in => sub {
		can_ok( $obj, 'longest_suffix_in' );
		is( $obj->longest_suffix_in( $host ), 'koala.au' );
		};

	subtest split_host => sub {
		can_ok( $obj, 'split_host' );
		my $result = $obj->split_host( $host );
		isa_ok( $result, ref {}, "split_host returns a hash ref" );
		is( $result->{suffix}, 'koala.au' );
		is( $result->{short}, 'wildfire' );
		is( $result->{host}, $host );
		};

	subtest split_host_idn => sub {
		$obj->add_suffix( '公司.cn' );

		my @cases = (
			[ 'shop.公司.cn',       '公司.cn'       ],
			[ 'shop.xn--55qx5d.cn', 'xn--55qx5d.cn' ],
			);

		foreach my $case ( @cases ) {
			my( $idn_host, $suffix ) = $case->@*;
			my $result = $obj->split_host( $idn_host );
			is( $result->{suffix}, $suffix,   "suffix for <$idn_host>" );
			is( $result->{short},  'shop',    "short for <$idn_host>" );
			is( $result->{host},   $idn_host, "host for <$idn_host>" );
			}
		};

	subtest split_host_no_suffix => sub {
		foreach my $bad_host ( 'shop.公司.jp', 'shop.xn--55qx5d.jp', 'example.org', '' ) {
			my $result = $obj->split_host( $bad_host );
			is( $result->{suffix}, undef,     "no suffix for <$bad_host>" );
			is( $result->{short},  $bad_host, "short is the host for <$bad_host>" );
			is( $result->{host},   $bad_host, "host for <$bad_host>" );
			}
		};
	};

subtest case_insensitive => sub {
	$warnings = undef;

	my $obj = $class->new( no_net => 1, no_local => 1 );
	like $warnings, qr/No way to fetch/, 'got fetch warning';

	my $list = "co.uk\nuk\n";
	$obj->parse_list( \$list );

	for my $host ( qw( sub.example.co.uk sub.example.CO.uk sub.example.CO.UK ) ) {
		my $r = $obj->split_host( $host );
		is( $r->{suffix}, 'co.uk',       "suffix for $host" );
		is( $r->{short},  'sub.example', "short for $host" );
		}
	};

done_testing();
