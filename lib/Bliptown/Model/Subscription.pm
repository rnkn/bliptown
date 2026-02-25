package Bliptown::Model::Subscription;
use Mojo::Base -base;
use Mojo::UserAgent;

my $ua = Mojo::UserAgent->new;
my $stripe_url = Mojo::URL->new;
$stripe_url->scheme('https');
$stripe_url->host('api.stripe.com');
$stripe_url->userinfo($ENV{BLIPTOWN_STRIPE_API_KEY} . ':');

sub create_stripe_url {
	my ($self, $path) = @_;
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host('api.stripe.com');
	$url->path($path);
	$url->userinfo($ENV{BLIPTOWN_STRIPE_API_KEY} . ':');
	return $url;
}

sub create_subscription { }

sub read_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	$stripe_url->path("v1/customers/$customer_id");

	my $tx = $ua->get($stripe_url);
	my $res = $tx->res->json;
	return $res;
}

sub update_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	$stripe_url->path("v1/customers/$customer_id");

	my %data;
	my %allowed_keys = map { $_ => 1 } qw(email);

	foreach my $key (keys %$args) {
		if ($allowed_keys{$key}) {
			$data{$key} = $args->{$key};
		}
	}

	my $tx = $ua->post($stripe_url, form => { %data });
	my $res = $tx->res->json;
	return $res;
}

sub delete_subscription {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	$stripe_url->path("v1/customers/$customer_id");

	my $tx = $ua->delete($stripe_url);
	my $res = $tx->res->json;
	return $res;
}

sub create_billing_session {
	my ($self, $args) = @_;
	my $customer_id = $args->{customer_id};
	unless ($customer_id) {
		$self->log->error("");
	}
	my $url = $self->create_stripe_url("v1/billing_portal/sessions");

	my $tx = $ua->post($url => form => { customer => $customer_id });
	my $res = $tx->res->json;
	return $res;
}

return 1;
