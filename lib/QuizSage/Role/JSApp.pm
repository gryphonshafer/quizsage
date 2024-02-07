package QuizSage::Role::JSApp;

use exact -role;

with 'QuizSage::Role::Data';

sub js_app_names ($self) {
    my $conf = $self->dataload('config/js_apps.yaml');
    return [
        sort {
            $a->{id} eq 'default' && -1 or
            $b->{id} eq 'default' && 1 or
            $a->{name} cmp $b->{name}
        }
        map { +{ id => $_, name => $conf->{$_}{name} } } keys $conf->%*
    ];
}

sub js_app_config ( $self, $app, $id = 'default' ) {
    my $apps_conf = $self->dataload('config/js_apps.yaml');
    my $app_conf  = $apps_conf->{ $id // 'default' }{apps}{$app};

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

This role provides some JSApp methods.

=head1 METHODS

=head2 js_app_config

=head2 js_app_names

=head1 WITH ROLE

L<QuizSage::Role::Data>.
