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
    return unless ( $self->data->{meet_id} and defined $self->data->{settings}{room} );

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

sub pickup ( $self, $pickup_settings, $user ) {
    my $quiz_settings    = {};
    my $quiz_defaults    = $self->conf->get('quiz_defaults');
    my $available_bibles = $self->dq('material')->get( 'bible', ['acronym'] )->run->column;

    # canonicalize default bible acronym

    $pickup_settings->{bible} = uc ( $pickup_settings->{bible} // '' );
    die 'Default bible is invalid or unavailable'
        unless ( $pickup_settings->{bible} and grep { $_ eq $pickup_settings->{bible} } @$available_bibles );

    # canonicalize roster and save in quiz settings

    my $roster = {
        default_bible => $pickup_settings->{bible},
        data          => $pickup_settings->{roster_data},
    };
    QuizSage::Model::Meet->parse_and_structure_roster_text( \$roster );
    $quiz_settings->{teams} = $roster;

    # parse material label, append missing bibles, and build material JSON

    my $roster_bibles = { map { $_->{bible} => 1 } map { $_->{quizzers}->@* } @$roster };
    my $label         = QuizSage::Model::Label->new( user_id => $user->id );
    my $label_data    = $label->parse( $pickup_settings->{material_label} );

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
        importmap => $self->js_app_config( 'quiz', $pickup_settings->{js_apps_id} )->{importmap},
    )->run(
        $root_dir . '/ocjs/lib/Model/Meet/distribution.js',
        {
            bibles      => $label_data->{bibles}{primary},
            teams_count => scalar( $quiz_settings->{teams}->@* ),
        },
    )->[0][0];

    # cleanup roster data and save user pickup quiz settings

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

    # create and return quiz

    return $self->create({
        settings => $quiz_settings,
        user_id  => $user->id,
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

sub create_material_json_from_label ( $self, $label, $user ) {
    my $label_obj       = QuizSage::Model::Label->new( user_id => $user->id );
    my $canonical_label = ( ref $label ) ? $label_obj->format($label) : $label_obj->canonicalize($label);
    my $material        = material_json( label => $canonical_label );

    return {
        label       => $canonical_label,
        description => $material->{description},
        id          => $material->{id},
    };
}

1;

=head1 NAME

QuizSage::Model::Quiz

=head1 SYNOPSIS

    use QuizSage::Model::Quiz;

    my $quiz = QuizSage::Model::Quiz->new;

=head1 DESCRIPTION

This class is the model for quiz objects.

=head1 OBJECT METHODS

=head2 freeze, thaw

=head2 pickup

=head2 settings

=head2 latest_quiz_in_meet_room

=head2 ensure_material_json_exists

=head2 create_material_json_from_label

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<QuizSage::Role::JSApp>.
