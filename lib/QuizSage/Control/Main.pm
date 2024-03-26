package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Season;
use GD;
use Mojo::File 'path';

sub home ($self) {
    $self->stash( active_seasons => QuizSage::Model::Season->new->active_seasons )
        if ( $self->stash('user') );
}

sub set ($self) {
    $self->session( $self->param('type') => $self->param('name') );

    if ( my $user = $self->stash('user') ) {
        $user->data->{settings}{ $self->param('type') } = $self->param('name');
        $user->save;
    }

    $self->redirect_to( $self->req->headers->referer );
}

{
    my $conf     = QuizSage::Model::Season->new->conf;
    my $captcha  = $conf->get('captcha');
    my $root_dir = $conf->get( qw( config_app root_dir ) );
    my $base     = path($root_dir);
    my ($ttf)    = glob( $base->to_string . '/' . $captcha->{ttf} );
    ($ttf)       = glob( $base->child( $conf->get('omniframe') )->to_string . '/' . $captcha->{ttf} )
        unless ($ttf);

    sub captcha ($self) {
        srand;

        my $sequence = int( rand( 10_000_000 - 1_000_000 ) ) + 1_000_000;
        my $display  = $sequence;

        $display =~ s/^(\d{2})(\d{3})/$1-$2-/;
        $display =~ s/(.)/ $1/g;

        my $image  = GD::Image->new( $captcha->{width}, $captcha->{height} );
        my $rotate = rand() / $captcha->{rotation} * ( ( rand() > 0.5 ) ? 1 : -1 );

        $image->fill( 0, 0, $image->colorAllocate( map { eval $_ } $captcha->{background}->@* ) );
        $image->stringFT(
            $image->colorAllocate( map { eval $_ } $captcha->{text_color}->@* ),
            $ttf,
            $captcha->{size},
            $rotate,
            $captcha->{x},
            $captcha->{y_base} + $rotate * $captcha->{y_rotate},
            $display,
        );

        for ( 1 .. 10 ) {
            my $index = $image->colorAllocate( map { eval $_ } $captcha->{noise_color}->@* );
            $image->setPixel( rand( $captcha->{width} ), rand( $captcha->{width} ), $index )
                for ( 1 .. $captcha->{noise} );
        }

        $self->session( captcha => $sequence );
        return $self->render( data => $image->png(9), format => 'png' );
    }
}

1;

=head1 NAME

QuizSage::Control::Main

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Main" actions.

=head1 METHODS

=head2 home

Handler for the home page. The home page has a not-logged-in view and a
logged-in view that are substantially different.

=head2 set

This handler will set the C<type>-parameter-named session value to the C<name>
parameter value. If the user is logged in, this handler will also save the
the C<name> parameter value to the user's settings JSON under the
C<type>-parameter-named name. Finally, this handler will redirect back to the
referer.

=head2 captcha

This handler will automatically generate and return a captcha image consisting
of a text sequence. That text sequence will also be added to the session under
the name C<captcha>.

=head1 INHERITANCE

L<Mojolicious::Controller>.
