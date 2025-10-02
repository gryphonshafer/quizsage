use Test2::V0;
use exact -conf;
use Mojo::JSON 'from_json';
use QuizSage::Model::Label;
use QuizSage::Util::Material qw{ text2words material_json synonyms_of_term };

my @spew;
my $mock_mojo_file  = mock 'Mojo::File' => ( override => [ spew => sub { @spew = @_ } ] );
my $mock_file_path  = mock 'File::Path' => ( override => 'make_path' );
my $model_label_obj = QuizSage::Model::Label->new;
my $mock_label      = mock 'QuizSage::Model::Label' => (
    override => [
        new            => sub { $model_label_obj },
        bible_acronyms => sub { [ qw( ESV NASB NIV ) ] },
    ],
);

imported_ok( qw{ text2words material_json } );

like(
    dies { material_json() },
    qr/Must provide label/,
    'Must provide label',
);

like(
    dies { material_json( label => 'NIV' ) },
    qr/Must supply at least 1 valid reference range/,
    'Must supply at least 1 valid reference range',
);

is( material_json( label => 'Eph 6:17 NIV', force => 1 ), {
    label       => 'Ephesians 6:17 NIV',
    description => 'Ephesians 6:17 NIV',
    id          => '35bec86e7f147048',
    json_file   => check_isa('Mojo::File'),
}, 'material_json' );

isa_ok( $spew[0], 'Mojo::File' );

is( from_json( $spew[1] ), hash {
    bibles      => {
        NIV => hash {
            type => 'primary',
        },
    },
    label       => 'Ephesians 6:17 NIV',
    description => 'Ephesians 6:17 NIV',
    ranges      => [{
        range  => 'Ephesians 6:17',
        verses => D(),
    }],
    etc(),
}, 'JSON valid and has expected contents' );

is(
    text2words(
        q{But Jesus looked at them and said, "What then is (the meaning of) this that is written: } .
        q{'The (very) Stone which the builders rejected, this became the chief Cornerstone'?}
    ),
    [ qw(
        but jesus looked at them and said what then is the meaning of this that is written
        the very stone which the builders rejected this became the chief cornerstone
    ) ],
    'text2words',
);

is(
    text2words( q{Jesus asked, "What's (the meaning of) this: 'I and my Father are one.'"} ),
    [ qw( jesus asked what's the meaning of this i and my father are one ) ],
    'text2words again',
);

ok(
    lives { synonyms_of_term('faith') },
    q{synonyms_of_term('faith')},
) or note $@;

done_testing;
