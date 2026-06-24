package Bliptown::Model::Customer;
use Mojo::Base -base;
use Mojo::UserAgent;

has 'util';

my $ua = Mojo::UserAgent->new;

sub create_customer {
	my ($self, $args) = @_;
	my $username =  $args->{username};
	my $email =  $args->{email};
	return unless ($username && $email);
	my $url = $self->util->create_stripe_url("/v1/customers");

	my $tx = $ua->post($url => form => {
		name => $username,
		email => $email,
	});
	my $res = $tx->res->json;
	return $res;
}

sub read_customer {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->create_stripe_url("v1/customers/$customer_id");

	my $tx = $ua->get($url);
	my $res = $tx->res->json;
	return $res;
}

sub update_customer {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->create_stripe_url("v1/customers/$customer_id");

	my %data;
	my %allowed_keys = map { $_ => 1 } qw(email);

	foreach my $key (keys %$args) {
		if ($allowed_keys{$key}) {
			$data{$key} = $args->{$key};
		}
	}

	my $tx = $ua->post($url, form => { %data });
	my $res = $tx->res->json;
	return $res;
}

sub delete_customer {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->util->create_stripe_url("v1/customers/$customer_id");

	my $tx = $ua->delete($url);
	my $res = $tx->res->json;
	return $res;
}

sub create_billing_session {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->util->create_stripe_url("v1/billing_portal/sessions");

	my $tx = $ua->post($url => form => {
		customer => $customer_id
	});
	my $res = $tx->res->json;
	return $res;
}

return 1;
