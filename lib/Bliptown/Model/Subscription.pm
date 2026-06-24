package Bliptown::Model::Subscription;
use Mojo::Base -base;
use Mojo::UserAgent;

has 'util';

my $ua = Mojo::UserAgent->new;

sub create_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	my $url = $self->util->create_stripe_url('/v1/checkout/sessions');

	my $tx = $ua->post($url => form => {
		customer => $customer_id,
		mode => 'subscription',
		'line_items[0][price]' => $ENV{BLIPTOWN_STRIPE_PRICE_ID},
		'line_items[0][quantity]' => 1,
		success_url => 'http://blip.local',
		cancel_url => 'http://blip.local',
	});
	my $res = $tx->res->json;
	return $res;
}

sub read_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->util->create_stripe_url("v1/customers/$customer_id");

	my $tx = $ua->get($url);
	my $res = $tx->res->json;
	return $res;
}

sub update_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	return unless $customer_id;
	my $url = $self->util->create_stripe_url("v1/customers/$customer_id");

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

sub delete_subscription {
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

	my $tx = $ua->post($url => form => { customer => $customer_id });
	my $res = $tx->res->json;
	return $res;
}

return 1;
