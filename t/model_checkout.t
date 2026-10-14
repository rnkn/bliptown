use Mojo::Base -strict;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;

my $util		= Bliptown::Model::Util->new;
my $customer	= Bliptown::Model::Customer->new(
	util => $util
);
my $checkout	= Bliptown::Model::Checkout->new(
	util => $util
);

my $res = $customer->create_customer({
	username => 'testcustomer',
	email => 'testcustomer@example.com',
});

my $customer_id = $res->{id};

subtest 'create_checkout_session' => sub {
	my $res = $checkout->create_checkout_session({
		customer_id => $customer_id,
	});

	is $res->{object}, 'checkout.session', 'create_checkout_session object is checkout.session';
	like $res->{id}, qr/cs_test_[A-Za-z0-9]+/, 'create_checkout_session returns valid session ID';
	like $res->{url}, qr{https://checkout.stripe.com}, 'create_checkout_session returns valid session URL';
};

$customer->delete_customer({
	customer_id => $customer_id,
});

done_testing;
