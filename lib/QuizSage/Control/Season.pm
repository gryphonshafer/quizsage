package QuizSage::Control::Season;

use exact 'Mojolicious::Controller';
use Mojo::File 'path';
use QuizSage::Model::Meet;
use QuizSage::Model::Season;
use YAML::XS qw( LoadFile Load Dump );

sub admin ($self) {
    my $filter_and_sort = sub {
        return [
            sort {
                $b->data->{start} cmp $a->data->{start} or
                $a->data->{location} cmp $b->data->{location} or
                $a->data->{name} cmp $b->data->{name}
            }
            grep { $_->admin_auth( $self->stash('user') ) }
            @_
        ];
    };

    my $seasons = $filter_and_sort->( QuizSage::Model::Season->new->every );
    my $meets   = [
        grep {
            my $meet_season_id = $_->data->{season_id};
            not grep { $meet_season_id == $_->data->{season_id} } @$seasons;
        }
        @{ $filter_and_sort->( QuizSage::Model::Meet->new->every ) }
    ];

    $self->stash(
        seasons => $seasons,
        meets   => $meets,
    );
}

sub record ($self) {
    my $season = QuizSage::Model::Season->new;

    if ( $self->param('season_id') ) {
        my $season = $season->load( $self->param('season_id') );
        if ( $season->admin_auth( $self->stash('user') ) ) {
            if ( $self->param('name') ) {
                $season->data->{settings} = Load( $self->param('settings') ) if ( $self->param('settings') );
                $season->data->{$_} = $self->param($_) for ( qw( name location start days ) );
                $season->save;
                return $self->redirect_to('/season/admin');
            }
            else {
                my $yaml = Dump( $season->data->{settings} // '' );
                $yaml =~ s/^\-+//;

                $self->stash(
                    season          => $season,
                    season_settings => $yaml,
                );
            }
        }
    }
    elsif ( $self->param('name') ) {
        $season->create({
            user_id        => $self->stash('user')->id,
            name           => $self->param('name'),
            maybe location => $self->param('location'),
            maybe start    => $self->param('start'),
            maybe days     => $self->param('days'),
            maybe settings => ( ( $self->param('settings') ) ? Load( $self->param('settings') ) : undef ),
        });
        return $self->redirect_to('/season/admin');
    }
    else {
        ( my $yaml = path(
            $season->conf->get( qw( config_app root_dir ) ) . '/config/meets/defaults/season.yaml'
        )->slurp ) =~ s/^\-+//;

        $self->stash( season_settings => $yaml );
    }
}

sub stats ($self) {
    my $season = QuizSage::Model::Season->new->load( $self->param('season_id') );
    $self->stash(
        stats  => $season->stats,
        season => $season,
    );
}

1;

=head1 NAME

QuizSage::Control::Season

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Season" actions.

=head1 METHODS

=head2 admin

This controller handles the season administration page.

=head2 record

This controller handles season creation and editing display and functionality.

=head2 stats

This controller handles meet statistics display by setting the C<stats> stash
value based on L<QuizSage::Model::Season>'s C<stats>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
