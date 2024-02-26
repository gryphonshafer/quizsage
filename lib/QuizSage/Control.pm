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

    $users->any('/meet/passwd')->to('meet#passwd');
    $users
        ->any( '/meet/:meet_id/board/:room_number' => [ format => ['json'] ] )
        ->to( 'meet#board', format => undef );
    $users->any( '/meet/:meet_id' . $_->[0] )->to( 'meet#' . $_->[1] ) for (
        [ '/roster',       'roster'       ],
        [ '/distribution', 'distribution' ],
        [ '/stats',        'stats'        ],
        [ '',              'state'        ],
    );

    $users->any(
        '/:practice_type' => [ practice_type => [ qw( quiz/pickup queries/setup ) ] ]
    )->to('quiz#practice');

    $users->any("/quiz/$_")->to("quiz#$_") for ( qw( teams build ) );

    $users->any( $_->[0] => [ format => ['json'] ] )->to( $_->[1], format => undef ) for (
        [ '/queries',       'quiz#queries'      ],
        [ '/quiz/queries',  'quiz#quiz_queries' ],
        [ '/quiz/:quiz_id', 'quiz#quiz'         ],
    );

    $users->post('/quiz/save/:quiz_id'  )->to('quiz#save'  );
    $users->any ('/quiz/delete/:quiz_id')->to('quiz#delete');

    $all->any('/')->to('main#home');

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
required C<mojo_app_lib> configuration key) is sufficient to startup a basic
(and mostly useless) web application.

=head1 METHODS

=head2 startup

This is a basic, thin startup method for L<Mojolicious>. This method calls
C<setup> and sets a universal route that renders a basic text message.

=head1 INHERITANCE

L<Omniframe::Control>.
