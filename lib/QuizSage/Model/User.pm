package QuizSage::Model::User;

use exact -class, -conf;
use Email::Address;
use Mojo::JSON qw( encode_json decode_json );
use Mojo::Util qw( b64_encode b64_decode );
use Omniframe::Class::Email;
use Omniframe::Util::Bcrypt 'bcrypt';
use Omniframe::Util::Crypt qw( encrypt decrypt );
use QuizSage::Model::Meet;

with 'Omniframe::Role::Model';

class_has active => 1;

before 'create' => sub ( $self, $params ) {
    $params->{active} //= 0;
};

sub freeze ( $self, $data ) {
    if ( $self->is_dirty( 'email', $data ) or not exists $data->{email} ) {
        my ($address) = Email::Address->parse( $data->{email} );
        croak('Email not provided properly') unless ($address);
        $data->{email} = lc $address->address;
    }

    my $min_passwd_length = conf->get('min_passwd_length');
    if ( $self->is_dirty( 'passwd', $data ) ) {
        croak("Password supplied is not at least $min_passwd_length characters in length")
            unless ( length $data->{passwd} >= $min_passwd_length );
        $data->{passwd} = bcrypt( $data->{passwd} );
    }

    if ( $self->is_dirty( 'phone', $data ) ) {
        $data->{phone} =~ s/\D+//g;
        croak('Phone supplied is not at least 10 digits in length') unless ( length $data->{phone} >= 10 );
    }

    $data->{settings} = encode_json( $data->{settings} );
    undef $data->{settings} if ( $data->{settings} eq '{}' or $data->{settings} eq 'null' );

    return $data;
}

sub thaw ( $self, $data ) {
    $data->{settings} = ( defined $data->{settings} ) ? decode_json( $data->{settings} ) : {};
    return $data;
}

sub _encode_token ($user_id) {
    return b64_encode( encrypt( encode_json( [ $user_id, time ] ) ) );
}

sub _decode_token ($token) {
    my $data;
    try {
        $data = decode_json( decrypt( b64_decode($token) ) );
    }
    catch ($e) {}

    return (
        $data and $data->[0] and $data->[1] and
        $data->[1] < time + conf->get('token_expiration')
    ) ? $data->[0] : undef;
}

sub send_email ( $self, $type, $url ) {
    croak('User object not data-loaded') unless ( $self->id );
    push( @{ $url->path->parts }, _encode_token( $self->id ) );

    return Omniframe::Class::Email->new( type => $type )->send({
        to   => sprintf( '%s %s <%s>', map { $self->data->{$_} } qw( first_name last_name email ) ),
        data => {
            user => $self->data,
            url  => $url->to_abs->to_string,
        },
    });
}

sub verify ( $self, $token ) {
    my $user_id = _decode_token($token);
    return unless ($user_id);

    $self->dq->sql('UPDATE user SET active = 1 WHERE user_id = ?')->run($user_id);
    return $user_id;
}

sub reset_password ( $self, $token, $new_password ) {
    my $min_passwd_length = conf->get('min_passwd_length');
    croak("Password supplied is not at least $min_passwd_length characters in length")
        unless ( length $new_password >= $min_passwd_length );

    my $user_id = _decode_token($token);
    return unless ($user_id);

    $self->dq->sql('UPDATE user SET passwd = ? WHERE user_id = ?')->run( bcrypt($new_password), $user_id );

    return $user_id;
}

sub login ( $self, $email, $passwd ) {
    $self->load({
        email  => lc($email),
        passwd => bcrypt($passwd),
        active => 1,
    });

    $self->save({ last_login => \q/( STRFTIME( '%Y-%m-%d %H:%M:%f', 'NOW', 'LOCALTIME' ) )/ });

    return $self;
}

sub qm_auth ( $self, $meet ) {
    try {
        $meet = QuizSage::Model::Meet->new->load($meet) unless ( $meet isa QuizSage::Model::Meet );
        return (
            $meet->data->{passwd} and
            $self->data->{settings}{meet_passwd} and
            $meet->data->{passwd} eq $self->data->{settings}{meet_passwd}
        ) ? 1 : 0;
    }
    catch ($e) {
        return undef;
    }
}

