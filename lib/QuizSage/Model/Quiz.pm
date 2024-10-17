package QuizSage::Model::Quiz;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use Omniframe::Class::Javascript;
use Omniframe::Mojo::Socket;
use QuizSage::Model::Label;
use QuizSage::Model::Meet;
use QuizSage::Util::Material 'material_json';

with qw( Omniframe::Role::Model QuizSage::Role::JSApp );

class_has socket => Omniframe::Mojo::Socket->new;

after [ qw( create save delete ) ] => sub ( $self, @params ) {
    return unless ( $self->data->{meet_id} );

    my $season_id = $self->dq
        ->sql('SELECT season_id FROM meet WHERE meet_id = ?')
        ->run( $self->data->{meet_id} )->value;
    $self->dq->sql('UPDATE meet SET stats = NULL WHERE meet_id = ?')->run( $self->data->{meet_id} );
    $self->dq->sql('UPDATE season SET stats = NULL WHERE season_id = ?')->run($season_id);

    return unless ( defined $self->data->{settings}{room} );

    $self->socket->message(
        encode_json( {
            type => 'board',
            meet => 0 + $self->data->{meet_id},
            room => 0 + $self->data->{settings}{room},
        } ),
        $self->data->{ ( $self->data->{state} ) ? 'state' : 'settings' },
    );
};

sub freeze ( $self, $data ) {
    for ( qw( settings state ) ) {
        $data->{$_} = encode_json( $data->{$_} );
        undef $data->{$_} if ( $data->{$_} eq '{}' or $data->{$_} eq 'null' );
    }

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{$_} = ( defined $data->{$_} ) ? decode_json( $data->{$_} ) : {}
        for ( qw( settings state ) );

    return $data;
}

