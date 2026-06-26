package Bliptown::Model::Checkout;
use Mojo::Base -base;
use Mojo::UserAgent;

has 'util';

my $ua = Mojo::UserAgent->new;

sub create_checkout_session {
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

return 1;
