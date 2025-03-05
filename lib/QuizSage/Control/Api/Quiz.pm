package QuizSage::Control::Api::Quiz;

use exact -conf, 'Mojolicious::Controller';
use Mojo::File 'path';
use Mojo::JSON 'decode_json';
use QuizSage::Model::Quiz;
use QuizSage::Util::Material 'material_json';
use Omniframe;
use Omniframe::Class::Javascript;

my $root_dir = conf->get( qw( config_app root_dir ) );
my $ocjs     = Omniframe::Class::Javascript->new(
    basepath  => $root_dir . '/static/js',
    importmap => Omniframe->with_roles('QuizSage::Role::JSApp')->new->js_app_config(
        'quiz',
        conf->get('quiz_defaults')->{js_apps_id},
    )->{importmap},
);

sub distribution ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi =>
        $ocjs->run(
            $root_dir . '/ocjs/lib/Model/Meet/distribution.js',
            {
                bibles      => $self->every_param('bibles'),
                teams_count => $self->param('teams_count'),
            },
        )->[0][0]
    );
}

sub verses ($self) {
    $self->openapi->valid_input or return;
    $self->render( openapi =>
        $ocjs->run(
            $root_dir . '/ocjs/lib/Model/Quiz/material.js',
            {
                count         => $self->param('count'),
                material_data => decode_json(
                    path(
                        material_json(
                            label => $self->param('label'),
                            user  => $self->session('user_id'),
                        )->{json_file}
                    )->slurp
                ),
            },
        )->[0][0]
    );
}

sub data ($self) {
    $self->openapi->valid_input or return;
    my $data;
    try {
        $data = QuizSage::Model::Quiz->new->load( $self->param('quiz_id') )->data;
    }
    catch ($e) {}
    $self->render( openapi => $data );
}

1;

=head1 NAME

QuizSage::Control::Api::Quiz

=head1 DESCRIPTION

This class is a subclass of L<Mojolicious::Controller> and provides handlers
for "Quizzes" API calls.

=head1 METHODS

=head2 distribution

This endpoint will return an array of a quiz distribution.

=head2 verses

This endpoint will use a material label and return an array of verse objects
that could be used for a quiz.

=head2 data

Given a quiz ID, this endpoint will return the quiz data (assuming that quiz
exists).

=head1 INHERITANCE

L<Mojolicious::Controller>.