sub pickup ( $self, $pickup_settings, $user = undef ) {
    my $quiz_settings    = {};
    my $quiz_defaults    = $self->conf->get('quiz_defaults');
    my $available_bibles = $self->dq('material')->get( 'bible', ['acronym'] )->run->column;

    # canonicalize default bible acronym

    $pickup_settings->{bible} = uc ( $pickup_settings->{bible} // $quiz_defaults->{bible} // '' );
    die 'Default bible is invalid or unavailable'
        unless ( $pickup_settings->{bible} and grep { $_ eq $pickup_settings->{bible} } @$available_bibles );

    # canonicalize roster and save in quiz settings

    $pickup_settings->{roster_data} //= $quiz_defaults->{roster_data};

    my $roster = {
        default_bible => $pickup_settings->{bible},
        data          => $pickup_settings->{roster_data},
    };
    QuizSage::Model::Meet->parse_and_structure_roster_text( \$roster );
    $quiz_settings->{teams} = $roster;

    # parse material label, append missing bibles, and build material JSON

    my $roster_bibles = { map { $_->{bible} => 1 } map { $_->{quizzers}->@* } @$roster };
    my $label         = QuizSage::Model::Label->new( maybe user_id => $user->id );
    my $label_data    = $label->parse(
        $pickup_settings->{material_label} // $quiz_defaults->{material_label}
    );

    $label_data->{bibles}          //= {};
    $label_data->{bibles}{primary} //= [ $pickup_settings->{bible} ];

    my $label_bibles = [ map {@$_} (
        $label_data->{bibles}{primary},
        $label_data->{bibles}{auxiliary} // [],
    ) ];

    push( @{ $label_data->{bibles}{primary} }, $_ ) for (
        grep {
            my $roster_bible = $_;
            not grep { $_ eq $roster_bible } @$label_bibles;
        } keys %$roster_bibles
    );

    $quiz_settings->{material} = $self->create_material_json_from_label( $label_data, $user );

    # build distribution

    my $root_dir = $self->conf->get( qw( config_app root_dir ) );

    $quiz_settings->{distribution} = Omniframe::Class::Javascript->new(
        basepath  => $root_dir . '/static/js',
        importmap => $self->js_app_config(
            'quiz',
            $pickup_settings->{js_apps_id} // $quiz_defaults->{js_apps_id},
        )->{importmap},
    )->run(
        $root_dir . '/ocjs/lib/Model/Meet/distribution.js',
        {
            bibles      => $label_data->{bibles}{primary},
            teams_count => scalar( $quiz_settings->{teams}->@* ),
        },
    )->[0][0];

    # cleanup roster data and save user pickup quiz settings

    if ($user) {
        $pickup_settings->{roster_data} =~ s/[ ]{2,}/ /g;
        $pickup_settings->{roster_data} =~ s/\t/ /g;
        $pickup_settings->{roster_data} =~ s/\r?\n/\n/g;
        $pickup_settings->{roster_data} =~ s/\n{3,}/\n\n/g;
        $pickup_settings->{roster_data} =~ s/(?:^\s+|\s+$)//g;

        $user->data->{settings}{pickup_quiz} = {
            bible          => $pickup_settings->{bible},
            material_label => $quiz_settings->{material}{label},
            roster_data    => $pickup_settings->{roster_data},
        };

        $user->save;
    }

    # create and return quiz

    return $self->create({
        settings      => $quiz_settings,
        maybe user_id => ($user) ? $user->id : undef,
    });
}

sub latest_quiz_in_meet_room ( $self, $meet_id, $room_number ) {
    my $quiz_id = $self->dq->sql(q{
        SELECT quiz_id
        FROM quiz
        WHERE meet_id = ? AND JSON_EXTRACT( settings, '$.room' ) = ?
        ORDER BY last_modified DESC
        LIMIT 1
    })->run( $meet_id, $room_number )->value;

    return unless ($quiz_id);
    return $self->load($quiz_id);
}

sub ensure_material_json_exists ($self) {
    return if ( -f join( '/',
        $self->conf->get( qw( config_app root_dir ) ),
        $self->conf->get( qw( material json location ) ),
        $self->data->{settings}{material}{id} . '.json',
    ) );

    my $material = material_json( description => $self->data->{settings}{material}{description} );

    if ( $self->data->{settings}{material}{id} ne $material->{id} ) {
        $self->data->{settings}{material}{id} = $material->{id};
        $self->save;
    }
}

sub create_material_json_from_label ( $self, $label, $user = undef ) {
    my $label_obj       = QuizSage::Model::Label->new( maybe user_id => $user->id );
    my $canonical_label = ( ref $label ) ? $label_obj->format($label) : $label_obj->canonicalize($label);
    my $material        = material_json( label => $canonical_label );

    return {
        label       => $canonical_label,
        description => $material->{description},
        id          => $material->{id},
    };
}

sub recent_pickup_quizzes ( $self, $user_id, $ctime_life = undef ) {
    $self->dq
        ->sql(q{DELETE FROM quiz WHERE JULIANDAY('NOW') - JULIANDAY(created) > ?})
        ->run( $ctime_life // $self->conf->get('pickup_quiz_ctime_life') );

    return [
        sort { $b->{created} cmp $a->{created} }
        map {
            my $quiz = $_;

            my $current_query;
            if (
                $quiz->{data}{state} and
                $quiz->{data}{state}{board} and
                $quiz->{data}{state}{board}->@*
            ) {
                my ($current) = grep { $_->{current} } $quiz->{data}{state}{board}->@*;
                $current_query = ($current) ? $current->{id} : 'Done';
            }
            else {
                $current_query = '1A';
            }

            +{
                quiz_id       => $quiz->{data}{quiz_id},
                created       => $quiz->{data}{created},
                teams         => $quiz->{data}{settings}{teams},
                current_query => $current_query,
                label         => $quiz->{data}{settings}{material}{label},
            };
        } $self->every({ user_id => $user_id })->@*
    ];
}

1;

=head1 NAME

QuizSage::Model::Quiz

=head1 SYNOPSIS

    use QuizSage::Model::Quiz;
    use QuizSage::Model::User;

    my $quiz = QuizSage::Model::Quiz->new;

    my $pickup_quiz = $quiz->pickup(
        {},                                  # quiz settings
        QuizSage::Model::User->new->load(1), # user (optional),
    );

    my $quiz_object = $quiz->latest_quiz_in_meet_room(
        42, # meet ID
        1,  # room number
    );

    $quiz->ensure_material_json_exists;

    my $material_metadata = $quiz->create_material_json_from_label(
        'Gal 1-2',                            # material label
        QuizSage::Model::User->new->load(42), # user (optional)
    );

=head1 DESCRIPTION

This class is the model for quiz objects.

=head1 EXTENDED METHODS

=head2 create, save, delete

Extended from L<Omniframe::Role::Model>, these methods are appended with
functionality that will, if the object is a quiz under a meet (versus a pickup
quiz) message the scoreboard socket for the meet and room with the C<state> or
C<settings> of the quiz.

=head1 OBJECT METHODS

=head2 freeze, thaw

Likely not used directly, these method run data pre-save to and post-read from
the database functions. C<freeze> will encode C<settings> C<thaw> will decode
C<settings>.

=head2 pickup

This method requires a settings hashref and can accept an optional user object.
Based on these inputs, the method will generate a pickup quiz and return that
quiz object.

    my $pickup_quiz = $quiz->pickup(
        {},                                  # quiz settings
        QuizSage::Model::User->new->load(1), # user (optional),
    );

Internally, given the quiz settings hashref, the method will:

=over

=item * Canonicalize the default C<bible> acronym and C<roster_data>, then save
in the pickup quiz's settings

=item * Parse the C<material_label>, append any missing bibles, and build a
material JSON file

=item * Build a distribution for the quiz using the "quiz"
L<QuizSage::Role::JSApp> configuration

=item * Cleanup settings data and save it to the user's settings under
C<pickup_quiz> (if a user was provided as input)

=back

Any missing configuration values are pulled from quiz settings defaults from the
C<quiz_defaults> configuration value.

=head2 latest_quiz_in_meet_room

This method requires a meet ID and a room number as input, and it will search
for and return the quiz object of the last modified quiz matching the inputs
(or undefined if no quiz is found).

    my $quiz_object = $quiz->latest_quiz_in_meet_room(
        42, # meet ID
        1,  # room number
    );

=head2 ensure_material_json_exists

This method will ensure the material JSON file for a quiz exists. If the file
doesn't exist, it'll be created.

    $quiz->ensure_material_json_exists;

=head2 create_material_json_from_label

This method will create a material JSON file from a material label (and
optionally a loaded user object).

    my $material_metadata = $quiz->create_material_json_from_label(
        'Gal 1-2',                            # material label
        QuizSage::Model::User->new->load(42), # user (optional)
    );

The hashref returned will contains keys for C<label>, C<description>, and C<id>.

=head2 recent_pickup_quizzes

This method requires a user ID and an optional integer. It will delete all
pickup quizzes created older in days than the integer or
C<pickup_quiz_mtime_life> configuration value. It will then return a list of
remaining pickup quizzes.

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<QuizSage::Role::JSApp>.
