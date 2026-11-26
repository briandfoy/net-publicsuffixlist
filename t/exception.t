use v5.26;
use Test::More 1;

my $class = 'Net::PublicSuffixList';

my $warnings;
local $SIG{'__WARN__'} = sub { $warnings .= $_[0] };

subtest sanity => sub {
	use_ok( $class ) or BAIL_OUT( "$class did not compile" );
	};

subtest exception => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );

	$warnings = undef;
	my $list = "*.ck\n!www.ck\n";
	$obj->parse_list( \$list );
	unlike( $warnings // '', qr/invalid/i, 'exception rule is accepted' );

	my @cases = (
		[ 'foo.ck'     => 'foo.ck' ],
		[ 'www.ck'     => 'ck'     ],
		[ 'foo.www.ck' => 'ck'     ],
		);

	foreach my $case ( @cases ) {
		my( $host, $want ) = $case->@*;
		is( $obj->longest_suffix_in( $host ), $want, "suffix for <$host>" );
		}
	};

subtest exception_wildcard_rejected => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );

	$warnings = undef;
	$obj->add_suffix( '!*.com' );
	like( $warnings, qr/invalid/i, 'got invalid warning for <!*.com>' );

	ok( ! $obj->suffix_exists( 'com' ),    '<com> is not stored' );
	ok( ! $obj->suffix_exists( '*.com' ),  '<*.com> is not stored' );
	is_deeply( $obj->suffixes_in( 'example.com' ), [], 'no suffix for <example.com>' );
	};

done_testing();
