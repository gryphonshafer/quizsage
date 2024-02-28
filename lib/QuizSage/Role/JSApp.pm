package QuizSage::Role::JSApp;

use exact -role;

with 'QuizSage::Role::Data';

sub js_app_names ($self) {
    my $conf = $self->dataload('config/js_apps.yaml');
    return [
        sort {
            $a->{id} eq 'default' && -1 or
            $b->{id} eq 'default' &&  1 or
            $a->{name} cmp $b->{name}
        }
        map { +{ id => $_, name => $conf->{$_}{name} } } keys $conf->%*
    ];
}

sub js_app_config ( $self, $app, $id = undef ) {
    my $apps_conf = $self->dataload('config/js_apps.yaml');
    my $app_conf  = $apps_conf->{
        $id // ( ( $self->can('data') and $self->data ) ? $self->data->{js_apps_id} : undef ) // 'default'
    }{apps}{$app};

    while ( my $extends = delete $app_conf->{extends} ) {
        my $base = $apps_conf->{$extends}{apps}{$app};

        my $merge;
        $merge = sub ( $base, $ext ) {
            if ( ref $base eq 'HASH' ) {
                for my $key ( keys %$ext ) {
                    if ( ref $base->{$key} ) {
                        $merge->( $base->{$key}, $ext->{$key} );
                    }
                    else {
                        $base->{$key} = $ext->{$key};
                    }
                }
            }
            elsif ( ref $base eq 'ARRAY' ) {
               @$base = @$ext;
            }
        };
        $merge->( $base, $app_conf );

        $app_conf = $base;
    }

    return $app_conf;
}

1;

=head1 NAME

QuizSage::Role::JSApp

=head1 SYNOPSIS

    package Package;

    use exact -class;

    with 'QuizSage::Role::JSApp';

=head1 DESCRIPTION

This role provides some methods to support Javascript applications defined by
a configuration file located at: C<config/js_apps.yaml>.

The reason this exists is so that we can define in the configuration file
application settings like C<importmap> details per application and support
inheritance between setting blocks. For example:

    ---
    default:
        name: Christian Bible Quizzing (CBQ)
        apps:
            app_name:
                module:
                  - vue/apps/app_name
                importmap:
                    name/used/in/imports     : actual/path/to/file
                    name/also_used/in/imports: actual/path/to/other_file
    aubq:
        name: Alternate Universe Bible Quizzing (AUBQ)
        apps:
            app_name:
                extends: default
                importmap:
                    name/used/in/imports: actual/path/to/alternate_file

=head1 METHODS

=head2 js_app_names

Return a list of Javascript application sets defined in the configuration file,
sorted by name with the "default" ID first.

    my $arrayref_of_hashes = $obj->js_app_names;
    say $arrayref_of_hashes->[0]{id}; # should be "default"

The hashrefs here returned contain an C<id> key and C<name> key.

=head2 js_app_config

Return the configuration data for a Javascript application based on an
application name and optional set ID.

    my $conf_0 = $obj->js_app_config('quiz');
    my $conf_1 = $obj->js_app_config( 'quiz', 'default' );

=head1 WITH ROLE

L<QuizSage::Role::Data>.
