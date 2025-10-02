package QuizSage::Control::Main;

use exact -conf, 'Mojolicious::Controller';
use Mojo::File 'path';
use QuizSage::Model::Label;
use QuizSage::Model::Memory;
use QuizSage::Model::Quiz;
use QuizSage::Model::Season;
use QuizSage::Model::User;
use QuizSage::Util::Material qw( material_json synonyms_of_term );

sub home ($self) {
    $self->stash(
        seasons => QuizSage::Model::Season->new->seasons,
    ) if ( $self->stash('user') );
}

sub set ($self) {
    $self->session( $self->param('type') => $self->param('name') );

    if ( my $user = $self->stash('user') ) {
        $user->data->{settings}{ $self->param('type') } = $self->param('name');
        $user->save;
    }

    $self->redirect_to( $self->req->headers->referer );
}

my $root_dir = conf->get( qw( config_app root_dir ) );
my $base     = path($root_dir);

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
    my $quiz_defaults = conf->get('quiz_defaults');
    my $user_settings = $user->data->{settings}{ $self->stash('setup_label') }  // {};

    my $settings;
    $settings->{$_} = $self->param($_) // $user_settings->{$_} // $quiz_defaults->{$_}
        for (
            ( $self->stash('setup_label') eq 'pickup_quiz' )
                ? ( qw( bible roster_data material_label ) ) :
            ( $self->stash('setup_label') eq 'ref_gen' )
                ? ( qw( bible material_label ) ) : ('material_label')
        );

    my $setup_error_messages = {
        label =>
            'There was an error in parsing the label/description input. ' .
            'These sorts of things are usually due to ' .
            'mistyped translation acronyms, unrecognized book names, ' .
            'syntax error, or extraneous text. ' .
            'Check your input and consider consulting the ' .
            '<a href="' . $self->url_for('/docs/material_labels.md') .
                '">material labels documentation</a>.',
        not_multi_chapter =>
            'It appears the material label/description does not include multiple chapters. ' .
            'Running quizzes or drills requires multiple chapters. ' .
            'If you only want to quiz or drill on a single chapter, consult the ' .
            '<a href="' . $self->url_for('/docs/material_labels.md') .
                '">material labels documentation</a> ' .
            'for instructions on how to setup your label/description.',
    };

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

        $settings->{material_label} .= ' ' . ( $settings->{bible} // $quiz_defaults->{bible} )
            if ( not $parsed_label->{bibles} );

        my $material_label_input = $settings->{material_label};
        $settings->{material_label} = $label->canonicalize( $settings->{material_label} );

        unless ( $settings->{material_label} ) {
            $self->notice( 'Label error: ' . $material_label_input );
            $self->stash(
                memo => {
                    class   => 'error',
                    message => $setup_error_messages->{label},
                },
                material_label => $material_label_input,
            );
        }
        elsif (
            (
                $self->stash('setup_label') eq 'queries_drill' or
                $self->stash('setup_label') eq 'pickup_quiz' and $self->param('generate_queries')
            )
            and not $label->is_multi_chapter( $settings->{material_label} )
        ) {
            $self->stash(
                memo => {
                    class   => 'error',
                    message => $setup_error_messages->{not_multi_chapter},
                },
                material_label => $material_label_input,
            );
        }
        else {
            if ( $self->stash('setup_label') eq 'ref_gen' ) {
                $settings->{$_} = ( $self->req->param($_) ) ? 1 : 0 for ( qw(
                    cover
                    reference
                    concordance
                    mark_unique
                ) );

                $settings->{$_} = ( $self->req->param($_) ) ? 0 + $self->req->param( $_ . '_number' ) : 0
                    for ( qw( whole chapter phrases ) );

                $settings->{$_} = $self->req->param($_) for ( qw(
                    reference_scope
                    concordance_scope
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

                $settings->{labels_to_markup} = ( $self->req->param('labels_to_markup') )
                    ? join( "\n", $label->identify_aliases( $self->req->param('labels_to_markup') )->@* )
                    : '';
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
    }
    elsif ( $self->stash('setup_label') eq 'pickup_quiz' and not $self->param('generate_queries') ) {
        try {
            my $quiz_id = QuizSage::Model::Quiz->new->pickup( $settings, $user )->id;
            $self->info( 'Pickup quiz generated: ' . $quiz_id );
            return $self->redirect_to( '/quiz/pickup/' . $quiz_id );
        }
        catch ($e) {
            $self->notice( 'Pickup quiz error: ' . $e );
            my $deat_e = deat $e;
            $self->stash(
                memo => {
                    class   => 'error',
                    message => (
                        (
                            $deat_e eq 'Must provide label' or
                            $deat_e eq 'Must supply at least 1 valid reference range' or
                            $deat_e eq 'Must have least 1 primary supported canonical Bible acronym'
                        )
                            ? $setup_error_messages->{label} :
                        ( $deat_e eq 'Material must be multi-chapter' )
                            ? $setup_error_messages->{not_multi_chapter}
                            : 'Pickup quiz settings error: ' . $deat_e
                    ),
                },
                map { $_ => $settings->{$_} } qw(
                    material_label
                    bible
                    roster_data
                ),
            );
        }
    }
}

sub download ($self) {
    $self->stash( shards => conf->get( qw( database shards ) ) );
    if ( my $shard = $self->param('shard') ) {
        my $file = $base->child( conf->get( qw( database shards ), $shard, 'file' ) );

        $self->res->headers->header(@$_) for (
            [ 'Content-Type'        => 'application/x-sqlite'                           ],
            [ 'Content-Disposition' => 'attachment; filename="' . $file->basename . '"' ],
        );

        $self->res->body( $file->slurp );
        $self->rendered;
    }
}

sub synonyms ($self) {
    my $settings = {
        map { $_ => $self->param($_) }
        grep { defined $self->param($_) } qw(
            case_sensitive
            skip_substring_search
            skip_term_splitting
            minimum_verity
            direct_lookup
            reverse_lookup
        )
    };
    for ( qw(
        ignored_types
        special_types
    ) ) {
        $settings->{$_} = $self->every_param($_) if ( defined $self->param($_) );
    }

    my $matches = [];
    try {
        $matches = synonyms_of_term( $self->param('term'), $settings );
    }
    catch ($e) {
        $self->notice( 'Synonyms error: ' . deat $e );
    }

    $self->render( json => $matches );
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

=head2 setup

This method handles setting up settings for various other parts of QuizSage.

=head2 download

This method supports the download page.

=head2 synonyms

This method requires a C<term> parameter be provided, which is a word, portion
of a word, or a string of space-separated words. The C<synonyms_of_term> method
from L<QuizSage::Util::Material> gets called, and the matches are returned as
JSON.

You can optionally also set any settings via parameters.

=head1 INHERITANCE

L<Mojolicious::Controller>.
