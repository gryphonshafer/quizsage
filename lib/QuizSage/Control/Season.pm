package QuizSage::Control::Season;

use exact 'Mojolicious::Controller';
use Mojo::File 'path';
use QuizSage::Model::Meet;
use QuizSage::Model::Season;
use YAML::XS qw( LoadFile Load Dump );

sub stats ($self) {
    my $season = QuizSage::Model::Season->new->load( $self->param('season_id') );
    $self->stash(
        stats  => $season->stats,
        season => $season,
    );
}

sub _filter_and_sort ( $self, @records ) {
    return [
        sort {
            $b->data->{start} cmp $a->data->{start} or
            $a->data->{location} cmp $b->data->{location} or
            $a->data->{name} cmp $b->data->{name}
        }
        grep { $_->admin_auth( $self->stash('user') ) }
        @records
    ];
}

sub admin ($self) {
    my $seasons = $self->_filter_and_sort( QuizSage::Model::Season->new->every );
    my $meets   = [
        grep {
            my $meet_season_id = $_->data->{season_id};
            not grep { $meet_season_id == $_->data->{season_id} } @$seasons;
        }
        @{ $self->_filter_and_sort( QuizSage::Model::Meet->new->every ) }
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
            if ( $self->param('action') and $self->param('user_id') ) {
                $season->admin( $self->param('action'), $self->param('user_id') );
                return $self->redirect_to( '/season/' . $self->param('season_id') . '/edit' );
            }
            elsif ( $self->param('name') ) {
                try {
                    $season->data->{settings} = Load( $self->param('settings') )
                        if ( $self->param('settings') );
                    $season->data->{$_} = $self->param($_) for ( qw( name location start days ) );
                    $season->save;
                    return $self->redirect_to('/season/admin');
                }
                catch ($e) {
                    $self->notice($e);
                    $self->flash(
                        message => 'There was an unexpected error in editing the season.',
                        map { $_ => $self->param($_) } qw( name location start days settings ),
                    );
                    return $self->redirect_to( '/season/' . $self->param('season_id') . '/edit' );
                }
            }
            else {
                my $yaml = Dump( $season->data->{settings} // '' );
                $yaml =~ s/^\-+//;

                $self->stash(
                    season   => $season,
                    settings => $yaml,
                    meets    => $self->_filter_and_sort(
                        QuizSage::Model::Meet->new->every({ season_id => $self->param('season_id') })
                    ),
                );
            }
        }
    }
    elsif ( $self->param('name') ) {
        try {
            $season->create({
                user_id        => $self->stash('user')->id,
                name           => $self->param('name'),
                maybe location => $self->param('location') || undef,
                maybe start    => $self->param('start')    || undef,
                maybe days     => $self->param('days')     || undef,
                maybe settings => ( ( $self->param('settings') ) ? Load( $self->param('settings') ) : undef ),
            });
            return $self->redirect_to('/season/admin');
        }
        catch ($e) {
            $self->notice($e);
            $self->flash(
                message => 'There was an unexpected error in creating the season.',
                map { $_ => $self->param($_) } qw( name location start days settings ),
            );
            return $self->redirect_to('/season/create');
        }
    }
    else {
        ( my $yaml = path(
            $season->conf->get( qw( config_app root_dir ) ) . '/config/meets/defaults/season.yaml'
        )->slurp ) =~ s/^\-+//;

        $self->stash( settings => $yaml );
    }
}

sub delete ($self) {
    QuizSage::Model::Season->new->load( $self->param('season_id') )->delete;
    return $self->redirect_to('/season/admin');
}

