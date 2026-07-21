use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use Bliptown::Model::Util;
use Bliptown::Model::Customer;

use_ok qw(Bliptown::Model::Checkout);

my $util		= Bliptown::Model::Util->new;
my $customer	= Bliptown::Model::Customer->new(util => $util);
my $checkout	= Bliptown::Model::Checkout->new(util => $util);

my $res = $customer->create_customer({
	username => 'testcustomer',
	email => 'testcustomer@example.com',
});

my $customer_id = $res->{id};

subtest 'create_checkout_session' => sub {
	my $res = $checkout->create_checkout_session({
		customer_id => $customer_id,
	});
	my $session_id = $res->{id};

	is $res->{object}, 'checkout.session', 'create_checkout_session object is checkout.session';
	like $session_id, qr/cs_test_[A-Za-z0-9]+/, 'create_checkout_session returns valid session ID';
	like $res->{url}, qr{https://checkout.stripe.com}, 'create_checkout_session returls valid session URL';
};

$customer->delete_customer({
	customer_id => $customer_id,
});

done_testing;
