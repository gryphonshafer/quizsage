use Test2::V0;
use exact -conf;
use Omniframe;
use QuizSage::Model::Season;
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

my $obj;

ok(
    lives { $obj = Omniframe->with_roles('QuizSage::Role::Meet::Editing')->new },
    q{with_roles('QuizSage::Role::Meet::Editing')->new},
) or note $@;

DOES_ok( $obj, $_ ) for ( qw(
    Omniframe::Role::Model
    QuizSage::Role::Meet::Build
    QuizSage::Role::Meet::Settings
    QuizSage::Role::Meet::Editing
) );

can_ok( $obj, 'save_after_edit' );

$obj->dq('material')->begin_work;

my $sth = $obj->dq('material')->sql(q{
    INSERT INTO bible (acronym) VALUES (?)
    ON CONFLICT(acronym) DO NOTHING
});

$sth->run($_) for ( qw( NIV NASB NASB5 ) );

my $meet = QuizSage::Model::Meet->new;
$meet->dq->begin_work;

my $season = QuizSage::Model::Season->new->create({
    name     => 'Name',
    location => 'Location',
    start    => time - 60 * 60 * 24 * 365.25 * 7,
});

$meet->create({
    season_id => $season->id,
    name     => 'Name',
    location => 'Location',
    start    => time - 60 * 60 * 24 * 365.25 * 7,
    passwd   => 'password',
})->build;

my @teams = split( /\n\n/, $meet->data->{settings}{roster}{data} );
$teams[0] .= "\nExtra Quizzer";
pop @teams;
$meet->data->{settings}{roster}{data} = join( "\n\n", @teams );
$meet->data->{settings}{brackets}[0]{weight}++;
ok( lives { $meet->save_after_edit }, 'save_after_edit' ) or note $@;

my $quiz = QuizSage::Model::Quiz->new->create({
    meet_id  => $meet->id,
    bracket  => $meet->data->{settings}{brackets}[0]{name},
    name     => 1,
    settings => $meet->quiz_settings( $meet->data->{settings}{brackets}[0]{name}, 1 ),
});
$teams[0] =~ s/TEAM/GROUP/;
$meet->data->{settings}{roster}{data} = join( "\n\n", @teams );
$meet->data->{settings}{brackets}[0]{weight}--;
ok( lives { $meet->save_after_edit }, 'save_after_edit' ) or note $@;

$meet->dq->rollback;
$obj->dq('material')->rollback;
done_testing;
