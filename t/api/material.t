use Test2::V0;
use exact -conf;
use Omniframe::Test::App;
use QuizSage::Model::Label;
use QuizSage::Test;

my @spew;
my $mock_mojo_file  = mock 'Mojo::File' => ( override => [ spew  => sub { @spew = @_ } ] );
my $mock_file_path  = mock 'File::Path' => ( override => 'make_path' );
my $model_label_obj = QuizSage::Model::Label->new;
my $mock_label      = mock 'QuizSage::Model::Label' => (
    override => [
        new            => sub { $model_label_obj },
        bible_acronyms => sub { [ qw( ESV NASB NIV ) ] },
    ],
);

setup;

mojo->get_ok( '/api/v1/material/' . $_ )->status_is(401) for ( qw(
    bibles
    payload
    reference/data
    reference/html
) );

api_login;

mojo->get_ok('/api/v1/material/bibles')->status_is(200)->json_is(
    array {
        all_items hash {
            field $_ => E() for ( qw(
                acronym
                label
                name
                year
            ) );
            end;
        };
        etc;
    }
);

my $label_form      = { form => { label => 'Romans 12:1-5 (2) James 1:2-4 (1) NIV ESV*' } };
my $mock_mojo_file2 = mock 'Mojo::File' => ( override => [ slurp => sub { '{"fake_data":1}' } ] );

mojo->get_ok( '/api/v1/material/payload', %$label_form )->status_is(200)->json_is({ fake_data => 1 });

mojo->get_ok(
    '/api/v1/material/reference/data',
    form => {
        label => $label_form->{form}{label},
        bible => 'NIV',
    },
)->status_is(200)->json_is(
    hash {
        field $_ => E() for ( qw(
            cover
            description
            id
            labels
            uniques
            page_width
            page_height
            page_left_margin_bottom
            page_left_margin_left
            page_left_margin_right
            page_left_margin_top
            page_right_margin_bottom
            page_right_margin_left
            page_right_margin_right
            page_right_margin_top
        ) );
        field bible    => 'NIV';
        field bibles   => ['ESV'];
        field sections => array {
            all_items hash {
                etc;
            };
            etc;
        };
        end;
    }
);

mojo->get_ok(
    '/api/v1/material/reference/html',
    form => {
        label => $label_form->{form}{label},
        bible => 'NIV',
    },
)
    ->status_is(200)
    ->text_like( title => qr/Ro 12:1-5; Jam 1:2-4 NIV with ESV/ )
    ->text_like( h2 => qr/Reference Material/ );

teardown;
