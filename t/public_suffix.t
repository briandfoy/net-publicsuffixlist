use v5.26;
use utf8;
use Test::More 1;

my $class = 'Net::PublicSuffixList';

my $warnings;
local $SIG{'__WARN__'} = sub { $warnings .= $_[0] };

subtest sanity => sub {
	use_ok( $class ) or BAIL_OUT( "$class did not compile" );
	};

sub new_psl {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	foreach my $rule ( @_ ) {
		$obj->add_suffix( $rule );
		}
	$obj;
	}

sub check_cases {
	my( $obj, @cases ) = @_;
	foreach my $case ( @cases ) {
		my( $host, $want ) = $case->@*;
		is_deeply( $obj->suffixes_in( $host ), $want, "suffixes in <$host>" );
		}
	}

subtest non_wildcard => sub {
	my $obj = new_psl( qw( com uk co.uk cn 公司.cn ) );

	check_cases( $obj,
		[ 'example.com'        => [ 'com' ]                 ],
		[ 'www.example.co.uk'  => [ 'uk', 'co.uk' ]         ],
		[ 'example.CO.UK'      => [ 'uk', 'co.uk' ]         ],
		[ 'shop.公司.cn'       => [ 'cn', '公司.cn' ]       ],
		[ 'shop.xn--55qx5d.cn' => [ 'cn', 'xn--55qx5d.cn' ] ],
		[ 'example.org'        => [ ]                       ],
		);
	};

subtest wildcard => sub {
	my $obj = new_psl( qw( com cn *.ck *.公司.cn ) );

	check_cases( $obj,
		[ 'example.com'             => [ 'com' ]                           ],
		[ 'ck'                      => [ ]                                 ],
		[ 'foo.ck'                  => [ 'foo.ck' ]                        ],
		[ 'a.b.ck'                  => [ 'b.ck' ]                          ],
		[ '公司.cn'                 => [ 'cn' ]                            ],
		[ 'www.shop.公司.cn'        => [ 'cn', 'shop.公司.cn' ]            ],
		[ 'www.shop.xn--55qx5d.cn'  => [ 'cn', 'shop.xn--55qx5d.cn' ]      ],
		);
	};

done_testing();
