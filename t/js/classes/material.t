use Test2::V0;
use exact -conf;
use Omniframe::Class::Javascript;
use Omniframe::Util::File 'opath';
use Mojo::JSON 'from_json';

my $out = Omniframe::Class::Javascript->new(
    basepath  => conf->get( qw( config_app root_dir ) ) . '/static/js',
    importmap => {
        'classes/material' => 'classes/material',
    },
)->run(
    q{
        import Material from 'classes/material';

        const material = new Material( { material: { data: OCJS.in.material } } );

        material.ready.then( () => {
            OCJS.out( {
                material  : material,
                text2words: material.text2words('Gryphon, Sharalyn, Alexander, and Evangeline love the Bible'),
                next_bible: [
                    material.next_bible(),
                    material.next_bible(),
                    material.next_bible(),
                    material.next_bible(),
                ],
                verses           : material.verses(),
                lookup           : material.lookup( 'NASB', 'James', 1, 2 ),
                search           : material.search( 'joy my' ),
                next_verse       : material.next_verse( 'James', 1, 2 ),
                synonyms_of_verse: material.synonyms_of_verse( 'James', 1, 2, 'NASB' ),
                materials        : material.materials({
                    prompt: 'Consider it all joy, my brothers and...',
                    reply : '...sisters, when you encounter various trials,',
                    ...material.lookup( 'NASB', 'James', 1, 2 )[0],
                }),
            } );
        } );
    },
    {
        material => from_json( opath('t/data/material.json')->slurp('UTF-8') ),
    },
)->[0][0];

is( [ sort $out->{material}{primary_bibles}->@* ], [ qw( BSB ESV ) ], 'primary_bibles' );
is( $out->{material}{bibles}, [
    { name => 'BSB',  type => 'primary'   },
    { name => 'ESV',  type => 'primary'   },
    { name => 'NASB', type => 'auxiliary' },
], 'bibles' );

is( $out->{material}{all_verses}, array {
    all_items hash {
        field bible     => T;
        field book      => T;
        field breaks    => array { all_items T; etc } ;
        field chapter   => T;
        field reference => T;
        field string    => T;
        field text      => T;
        field verse     => T;
        field words     => array { all_items T; etc };
        etc;
    };
    etc;
}, 'all_verses' );

is( $out->{material}{verses_by_bible}, hash {
    all_keys match qr/^[A-Z]+$/;
    all_vals array {
        all_items hash {
            field bible     => T;
            field book      => T;
            field breaks    => array { all_items T; etc } ;
            field chapter   => T;
            field reference => T;
            field string    => T;
            field text      => T;
            field verse     => T;
            field words     => array { all_items T; etc };
            etc;
        };
        etc;
    };
    etc;
}, 'verses_by_bible' );

is( $out->{text2words}[0], [ qw( gryphon sharalyn alexander and evangeline love the bible ) ], 'text2words' );
is( [ sort $out->{next_bible}->@* ], [ qw( BSB BSB ESV ESV ) ], 'next_bible' );
is( $out->{verses}, array {
    all_items hash {
        field bible     => T;
        field book      => T;
        field breaks    => array { all_items T; etc } ;
        field chapter   => T;
        field reference => T;
        field string    => T;
        field text      => T;
        field verse     => T;
        field words     => array { all_items T; etc };
        etc;
    };
    etc;
}, 'verses' );

is( $out->{lookup}, [{
    bible        => 'NASB',
    book         => 'James',
    breaks       => [],
    chapter      => 1,
    reference    => 'James 1:2',
    string       => 'consider it all joy my brothers and sisters when you encounter various trials',
    text         => 'Consider it all joy, my brothers and sisters, when you encounter various trials,',
    verse        => 2,
    words        => [ qw( consider it all joy my brothers and sisters when you encounter various trials ) ],
    book_next    => 'James',
    chapter_next => 1,
    verse_next   => 3,
    string_next  => T,
    text_next    => T,
    string_both  => T,
    text_both    => T,
}], 'lookup' );

my $search = {
    reference    => 'James 1:2',
    book         => 'James',
    chapter      => 1,
    verse        => 2,
    breaks       => [],
    text         => T,
    string       => T,
    words        => array { all_items T; etc },
    book_next    => 'James',
    chapter_next => 1,
    verse_next   => 3,
    string_next  => T,
    text_next    => T,
    string_both  => T,
    text_both    => T,
};
is( $out->{search}, array {
    item hash {
        field bible => $_;
        field $_    => $search->{$_} for ( keys %$search );
    } for ( qw( BSB ESV NASB ) );
}, 'search' );

is( $out->{next_verse}{reference}, 'James 1:3', 'next_verse' );
is( $out->{synonyms_of_verse}[0]{meanings}[0]{synonyms}[0]{words}[2], 'full', 'synonyms_of_word' );
is( [ qw( details materials ) ], [ sort keys %{ $out->{materials} } ], 'materials' );

done_testing;