sub meet ($self) {
    my $meet = QuizSage::Model::Meet->new;

    if ( $self->param('meet_action_type') eq 'add' ) {
        unless ( $self->param('settings') ) {
            ( my $yaml = path(
                $meet->conf->get( qw( config_app root_dir ) ) . '/config/meets/defaults/meet.yaml'
            )->slurp ) =~ s/^\-+//;
            my $roster_data = Load($yaml)->{roster}{data};
            $yaml =~ s/\nroster\s*:.*(?=\n\w)//ms;

            $self->stash(
                settings    => $yaml,
                roster_data => $roster_data,
            );
        }
        else {
            try {
                die 'User account not authorized for this action' unless (
                    QuizSage::Model::Season->new
                        ->load( $self->param('season_id') )
                        ->admin_auth( $self->stash('user') )
                );

                my $settings = Load( $self->param('settings') );
                $settings->{roster}{data} = $self->param('roster_data');

                my $warnings = $meet->create({
                    season_id => $self->param('season_id'),
                    settings  => $settings,
                    map { $_ => $self->param($_) } qw( name location start days passwd ),
                })->build( $self->stash('user')->id );

                $self->flash( message => {
                    type => ( (@$warnings) ? 'notice' : 'success' ),
                    text => 'New meet created and built' .
                        ( (@$warnings) ? ', but with the following warnings:' : '' ),
                    maybe bullets => ( (@$warnings) ? $warnings : undef ),
                } );

                return $self->redirect_to('/season/admin');
            }
            catch ($e) {
                $self->notice($e);
                $self->flash(
                    message => ( length $e < 1024 )
                        ? deat $e
                        : 'There was an unexpected error in creating the meet.',
                    map { $_ => $self->param($_) } qw( name location start days passwd settings ),
                );
                return $self->redirect_to( '/season/' . $self->param('season_id') . '/meet/add' );
            }
        }
    }
    else {
        unless ( $meet->load( $self->param('meet_id') )->admin_auth( $self->stash('user') ) ) {
            $self->flash( message => 'User account not authorized for this action' );
            return $self->redirect_to('/season/admin');
        }
        elsif ( $self->param('action') and $self->param('user_id') ) {
            $meet->admin( $self->param('action'), $self->param('user_id') );
            return $self->redirect_to(
                '/season/' . $meet->data->{season_id} . '/meet/' . $meet->id . '/edit'
            );
        }
        elsif ( $self->param('meet_action_type') eq 'edit' ) {
            unless ( $self->param('settings') ) {
                my $roster_data   = delete $meet->data->{settings}{roster}{data};
                my $default_bible = delete $meet->data->{settings}{roster}{default_bible};

                delete $meet->data->{settings}{roster} unless ( $meet->data->{settings}{roster}->%* );

                ( my $yaml = Dump( $meet->data->{settings} ) ) =~ s/^\-+//;

                $self->stash(
                    meet          => $meet,
                    settings      => $yaml,
                    default_bible => $default_bible // $meet->conf->get( qw( quiz_defaults bible ) ),
                    roster_data   => $roster_data,
                );
            }
            else {
                try {
                    my $settings = Load( $self->param('settings') );

                    $settings->{roster}{data}          = $self->param('roster_data');
                    $settings->{roster}{default_bible} = $self->param('default_bible');

                    $meet->data->{settings} = $settings;
                    $meet->data->{settings} = $meet->canonical_settings( $self->stash('user')->id );

                    $meet->data->{$_} = $self->param($_)
                        for ( grep { $self->param($_) } qw( name location start days passwd ) );

                    my ( $result, $warnings ) = $meet->save_and_maybe_rebuild( $self->stash('user')->id );

                    if ( $result eq 'success' ) {
                        $self->flash( message => {
                            type => ( (@$warnings) ? 'notice' : 'success' ),
                            text => 'Meet changes saved' .
                                ( (@$warnings) ? ', but with the following warnings:' : '' ),
                            maybe bullets => ( (@$warnings) ? $warnings : undef ),
                        } );
                    }
                    elsif ($result) {
                        $self->flash( message => 'Changes rejected: ' . $result );
                    }

                    return $self->redirect_to('/season/admin');
                }
                catch ($e) {
                    $self->notice($e);
                    $self->flash(
                        message => deat $e,
                        map { $_ => $self->param($_) } qw(
                            name location start days passwd settings default_bible roster_data
                        ),
                    );
                    return $self->redirect_to(
                        '/season/' . $self->param('season_id') . '/meet/' . $self->param('meet_id') . '/edit'
                    );
                }
            }
        }
        elsif ( $self->param('meet_action_type') eq 'delete' ) {
            $meet->delete;

            $self->flash( message => {
                type => 'success',
                text => 'Meet deleted',
            } );

            return $self->redirect_to('/season/admin');
        }
    }
}

1;

=head1 NAME

QuizSage::Control::Season

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Season" actions.

=head1 METHODS

=head2 stats

This controller handles meet statistics display by setting the C<stats> stash
value based on L<QuizSage::Model::Season>'s C<stats>.

=head2 admin

This controller handles the season administration page.

=head2 record

This controller handles season creation and editing display and functionality.

=head2 delete

This controller handles season deletion.

=head2 meet

This controller handles meet creation, editing, and deleting.

=head1 INHERITANCE

L<Mojolicious::Controller>.
