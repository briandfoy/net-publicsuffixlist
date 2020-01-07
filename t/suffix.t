use v5.26;
use Test::More 1;
use Mojo::Util qw(dumper);

my $class = 'Net::PublicSuffixList';


subtest sanity => sub {
	use_ok( $class ) or BAILOUT( "$class did not compile" );
	can_ok( $class, 'new' );
	};

subtest new => sub {
	isa_ok( $class->new, $class );
	};

diag( "# you'll see a warnings about 'no way to fetch' for this test. That's fine." );

subtest bare => sub {
	my $obj = $class->new( no_local => 1, no_net => 1 );
	isa_ok( $obj, $class );
	ok( $obj->{no_local}, "no_local is true" );
	ok( $obj->{no_net}, "no_net is true" );
	};

subtest add_suffix => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	my $suffix = 'co.uk';
	isa_ok( $class->new, $class );
	can_ok( $class, 'suffix_exists', 'add_suffix' );

	ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );

	my $result = $obj->add_suffix( $suffix );
	isa_ok( $result, $class, 'add_suffix returns the object' );

	ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );
	};

subtest add_suffix_strip => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	my $suffix = 'co.uk';
	isa_ok( $class->new, $class );
	can_ok( $class, 'suffix_exists', 'add_suffix' );

	my @suffixes = (
		[ qw( *.com    com   ) ],
		[ qw( *net     net   ) ],
		[ qw( *.co.uk  co.uk ) ],
		);
	foreach my $pair ( @suffixes ) {
		foreach my $suffix ( $pair->@* ) {
			ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
			}
		}

	foreach my $pair ( @suffixes ) {
		my $result = $obj->add_suffix( $pair->[0] );
		isa_ok( $result, $class, 'add_suffix returns the object'  );
		ok(   $obj->suffix_exists( $pair->[1] ), "Suffix <$pair->[1]> now exists for <$pair->[0]>" );
		ok( ! $obj->suffix_exists( $pair->[0] ), "Suffix <$pair->[0]> does not exist" );
		}

	my $result = $obj->add_suffix( $suffix );
	isa_ok( $result, $class, 'add_suffix returns the object' );

	ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );
	};

subtest remove_suffix => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	my $suffix = 'au';
	isa_ok( $class->new, $class );
	can_ok( $class, 'suffix_exists', 'add_suffix', 'remove_suffix' );

	ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );

	my $result = $obj->add_suffix( $suffix );
	isa_ok( $result, $class, 'add_suffix returns the object' );

	ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> now exists" );

	$result = $obj->remove_suffix( $suffix );
	isa_ok( $result, $class, 'remove_suffix returns the object' );

	};

subtest parse_list => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	can_ok( $class, 'parse_list' );

	my @suffixes = qw( co.uk foo.bar com );
	foreach my $suffix ( @suffixes ) {
		ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
		}

	my $body = join "\n", @suffixes;

	my $result = $obj->parse_list( \$body );
	isa_ok( $result, $class );

	foreach my $suffix ( @suffixes ) {
		ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
		}
	};

subtest parse_list => sub {
	my $obj = $class->new( no_net => 1, no_local => 1 );
	can_ok( $class, 'parse_list' );

	my @suffixes = qw( co.uk foo.bar com );
	foreach my $suffix ( @suffixes ) {
		ok( ! $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
		}

	my $body = join "\n", @suffixes;

	my $result = $obj->parse_list( \$body );
	isa_ok( $result, $class );

	foreach my $suffix ( @suffixes ) {
		ok( $obj->suffix_exists( $suffix ), "Suffix <$suffix> does not exist yet" );
		}
	};


diag( "# You shouldn't see any more 'no way to fetch' warnings." );


done_testing();