sub active_users_list ($self) {
    return [
        map {
            $_->{first_name} = ucfirst $_->{first_name};
            $_->{last_name}  = ucfirst $_->{last_name};
            $_->{email}      = lc $_->{email};
            $_->{label}      = $_->{first_name} . ' ' . $_->{last_name} . ' (' . $_->{email} . ')';
            $_;
        } $self->dq->sql(q{
            SELECT user_id, first_name, last_name, email
            FROM user
            WHERE active
            ORDER BY 2, 3, 4
        })->run->all({})->@*
    ];
}

sub is_app_admin ( $self, $user_id = undef ) {
    return $self->dq->sql(q{
        SELECT COUNT(*)
        FROM administrator
        WHERE user_id = ? AND season_id IS NULL and meet_id IS NULL
    })->run( $user_id // $self->id // 0 )->value
}

1;

=head1 NAME

QuizSage::Model::User

=head1 SYNOPSIS

    use QuizSage::Model::User;

    my $user_id = QuizSage::Model::User->new->create({
        email      => 'email',
        passwd     => 'passwd',
        first_name => 'first_name',
        last_name  => 'last_name',
        phone      => 'phone', # optional
        settings   => {},      # optional
    })->id;

    my $user = QuizSage::Model::User->new->login( 'username', 'passwd' );

    use Mojo::URL;
    $user->send_email( 'verify_email',    Mojo::URL->new );
    $user->send_email( 'forgot_password', Mojo::URL->new );

    $user->verify( 42, 'a1b2c3d4' );
    $user->reset_password( 42, 'a1b2c3d4', 'new_password' );

    my $logged_in_user = QuizSage::Model::User->new->login( 'username', 'passwd' );

    $user->qm_auth(42);
    $user->qm_auth( QuizSage::Model::Meet->new->load(42) );

=head1 DESCRIPTION

This class is the model for user objects. A user is an individual person that
uses the application.

=head1 EXTENDED METHOD

=head2 create

Extended from L<Omniframe::Role::Model>, this method requires C<email>,
C<passwd>, C<first_name>, and C<last_name> values.

This method can optionally accept a C<settings> hashref.

=head1 OBJECT METHODS

=head2 freeze

Likely not used directly, this method is provided such that
L<Omniframe::Role::Model> will ensure a valid email address, which is checked
via L<Email::Address>, and and a phone number.

Also, it will C<bcrypt> passwords before storing them in the database. It
expects a hashref of values and will return a hashref of values with the
C<passwd> crypted.

Also, C<freeze> will JSON-encode the C<settings> hashref.

=head2 thaw

Likely not used directly, C<thaw> will JSON-decode the C<settings> hashref.

=head2 send_email

This method will send an email to the user of a particular type. It requires an
email template for the type. This method must be provided the type and a loaded
L<Mojo::URL> object to redirect the user back to.

    use Mojo::URL;
    $user->send_email( 'verify_email',    Mojo::URL->new );
    $user->send_email( 'forgot_password', Mojo::URL->new );

=head2 verify

Response to a verify response from a verify email. Requires a user ID and a
user hash, which is the first set of characters from the user's encrypted
password.

    $user->verify( 42, 'a1b2c3d4' );

=head2 reset_password

Handle a reset password request (from an email). Requires a user ID, a
user hash, which is the first set of characters from the user's encrypted
password, and the new password to set.

    $user->reset_password( 42, 'a1b2c3d4', 'new_password' );

=head2 login

This method requires a username and password string inputs. It will then attempt
to find and login the user. If successful, it will return a loaded user object.

    my $logged_in_user = QuizSage::Model::User->new->login( 'username', 'passwd' );

=head2 qm_auth

This method verifies the user is authorized to be a quiz magistrate for a meet.
It requires the meet ID or a meet object.

    $user->qm_auth(42); # meet ID
    $user->qm_auth( QuizSage::Model::Meet->new->load(42) ); # meet object

=head2 active_users_list

This method will return an arrayref of hashrefs with C<user_id>, C<first_name>,
C<last_name>, and C<email> that match active users. It will also include a
C<label> field using data from other fields.

=head2 is_app_admin

This method will return a boolean value about whether the user is an
application-level administrator, meaning they have a record in the
C<administrator> table with no reference to season or meet.

=head1 WITH ROLE

L<Omniframe::Role::Model>.
