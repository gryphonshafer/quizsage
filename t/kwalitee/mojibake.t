use Test2::V0;
use Test::Mojibake;
use exact -conf;

all_files_encoding_ok( conf->get( qw( config_app root_dir ) ) );
done_testing;
