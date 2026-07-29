package Bliptown::Model::User;
use Mojo::Base -base;

has 'db';
has 'customer';

sub create_user {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my $email = $args->{email};

	my $customer = $self->customer->create_customer({
		username => $username,
		email => $email,
	});
	my $customer_id = $customer->{id};

	my $ok = $self->db->insert(
		'users', {
			username => $username,
			email => $email,
			customer_id => $customer_id,
		}
	);
	warn unless $ok;
	return $ok;
}

sub read_user {
	my ($self, $args) = @_;
	my $key = $args->{key};
	return unless $key;
	my $user_rec = $self->db->select(
		'users', undef, { $key => $args->{$key} }
	)->hash;
	return unless $user_rec;
	$user_rec->{custom_domain} = '' if $user_rec->{custom_domain} &&
		$user_rec->{custom_domain} eq 'NULL';
	return $user_rec;
}

sub update_user {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my $user_rec = $self->read_user({
		key => 'username',
		username => $username,
	});

	my %values;
	my %keys_null		= map { $_ => 1 } qw(custom_domain);
	my %keys_not_null	= map { $_ => 1 } qw(email);
	my %keys_int		= map { $_ => 1 } qw(date_format create_backups);

	foreach my $key (keys %$args) {
		if ($keys_null{$key}) {
			my $v = $args->{$key} || undef;
			$values{$key} = $v;
		}
		elsif ($keys_not_null{$key}) {
			my $v = $args->{$key};
			$values{$key} = $v if $v;
		}
		elsif ($keys_int{$key}) {
			my $v = $args->{$key} // 0;
			$values{$key} = $v;
		}
	};

	if (%values) {
		my $ok = $self->db->update('users', \%values, { username => $username });
		warn unless $ok;
	}
	return 1;
}

sub delete_user {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $user_rec = $self->read_user({
		key => 'username',
		username => $username,
	});
	my $customer_id = $user_rec->{customer_id};

	$self->customer->delete_customer({
		customer_id => $customer_id,
	});

	$self->db->delete('users', { username => $username });
	return 1;
}

sub authenticate_user {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my $user_rec = $self->read_user({
		key => 'username',
		username => $username,
	});
	return unless $user_rec;
	my $hash = $user_rec->{password_hash};
	return unless $hash;
	return unless bcrypt_check($args->{password}, $hash);

	return 1 if $username eq 'demo';

	my $secret = $user_rec->{totp_secret};
	my $totp = $args->{totp};
	my @totp_expected_pair = $self->totp->read_totp({ totp_secret => $secret });
	return unless $self->totp->check_totp({
		totp => $totp,
		totp_expected_pair => \@totp_expected_pair
	});
	return 1;
}

return 1;
