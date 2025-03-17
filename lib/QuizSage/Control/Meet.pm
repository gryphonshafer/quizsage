package QuizSage::Control::Meet;

use exact 'Mojolicious::Controller';
use Mojo::JSON 'encode_json';
use Omniframe::Util::Bcrypt 'bcrypt';
use QuizSage::Model::Meet;
use QuizSage::Model::Quiz;

sub passwd ($self) {
    if ( my $meet_passwd = $self->param('meet_passwd') ) {
        $self->stash('user')->data->{settings}{meet_passwd} = bcrypt($meet_passwd);
        $self->stash('user')->save;

        $self->flash(
            memo => {
                class   => 'success',
                message => 'Successfully set your meet official password.',
            }
        );

        $self->redirect_to( delete $self->session->{referer} // '/' );
    }
    else {
        $self->session( referer => $self->req->headers->referer );
    }
}

sub state ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    $self->stash(
        state   => $meet->state,
        qm_auth => $self->stash('user')->qm_auth($meet),
        meet    => $meet,
    );
}

sub roster ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    $self->stash(
        roster => $meet->data->{build}{roster},
        meet   => $meet,
    );
}

sub distribution ($self) {
    my $meet = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    $self->stash(
        build => $meet->distribution,
        meet  => $meet,
    );
}

sub stats ($self) {
    my $meet    = QuizSage::Model::Meet->new->load( $self->param('meet_id') );
    my $qm_auth = $self->stash('user')->qm_auth($meet);

    $self->stash(
        stats   => $meet->stats( ($qm_auth) ? $self->param('rebuild') : undef ),
        qm_auth => $qm_auth,
        meet    => $meet,
    );
}

sub board ($self) {
    my $quiz = QuizSage::Model::Quiz->new->latest_quiz_in_meet_room(
        $self->param('meet_id'),
        $self->param('room_number'),
    );

    if ( $self->tx->is_websocket ) {
        $self->socket( setup => encode_json( {
            type => 'board',
            meet => 0 + $self->param('meet_id'),
            room => 0 + $self->param('room_number'),
        } ) );
    }
    elsif ( ( $self->stash('format') // '' ) eq 'json' ) {
        $self->render( json => $quiz->data );
    }
    else {
        $self->stash( quiz => $quiz );
    }
}

1;

=head1 NAME

QuizSage::Control::Meet

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Meet" actions.

=head1 METHODS

=head2 passwd

This controller handles the setting of a user's meet password (otherwise known
as their quiz magistrate password).

=head2 state

This controller handles meet state display by setting the C<state> stash value
based on L<QuizSage::Model::Meet>'s C<state>. If a user has a matching meet
password, then the C<qm_auth> stash value will be true.

=head2 roster

This controller handles meet roster display by setting the C<roster> stash value
based on L<QuizSage::Model::Meet>'s C<build.roster> data.

=head2 distribution

This controller handles meet distribution display by setting the C<build> stash
value based on L<QuizSage::Model::Meet>'s C<build> data.

=head2 stats

This controller handles meet statistics display by setting the C<stats> stash
value based on L<QuizSage::Model::Meet>'s C<stats>.

=head2 board

This controller handler powers the live scoreboard display. It requires
C<meet_id> and C<room_number> parameters. Based on these, it'll either load the
latest quiz for the meet and room into the stash as C<quiz> (if a web page is
requested), return quiz data in JSON (if JSON is requested), or setup a web
socket for the meet and room (if a web socket is requested).

=head1 INHERITANCE

L<Mojolicious::Controller>.
