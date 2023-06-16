use Test2::V0;
use Test2::MojoX;
use exact -conf;
use Omniframe::Control;

$ENV{MOJO_LOG_LEVEL} = 'error';

my $mock = mock 'Omniframe::Control' => (
    override => [ qw( setup_access_log debug info notice warning warn ) ],
);

Test2::MojoX->new('QuizSage::Control')->get_ok('/')
    ->status_is(200)
    ->header_is( 'content-type' => 'text/html;charset=UTF-8' )
    ->text_is( title => 'Example Page' )
    ->attr_like( 'link[rel="stylesheet"]:last-of-type', 'href', qr|\bapp.css\?version=\d+| );

done_testing;
