package QuizSage::Control;

use exact 'Omniframe::Control';

sub startup ($self) {
    $self->setup;
    $self->routes->any( '/*null' => { null => undef } => sub ($c) {
        $c->stash(
            package => __PACKAGE__,
            now     => scalar(localtime),
            copy    => "\xa9",
            input   => $c->param('input'),
        );
        $c->render( template => 'example/index' );
    } );
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
