package Bliptown::Controller::Subscription;
use Mojo::Base 'Mojolicious::Controller';

sub subscribe_page {
	my $c = shift;
	my $token = $c->param('token') || '';

	# Verify payment token
	my $record = $c->payment_token->read_token({ token => $token });

	if (!$record || !$record->{username}) {
		return $c->render(
			status => 403,
			template => 'message',
			title => '403 Forbidden',
			content => '403 Forbidden: invalid payment token',
		);
	}

	my $username = $record->{username};
	my $user = $c->user->read_user({ key => 'username', username => $username });

	if (!$user) {
		return $c->render(
			status => 404,
			template => 'message',
			title => '404 Not Found',
			content => '404 Not Found: user not found',
		);
	}

	# Get Stripe payment URL from environment or config
	my $stripe_base_url = $ENV{BLIPTOWN_STRIPE_URL} || 'https://buy.stripe.com/YOUR_PAYMENT_LINK';

	# Add the payment token as a URL parameter
	my $stripe_url = "$stripe_base_url?client_reference_id=$token";

	return $c->render(
		template => 'subscribe',
		title => 'Subscribe to Bliptown',
		username => $username,
		stripe_url => $stripe_url,
		token => $token,
	);
}

return 1;
