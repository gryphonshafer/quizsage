use Test2::V0;
use exact -conf;
use Omniframe;
use Omniframe::Util::Data;

my $mock = mock 'Omniframe::Util::Data' => ( override => [ dataload => sub { +{
    default => {
        name => 'Christian Bible Quizzing (CBQ)',
        apps => {
            app_name => {
                module => ['vue/apps/app_name'],
                importmap => {
                    'name/used/in/imports'      => 'actual/path/to/file',
                    'name/also_used/in/imports' => 'actual/path/to/other_file',
                },
            },
        },
    },
    aubq => {
        name => 'Alternate Universe Bible Quizzing (AUBQ)',
        apps => {
            app_name => {
                extends   => 'default',
                importmap => {
                    'name/used/in/imports' => 'actual/path/to/alternate_file',
                },
            },
        },
    },
} } ] );

my $obj;

ok(
    lives { $obj = Omniframe->with_roles('QuizSage::Role::JSApp')->new },
    q{with_roles('QuizSage::Role::JSApp')->new},
) or note $@;

DOES_ok( $obj, 'QuizSage::Role::JSApp' );
can_ok( $obj, qw( js_app_names js_app_config ) );

is( $obj->js_app_names->[0], { id => 'default', name => D() }, 'js_app_names' );

is(
    $obj->js_app_config('app_name'),
    {
        module    => ['vue/apps/app_name'],
        importmap => {
            'name/used/in/imports'      => 'actual/path/to/file',
            'name/also_used/in/imports' => 'actual/path/to/other_file',
        },
    },
    'js_app_config(app_name)',
);

is(
    $obj->js_app_config( 'app_name', 'aubq' ),
    {
        module    => ['vue/apps/app_name'],
        importmap => {
            'name/used/in/imports'      => 'actual/path/to/alternate_file',
            'name/also_used/in/imports' => 'actual/path/to/other_file',
        },
    },
    'js_app_config( app_name aubq )',
);

done_testing;
