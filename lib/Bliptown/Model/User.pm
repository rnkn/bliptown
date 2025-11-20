package Bliptown::Model::User;
use Mojo::Base -base;
use Mojo::Util qw(secure_compare);
use Crypt::Bcrypt qw(bcrypt bcrypt_check);
use MIME::Base32;
use Authen::OATH;

has 'sqlite';

sub create_user {
	my ($self, $args) = @_;
	my $password_hash = bcrypt($args->{password}, '2b', 12, $ENV{BLIPTOWN_SALT});
	my @base64_set = (0 .. 9, 'a' .. 'z', 'A' .. 'Z', '+', '/');
	my $rand_str = join '', map $base64_set[rand @base64_set], 0 .. 21;
	my $secret = encode_base32 $rand_str;
	$self->sqlite->db->insert(
		'users', {
			username => $args->{username},
			email => $args->{email},
			password_hash => $password_hash,
			totp_secret => $secret,
		}
	);
}

sub read_user {
    my ($self, $args) = @_;
	my $key = $args->{key};
	return unless $key;

	my $user = $self->sqlite->db->select(
		'users', undef, { $key => $args->{$key} }
	)->hash;
	return $user if $user;
	return;
}

sub update_user {
	my ($self, $args) = @_;
	my %values;
	my @keys_null = qw(custom_domain);
	my @keys_not_null = qw(email);
	my @keys_int = qw(create_backups sort_new);
	foreach my $key (keys %$args) {
		if (grep { $key eq $_ } @keys_null) {
			my $v = $args->{$key} || 'NULL';
			$values{$key} = $v;
		}
		if (grep { $key eq $_ } @keys_not_null) {
			my $v = $args->{$key};
			$values{$key} = $v if $v;
		}
		if (grep { $key eq $_ } @keys_int) {
			my $v = $args->{$key} // 0;
			$values{$key} = $v;
		}
	};
	my $new_password = $args->{new_password};
	if ($new_password) {
		my $password_hash = bcrypt($new_password, '2b', 12, $ENV{BLIPTOWN_SALT});
		$values{password_hash} = $password_hash;
	};
    my $success = $self->sqlite->db->update(
		'users', \%values, { username => $args->{username} }
	);
	return 1 if $success;
}

sub delete_user {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
    $self->sqlite->db->delete(
		'users', { username => $username }
	);
	return 1;
}

sub authenticate_user {
    my ($self, $args) = @_;
    my $user = $self->read_user(
		{ key => 'username', username => $args->{username} }
	);
	return unless $user;
    my $hash = $user->{password_hash};
	unless ($hash && bcrypt_check($args->{password}, $hash)) {
		return;
    }
	my $secret = decode_base32 $user->{totp_secret};
	my $oath = Authen::OATH->new;
	unless ($secret && secure_compare $oath->totp($secret), $args->{totp}) {
		return;
    }
    return 1;
}

return 1;
