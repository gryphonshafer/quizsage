use Test::Pod;
use Cwd 'getcwd';
use exact -conf;

my $root_dir = conf->get( qw( config_app root_dir ) );
my $cwd = getcwd;
chdir($root_dir);

all_pod_files_ok;
