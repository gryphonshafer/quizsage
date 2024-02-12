package QuizSage::Model::Quiz;

use exact -class;
use Mojo::JSON qw( encode_json decode_json );
use Omniframe::Class::Javascript;
use QuizSage::Model::Meet;
use QuizSage::Util::Material 'material_json';

with qw( Omniframe::Role::Model QuizSage::Role::JSApp );

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

sub pickup ( $self, $pickup_settings, $user_id ) {
    my $quiz_settings = {};

    my $quiz_defaults = $self->conf->get('quiz_defaults');
    $pickup_settings->{$_} //= $quiz_defaults->{$_} for ( qw( material roster_data ) );
    $pickup_settings->{default_bible} //= $quiz_defaults->{bible};

    my $roster = {
        default_bible => $pickup_settings->{default_bible},
        data          => $pickup_settings->{roster_data},
    };
    QuizSage::Model::Meet->parse_and_structure_roster_text( \$roster );
    $quiz_settings->{teams} = $roster;

    my $material = material_json( label => $pickup_settings->{material} );
    $quiz_settings->{material} = {
        label       => $pickup_settings->{material},
        description => $material->{description},
        material_id => $material->{material_id},
    };

    my $root_dir = $self->conf->get( qw( config_app root_dir ) );
    my $bibles   = decode_json( $material->{json_file}->slurp )->{bibles};

    $quiz_settings->{distribution} = Omniframe::Class::Javascript->new(
        basepath  => $root_dir . '/static/js',
        importmap => $self->js_app_config( 'quiz', $pickup_settings->{js_apps_id} )->{importmap},
    )->run(
        $root_dir . '/ocjs/lib/Model/Meet/distribution.js',
        {
            bibles      => [ grep { $bibles->{$_}{type} eq 'primary' } keys %$bibles ],
            teams_count => scalar( $quiz_settings->{teams}->@* ),
        },
    )->[0][0];

    return $self->create({
        settings => $quiz_settings,
        user_id  => $user_id,
    });
}

sub settings ($self) {
    my $js_app_config = $self->js_app_config( 'quiz', $self->data->{js_apps_id} );

    for ( qw( module defer importmap ) ) {
        $js_app_config->{$_} = $self->data->{$_} if ( exists $self->data->{$_} );
    }

    return $js_app_config;
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

=head1 WITH ROLES

L<Omniframe::Role::Model>, L<QuizSage::Role::JSApp>.
