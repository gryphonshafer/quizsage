use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Test;

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

# my $label_form = { form => { label => 'Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*' } };

# mojo
#     ->get_ok( '/api/v1/label/' . $_, %$label_form )
#     ->status_is(200)
#     ->json_like( qr/^Romans 12:1\-5 \(2\) James 1:2\-4 \(1\)/ )
#     for ( qw( canonicalize descriptionize ) );

# mojo->get_ok( '/api/v1/label/parse', %$label_form )->status_is(200)->json_is(
#     hash {
#         field ranges => array {
#             all_items hash {
#                 field weight => D();
#                 field range  => array {
#                     all_items E();
#                     etc;
#                 };
#             };
#             etc;
#         };
#         etc;
#     }
# );

# mojo->post_ok(
#     '/api/v1/label/format',
#     json => {
#         bibles => {
#             primary   => ['NIV'],
#             auxiliary => ['ESV'],
#         },
#         ranges => [
#             {
#                 range  => ['Romans 12:1-5'],
#                 weight => 2
#             },
#             {
#                 range  => ['James 1:2-4'],
#                 weight => 1
#             },
#         ],
#     },
# )->status_is(200)->json_is('Romans 12:1-5 (2) James 1:2-4 (1) ESV* NIV');

teardown;
