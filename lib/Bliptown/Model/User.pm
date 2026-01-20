package Bliptown::Model::User;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);
use Crypt::Bcrypt qw(bcrypt bcrypt_check);

has 'sqlite';
has 'totp';
has 'domain_list';

sub create_user {
	my ($self, $args) = @_;
	my $salt = substr(generate_secret, 0, 16);
	my $password_hash = bcrypt($args->{password}, '2b', 12, $salt);
	my $totp_secret = $self->totp->create_secret;
	$self->sqlite->db->insert(
		'users', {
			username => $args->{username},
			email => $args->{email},
			password_hash => $password_hash,
			totp_secret => $totp_secret,
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
	$user->{custom_domain} = '' if $user->{custom_domain} &&
		$user->{custom_domain} eq 'NULL';
	return $user if $user;
	return;
}

sub update_user {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my %values;
	my @keys_null = qw(custom_domain);
	my @keys_not_null = qw(email totp_secret);
	my @keys_int = qw(create_backups);
	foreach my $key (keys %$args) {
		if (grep { $key eq $_ } @keys_null) {
			my $v = $args->{$key} || undef;
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
		my $salt = substr(generate_secret, 0, 16);
		my $password_hash = bcrypt($new_password, '2b', 12, $salt);
		$values{password_hash} = $password_hash;
	};
	my $ok = $self->sqlite->db->update(
		'users', \%values, { username => $username }
	);
	warn unless $ok;
	return 1;
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
	my $username = $args->{username};
	my $user = $self->read_user(
		{ key => 'username', username => $username }
	);
	return unless $user;
	my $hash = $user->{password_hash};
	return unless $hash;
	return unless bcrypt_check($args->{password}, $hash);

	return 1 if $username eq 'demo';

	my $secret = $user->{totp_secret};
	my $totp = $args->{totp};
	my $totp_check = $self->totp->read_totp({ totp_secret => $secret });
	unless ($self->totp->check_totp(
				{ totp => $totp, totp_check => $totp_check }
			)) {
		return;
	}
	return 1;
}

return 1;
