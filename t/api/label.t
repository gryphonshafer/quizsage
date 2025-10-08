use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

my $model_label_obj = QuizSage::Model::Label->new;
my $mock_label      = mock 'QuizSage::Model::Label' => (
    override => [
        new            => sub { $model_label_obj },
        bible_acronyms => sub { [ qw( ESV NASB NIV ) ] },
    ],
);

setup;

mojo->post_ok('/api/v1/label/format')->status_is(401);
mojo->get_ok( '/api/v1/label/' . $_ )->status_is(401) for ( qw(
    aliases
    canonicalize
    descriptionize
    parse
) );

api_login;

mojo->get_ok('/api/v1/label/aliases')->status_is(200)->json_is(
    array {
        all_items hash {
            field $_ => E() for ( qw(
                name
                label
                is_self_made
                public
                last_modified
                created
            ) );
            field author => hash {
                field $_ => E() for ( qw(
                    first_name
                    last_name
                    email
                ) );
                end;
            };
            end;
        };
        etc;
    }
);

my $label_form = { form => { label => 'Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*' } };

mojo
    ->get_ok( '/api/v1/label/' . $_, %$label_form )
    ->status_is(200)
    ->json_like( qr/^Romans 12:1\-5 \(2\) James 1:2\-4 \(1\)/ )
    for ( qw( canonicalize descriptionize ) );

mojo->get_ok( '/api/v1/label/parse', %$label_form )->status_is(200)->json_is(
    hash {
        field parts => array {
            all_items hash {
                field type   => 'weighted_set';
                field weight => D();
                field parts  => array {
                    all_items hash {
                        field type => 'text';
                        field refs => T();
                    };
                    etc;
                };
            };
            etc;
        };
        etc;
    }
);

mojo->post_ok(
    '/api/v1/label/format',
    json => {
        bibles => {
            primary   => ['NIV'],
            auxiliary => ['ESV'],
        },
        parts => [
            {
                type   => 'weighted_set',
                weight => 2,
                parts  => [
                    {
                        type => 'text',
                        refs => 'Romans 12:1-5',
                    },
                ],
            },
            {
                type   => 'weighted_set',
                weight => 1,
                parts  => [
                    {
                        type => 'text',
                        refs => 'James 1:2-4',
                    },
                ],
            },
        ],
    },
)->status_is(200)->json_is('Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*');

teardown;
