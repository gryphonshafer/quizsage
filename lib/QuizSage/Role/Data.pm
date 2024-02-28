package QuizSage::Role::Data;

use exact -role;
use Mojo::JSON 'decode_json';
use Mojo::File 'path';
use YAML::XS qw( LoadFile Load Dump );

with 'Omniframe::Role::Conf';

sub deepcopy ( $self, @items ) {
    return unless (@items);
    my @results = map { Load( Dump($_) ) } @items;
    return ( @results == 1 ) ? $results[0] : ( wantarray ) ? @results : \@results;
}

sub dataload ( $self, $file ) {
    my $path = path( $self->conf->get( qw( config_app root_dir ) ) . '/' . $file );
    return
        ( $file =~ /\.yaml$/i ) ? LoadFile($path)             :
        ( $file =~ /\.json$/i ) ? decode_json( $path->slurp ) : $path->slurp;
}

1;

=head1 NAME

QuizSage::Role::Data

=head1 SYNOPSIS

    package Package;

    use exact -class;

    with 'QuizSage::Role::Data';

=head1 DESCRIPTION

This role provides some "data" methods, that is to say, common methods for
loading or handling data.

=head1 METHODS

=head2 deepcopy

This method expects any number of data objects as input and will create "deep
copies" of them, meaning any internal references will be replicated instead of
maintained, allowing for alteration of said reference content without infecting
the original data objects.

    my $deep_copy = $obj->deepcopy($original_data);

If multiple inputs are provided, the context of the call will cause either an
array or arrayref to be returned.

    my $deep_copies = $obj->deepcopy( $data_obj_0, $data_obj_1 );
    my @deep_copies = $obj->deepcopy( $data_obj_0, $data_obj_1 );

=head2 dataload

This method will load a YAML or JSON file from within the project's directory
tree based on the realtive path to the file from the projects's root directory.
The method will return the data from the source file.

    my $decoded_season_data =
        $obj->dataload('config/meets/defaults/season.yaml');
    my $decoded_material_data =
        $obj->dataload('static/json/material/d8dc04b8c7ed6bc4.json');

=head1 WITH ROLE

L<Omniframe::Role::Conf>.
