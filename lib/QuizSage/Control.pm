package QuizSage::Control;

use exact 'Omniframe::Control';
use QuizSage::Model::User;

sub startup ($self) {
    $self->setup;

    my $all = $self->routes->under( sub ($c) {
        $c->stash( page => { wrappers => ['page.html.tt'] } );

        if ( my $user_id = $c->session('user_id') ) {
            try {
                $c->stash( 'user' => QuizSage::Model::User->new->load($user_id) );

                if (
                    $c->stash('user') and
                    $c->stash('user')->data and
                    $c->stash('user')->data->{settings}
                ) {
                    for my $type ( qw( theme style ) ) {
                        $c->session( $type => $c->stash('user')->data->{settings}{$type} )
                            if ( $c->stash('user')->data->{settings}{$type} );
                    }
                }
            }
            catch ($e) {
                delete $c->session->{'user_id'};
                $c->notice( 'Failed user load based on session "user_id" value: "' . $user_id . '"' );
            }
        }
        return 1;
    } );

    my $users = $all->under( sub ($c) {
        return 1 if ( $c->stash('user') );
        $c->info('Login required but not yet met');
        $c->flash( message => 'Login required for the previously requested resource.' );
        $c->redirect_to('/');
        return 0;
    } );

    $users->any('/user/profile')->to( 'user#account', account_action_type => 'profile' );
    $users->any('/user/logout')->to('user#logout');

    $users->any( '/memory/' . $_ )->to( 'memory#' . $_ ) for ( qw( memorize review ) );
    $users
        ->any( '/memory/state' => [ format => ['json'] ] )
        ->to( 'memory#state', format => undef );

    $users->any('/meet/passwd')->to('meet#passwd');
    $users
        ->any( '/meet/:meet_id/board/:room_number' => [ format => ['json'] ] )
        ->to( 'meet#board', format => undef );
    $users->any( '/meet/:meet_id/' . $_ )->to( 'meet#' . $_ ) for ( qw( state roster distribution stats ) );

    $users->any( '/season/:season_id' . $_->[0] )->to( 'season#' . $_->[1] ) for (
        [ '/stats', 'stats' ],
    );

    $users->any(
        '/:setup_type' => [ setup_type => [ qw(
            memory/memorize/setup
            drill/setup
            quiz/pickup/setup
            reference/lookup/setup
            reference/generator/setup
        ) ] ]
    )->to('main#setup');

    $users->any("/quiz/$_")->to("quiz#$_") for ( qw( teams build ) );

    $users
        ->any( $_->[0] => [ format => ['json'] ] )
        ->to(
            $_->[1],
            format            => undef,
            maybe action_type => $_->[2],
        ) for (
            [ '/drill',                'quiz#queries', 'drill'   ],
            [ '/queries',              'quiz#queries', 'queries' ],
            [ '/quiz/:quiz_id',        'quiz#quiz',    undef     ],
            [ '/quiz/pickup/:quiz_id', 'quiz#quiz',    undef     ],
        );

    $users->post('/quiz/save/:quiz_id'  )->to('quiz#save'  );
    $users->any ('/quiz/delete/:quiz_id')->to('quiz#delete');

    $users->any( '/reference/' . $_ )->to('reference#' . $_ ) for ( qw( lookup generator ) );

    $all->any('/')->to('main#home');
    $all->any( '/set/:type/:name' => [ type => [ qw( theme style ) ] ] )->to('main#set');
    $all->any('/captcha')->to('main#captcha');

    $all->any("/user/$_")->to("user#$_") for ( qw( forgot_password login ) );
    $all->any('/user/create')->to( 'user#account', account_action_type => 'create' );
    $all->any("/user/$_/:user_id/:user_hash")->to("user#$_") for ( qw( verify reset_password ) );

    $all->any( '/docs/*name' => sub ($c) {
        $c->document( 'docs/' . $c->stash('name') );
        $c->stash( docs_nav => $c->docs_nav('docs') );

        if ( $c->stash('html') ) {
            $c->render( template => 'docs' );
        }
        else {
            $c->redirect_to('/');
        }
    } );

    $all->any( '/*null' => { null => undef } => sub ($c) { $c->redirect_to('/') } );
}

1;

=head1 NAME

QuizSage::Control

=head1 SYNOPSIS

    #!/usr/bin/env perl
    use MojoX::ConfigAppStart;
    MojoX::ConfigAppStart->start;

=head1 DESCRIPTION

This class is a subclass of L<Omniframe::Control> and provides an override to
the C<startup> method such that L<MojoX::ConfigAppStart> (along with its
required C<mojo_app_lib> configuration key) is sufficient to startup the web
application.

=head1 METHODS

=head2 startup

This is the startup method for L<Mojolicious>. This method calls
L<Omniframe::Control>'s C<setup> and sets all routes for the web application.

All routes are given the page wrapper C<page.html.tt>, which itself is wrapped
by Omniframe's C<wrapper.html.tt>.

When a user logs in, their browser is given a C<user_id>, which (if valid) is
loaded into a C<user> object for all pages.

=head1 INHERITANCE

L<Omniframe::Control>.
