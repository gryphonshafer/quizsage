package QuizSage::Control::Label;

use exact 'Mojolicious::Controller';
use QuizSage::Model::Label;

sub tester ($self) {
    my $referrer = $self->param('referrer') // $self->req->headers->referrer;
    my $label    = QuizSage::Model::Label->new( user_id => $self->stash('user')->id );

    $self->stash(
        referrer      => $referrer,
        label_aliases => $label->aliases,
        bibles        => $label
            ->dq('material')
            ->get( 'bible', undef, undef, { order_by => 'acronym' } )
            ->run->all({}),
    );

    $self->stash(
        maybe canonical_label       => $label->canonicalize  ( $self->param('label') ),
        maybe canonical_description => $label->descriptionize( $self->param('label') ),
    ) if ( $self->param('label') );
}

sub editor ($self) {
    my $label = QuizSage::Model::Label->new( user_id => $self->stash('user')->id );

    if ( $self->param('id') and ( $self->param('action') // '' ) eq 'delete' ) {
        $label->load({
            label_id => $self->param('id'),
            user_id  => $self->stash('user')->id,
        })->delete;

        $self->redirect_to('/label/editor');
    }
    elsif ( $self->param('name') and $self->param('label') ) {
        my $parsed = $label->parse( $self->param('label') );
        delete $parsed->{bibles};

        my $data = {
            user_id => $self->stash('user')->id,
            public  => ( $self->param('public') ) ? 1 : 0,
            name    => $self->param('name'),
            label   => $label->format($parsed),
        };

        if ( not $data->{label} ) {
            $self->flash( memo => { class => 'error', message => 'Unable to parse the material label' } );
        }
        else {
            try {
                if ( not $self->param('id') ) {
                    $label->create($data);
                }
                else {
                    $label->load({
                        label_id => $self->param('id'),
                        user_id  => $self->stash('user')->id,
                    })->save($data);
                }
            }
            catch ($e) {
                $self->flash( memo => {
                    class   => 'error',
                    message => 'Failed to save label (likely due to a name conflict)',
                } );
            }
        }
        $self->redirect_to('/label/editor');
    }
    else {
        $self->stash(
            $label->load({
                label_id => $self->param('id'),
                user_id  => $self->stash('user')->id,
            })->data
        ) if ( $self->param('id') );

        $self->stash(
            label_aliases => [
                sort {
                    $a->{sort_name} cmp $b->{sort_name}
                }
                map {
                    $_->{sort_name} = lc $_->{name};
                    $_;
                }
                $label->every_data({ user_id => $self->stash('user')->id })->@*
            ],
        );
    }
}

sub fabricate ($self) {
    my $params       = $self->req->params->to_hash;
    my $first_button = delete $params->{first_button};

    $self->stash($params);

    if ( $first_button and ( $params->{range} or $params->{sizes} ) ) {
        my ( $range, $sizes, $lists ) = QuizSage::Model::Label->new->fabricate(
            $params->{range},
            $params->{sizes},
        );
        $self->stash(
            range => $range,
            sizes => join( ' ', @$sizes ),
            lists => $lists,
        );
    }
    elsif ( my @lists = sort { $a <=> $b } grep { /^\d+$/ } keys $params->%* ) {
        my $bible_ref = QuizSage::Model::Label->new->bible_ref;
        $self->stash(
            lists => [
                sort { $a->{size} <=> $b->{size} }
                map {
                    +{
                        refs => $bible_ref->clear->add_detail(0)->simplify(1)->in( $params->{$_} )->refs,
                        size => scalar(
                            $bible_ref->clear->add_detail(1)->simplify(0)
                                ->in( $params->{$_} )->as_verses->@*
                        ),
                    };
                } @lists
            ]
        );
    }
}

1;

=head1 NAME

QuizSage::Control::Label

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Label" actions.

=head1 METHODS

=head2 tester

This controller handles material label testing, where a user provides material
label/description input and gets back a canonical label and description.

=head2 editor

This controller handles editing material labels.

=head2 fabricate

This controller handles "fabricating" (or semi-automatically constructing)
material labels.

=head1 INHERITANCE

L<Mojolicious::Controller>.
