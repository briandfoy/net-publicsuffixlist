use v5.26;
use utf8;
use Test::More 1;

my $class = 'Net::PublicSuffixList';

my $warnings;
local $SIG{'__WARN__'} = sub { $warnings .= $_[0] };

subtest sanity => sub {
	use_ok( $class ) or BAIL_OUT( "$class did not compile" );
	};

my $obj = $class->new( no_net => 1, no_local => 1 );

my @cases = (
	{ name => 'plain ASCII',           in => 'com',               want => ['com'] },
	{ name => 'uppercase lowered',     in => 'COM',               want => ['com'] },
	{ name => 'ASCII wildcard',        in => '*.ck',              want => ['*.ck'] },
	{ name => 'Unicode suffix',        in => '公司.cn',           want => ['xn--55qx5d.cn', '公司.cn'] },
	{ name => 'punycode suffix',       in => 'xn--55qx5d.cn',     want => ['xn--55qx5d.cn', '公司.cn'] },
	{ name => 'wildcard + Unicode',    in => '*.公司.cn',         want => ['*.xn--55qx5d.cn', '*.公司.cn'] },
	{ name => 'wildcard + punycode',   in => '*.xn--55qx5d.cn',   want => ['*.xn--55qx5d.cn', '*.公司.cn'] },
	);

foreach my $case ( @cases ) {
	subtest $case->{name} => sub {
		my @got = sort $obj->_forms( $case->{in} );
		my @want = sort @{ $case->{want} };
		is_deeply( \@got, \@want, "forms for <$case->{in}>" );
		};
	}

subtest 'invalid input is rejected' => sub {
	foreach my $bad ( '', '*', '*foo', '*.*.com' ) {
		$warnings = '';
		my @got = $obj->_forms( $bad );
		is_deeply( \@got, [], "rejected: <$bad>" );
		like( $warnings, qr/invalid/i, "warned on <$bad>" );
		}
	};

done_testing();
