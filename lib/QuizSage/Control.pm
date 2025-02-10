package QuizSage::Control;

use exact -conf, 'Omniframe::Control';
use MIME::Base64 'encode_base64';
use Mojo::JSON 'encode_json';
use Omniframe::Util::File 'opath';
use QuizSage::Model::User;

sub startup ($self) {
    $self->setup;

    my $captcha_conf = conf->get('captcha');
    $captcha_conf->{ttf} = opath( $captcha_conf->{ttf} );
    $self->plugin( CaptchaPNG => $captcha_conf );

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

                    $c->res->cookies({
                        name  => 'quizsage_info',
                        value => encode_base64( encode_json( {
                            material_json_path => $self->url_for(
                                conf->get( qw( material json path ) )
                            ),
                        } ), '' ),
                        samesite => 'Strict',
                    }) unless ( $c->req->cookie('quizsage_info') );
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
        $c->info( 'Login required but not yet met: ' . $c->req->url->to_string );
        $c->flash( memo => {
            class   => 'error',
            message => 'Login required for the previously requested resource',
        } );
        $c->redirect_to('/');
        return 0;
    } );

    $users->any('/user/profile')->to( 'user#account', account_action_type => 'profile' );
    $users->any('/user/logout')->to('user#logout');

    $users->any( '/memory/' . $_ )->to( 'memory#' . $_ ) for ( qw( memorize review_setup review state ) );

    $users->any('/meet/passwd')->to('meet#passwd');
    $users
        ->any( '/meet/:meet_id/board/:room_number' => [ format => ['json'] ] )
        ->to( 'meet#board', format => undef );
    $users->any( '/meet/:meet_id/' . $_ )->to( 'meet#' . $_ ) for ( qw( state roster distribution stats ) );

    $users->any(
        '/season/:season_id/meet/:meet_id/:meet_action_type',
        [ meet_action_type => [ qw( edit delete ) ] ],
    )->to('season#meet');
    $users->any('/season/:season_id/meet/add')->to( 'season#meet', meet_action_type => 'add' );

    $users->any( '/season/:season_id/' . $_ )->to( 'season#' . $_ ) for ( qw( delete stats ) );
    $users->any($_)->to('season#record') for (
        '/season/:season_id/edit',
        '/season/create',
    );
    $users->any('/season/admin')->to('season#admin');

    $users->any(
        '/:setup_type' => [ setup_type => [ qw(
            memory/memorize/setup
            drill/setup
            quiz/pickup/setup
            reference/lookup/setup
            reference/generator/setup
        ) ] ]
    )->to('main#setup');

    $users->any("/label/$_")->to("label#$_") for ( qw( tester editor ) );

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

    $users->any('/reference/lookup/:material_json_id')->to( 'reference#lookup', material_json_id => undef );
    $users->any('/reference/generator')->to('reference#generator');

    $all->any('/')->to('main#home');
    $all->any( '/set/:type/:name' => [ type => [ qw( theme style ) ] ] )->to('main#set');
    $all->any('/download')->to('main#download');
    $all
        ->any( '/download/:shard' => [ name => [ keys conf->get( qw( database shards ) )->%* ] ] )
        ->to('main#download');

    $all->any("/user/$_")->to("user#$_") for ( qw( forgot_password login ) );
    $all->any('/user/create')->to( 'user#account', account_action_type => 'create' );
    $all->any("/user/$_/:user_id/:user_hash")->to("user#$_") for ( qw( verify reset_password ) );

    $all->any( '/docs/*name' => { name => 'index.md' } => sub ($c) {
        $c->document( 'docs/' . $c->stash('name') );
        $c->stash( docs_nav => $c->docs_nav( 'docs', 'md', 'Documentation' ) );

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
