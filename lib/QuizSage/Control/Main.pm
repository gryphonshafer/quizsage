package QuizSage::Control::Main;

use exact 'Mojolicious::Controller';
use GD;
use Mojo::File 'path';
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;
use QuizSage::Model::User;
use QuizSage::Util::Material 'material_json';

sub home ($self) {
    $self->stash( seasons => QuizSage::Model::Season->new->seasons ) if ( $self->stash('user') );
}

sub set ($self) {
    $self->session( $self->param('type') => $self->param('name') );

    if ( my $user = $self->stash('user') ) {
        $user->data->{settings}{ $self->param('type') } = $self->param('name');
        $user->save;
    }

    $self->redirect_to( $self->req->headers->referer );
}

my $conf     = QuizSage::Model::Season->new->conf;
my $root_dir = $conf->get( qw( config_app root_dir ) );
my $base     = path($root_dir);

{
    my $captcha = $conf->get('captcha');
    my ($ttf)   = glob( $base->to_string . '/' . $captcha->{ttf} );
    ($ttf)      = glob( $base->child( $conf->get('omniframe') )->to_string . '/' . $captcha->{ttf} )
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

sub setup ($self) {
    $self->stash( setup_label =>
        ( $self->param('setup_type') eq 'memory/memorize/setup'     ) ? 'memorize'      :
        ( $self->param('setup_type') eq 'drill/setup'               ) ? 'queries_drill' :
        ( $self->param('setup_type') eq 'quiz/pickup/setup'         ) ? 'pickup_quiz'   :
        ( $self->param('setup_type') eq 'reference/lookup/setup'    ) ? 'lookup'        :
        ( $self->param('setup_type') eq 'reference/generator/setup' ) ? 'ref_gen'       : undef
    );

    my $user = $self->stash('user');
    if ( $self->stash('setup_label') eq 'memorize' and $self->session('become') ) {
        $user = QuizSage::Model::User->new->load( $self->session('become') );
        $self->stash( become_user => $user );
    }

    $self->stash(
        recent_pickup_quizzes => QuizSage::Model::Quiz->new->recent_pickup_quizzes( $user->id ),
    ) if ( $self->stash('setup_label') eq 'pickup_quiz' );

    my $label         = QuizSage::Model::Label->new( user_id => $user->id );
    my $quiz_defaults = $label->conf->get('quiz_defaults');
    my $user_settings = $user->data->{settings}{ $self->stash('setup_label') }  // {};

    my $settings;
    $settings->{$_} = $self->param($_) // $user_settings->{$_} // $quiz_defaults->{$_}
        for (
            ( $self->stash('setup_label') eq 'pickup_quiz' )
                ? ( qw( bible roster_data material_label ) ) :
            ( $self->stash('setup_label') eq 'ref_gen' )
                ? ( qw( bible material_label ) ) : ('material_label')
        );

    unless ( $self->param('material_label') or $self->param('roster_data') ) {
        $self->stash(
            label_aliases => $label->aliases,
            bibles        => $label
                ->dq('material')
                ->get( 'bible', undef, undef, { order_by => 'acronym' } )
                ->run->all({}),
            %$settings,
        );
    }
    elsif (
        $self->stash('setup_label') eq 'memorize' or
        $self->stash('setup_label') eq 'queries_drill' or
        $self->stash('setup_label') eq 'pickup_quiz' and $self->param('generate_queries') or
        $self->stash('setup_label') eq 'lookup' or
        $self->stash('setup_label') eq 'ref_gen'
    ) {
        my $parsed_label = $label->parse( $settings->{material_label} );

        $settings->{material_label} .= ' ' . $settings->{bible}
            if ( not $parsed_label->{bibles} and $settings->{bible} );
        $settings->{material_label} = $label->canonicalize( $settings->{material_label} );

        if ( $self->stash('setup_label') eq 'ref_gen' ) {
            $settings->{cover}     = ( $self->req->param('cover')     ) ? 1 : 0;
            $settings->{reference} = ( $self->req->param('reference') ) ? 1 : 0;
            $settings->{$_}        = ( $self->req->param($_) ) ? 0 + $self->req->param( $_ . '_number' ) : 0
                for ( qw( whole chapter phrases ) );

            $settings->{$_} = $self->req->param($_) for ( qw(
                page_width
                page_height
                page_right_margin_left
                page_right_margin_right
                page_right_margin_top
                page_right_margin_bottom
                page_left_margin_left
                page_left_margin_right
                page_left_margin_top
                page_left_margin_bottom
            ) );
        }

        $user->data->{settings}{ $self->stash('setup_label') } = $settings;
        $user->save;

        return $self->redirect_to(
            ( $self->stash('setup_label') eq 'memorize'      ) ? '/memory/memorize'     :
            ( $self->stash('setup_label') eq 'queries_drill' ) ? '/drill'               :
            ( $self->stash('setup_label') eq 'pickup_quiz'   ) ? '/queries'             :
            ( $self->stash('setup_label') eq 'ref_gen'       ) ? '/reference/generator' :
            ( $self->stash('setup_label') eq 'lookup'        ) ? '/reference/lookup/' . material_json (
                label => $settings->{material_label},
                user  => $user->id,
            )->{id} : '/'
        );
    }
    elsif ( $self->stash('setup_label') eq 'pickup_quiz' and not $self->param('generate_queries') ) {
        try {
            my $quiz_id = QuizSage::Model::Quiz->new->pickup( $settings, $user )->id;
            $self->info( 'Pickup quiz generated: ' . $quiz_id );
            return $self->redirect_to( '/quiz/pickup/' . $quiz_id );
        }
        catch ($e) {
            $self->notice( 'Pickup quiz error: ' . $e );
            $self->flash( message => 'Pickup quiz settings error: ' . $e );
            return $self->redirect_to('/quiz/pickup/setup');
        }
    }
}

sub download ($self) {
    $self->stash( shards => $conf->get( qw( database shards ) ) );
    if ( my $shard = $self->param('shard') ) {
        my $file = $base->child( $conf->get( qw( database shards ), $shard, 'file' ) );

        $self->res->headers->header(@$_) for (
            [ 'Content-Type'        => 'application/x-sqlite'                           ],
            [ 'Content-Disposition' => 'attachment; filename="' . $file->basename . '"' ],
        );

        $self->res->body( $file->slurp );
        $self->rendered;
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

=head2 setup

This method handles setting up settings for various other parts of QuizSage.

=head2 download

This method supports the download page.

=head1 INHERITANCE

L<Mojolicious::Controller>.
