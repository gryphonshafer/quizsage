use Test2::V0;
use exact -conf;
use QuizSage::Model::Season;

my $obj;
ok( lives { $obj = QuizSage::Model::Season->new }, 'new' ) or note $@;
DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Model
    Omniframe::Role::Time
    QuizSage::Role::Data
) );
can_ok( $obj, qw(
    create
    freeze thaw seasons stats
) );

$obj->dq->begin_work;

my $label = $$ . ( time + rand );

ok(
    lives {
        $obj->create({
            name     => $label . ' Name Old',
            location => 'Location',
            start    => time - 60 * 60 * 24 * 365.25 * 7,
        });
        $obj->create({
            name     => $label . ' Name Current',
            location => 'Location',
            start    => time - 60 * 60 * 24 * 40,
        });
    },
    q/create(...)/,
) or note $@;

my $seasons = $obj->seasons;

ok(
    not( scalar( grep { $_->{name} eq $label . ' Name Old' and $_->{active} } $seasons->@* ) ),
    'Season "Name Old" not an active season',
);

is(
    ( grep { $_->{name} eq $label . ' Name Current' } $seasons->@* )[0],
    {
        season_id   => T(),
        name        => $label . ' Name Current',
        location    => 'Location',
        meets       => [],
        active      => 1,
        start       => T(),
        start_stamp => T(),
        start_year  => T(),
        stop        => T(),
        stop_stamp  => T(),
        stop_year   => T(),
    },
    'Season "Name Current" an active season',
);

ref_ok( $obj->data->{settings}, 'HASH', 'settings is a hash' );

ok( lives { $obj->stats }, 'stats' ) or note $@;

$obj->dq->rollback;

done_testing;
