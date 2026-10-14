use Mojo::Base -strict;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;

my $util		= Bliptown::Model::Util->new;
my $customer	= Bliptown::Model::Customer->new(
	util => $util
);
my $customer_id	= '';

subtest 'create_customer' => sub {
	my $res = $customer->create_customer({
		username => 'testcustomer',
		email => 'testcustomer@example.com',
	});
	$customer_id = $res->{id};

	like $customer_id, qr/^cus_[A-Za-z0-9]+$/, 'create_customer returns valid customer ID';
};

subtest 'read_customer' => sub {
	my $res = $customer->read_customer({
		customer_id => $customer_id,
	});

	is $res->{id}, $customer_id, 'read_customer returns correct customer ID';
	is $res->{name}, 'testcustomer', 'read_customer returns correct customer name';
	is $res->{email}, 'testcustomer@example.com', 'read_customer returns correct customer email';
};

subtest 'read_customer fail' => sub {
	my $res = $customer->read_customer({
		customer_id => 'cus_1234567890',
	});

	like $res->{error}->{message}, qr/no such customer/i, 'read_customer fails with nonexistent customer ID';
};

subtest 'update_customer' => sub {
	$customer->update_customer({
		customer_id => $customer_id,
		email => 'newemail@mydomain.org',
	});

	my $res = $customer->read_customer({
		customer_id => $customer_id,
	});
	is $res->{email}, 'newemail@mydomain.org', 'update_customer updates customer email';
};

subtest 'update_customer fail' => sub {
	my $res = $customer->update_customer({
		customer_id => 'cus_1234567890',
		email => 'newemail@mydomain.org',
	});

	like $res->{error}->{message}, qr/no such customer/i, 'update_customer fails with nonexistent customer ID';
};

subtest 'create_billing_session' => sub {
	my $res = $customer->create_billing_session({
		customer_id => $customer_id
	});

	is $res->{customer}, $customer_id, 'create_billing_session returns correct customer ID';
	like $res->{id}, qr/^bps_[A-Za-z0-9]+$/, 'create_billing_session returns valid session ID';
	like $res->{url}, qr{https://billing.stripe.com}, 'create_billing_session returns valid URL';
};

subtest 'delete_customer fail' => sub {
	my $res = $customer->delete_customer({
		customer_id => 'cus_1234567890',
	});

	like $res->{error}->{message}, qr/no such customer/i, 'delete_customer fails with nonexistent customer ID';
};

subtest 'delete_customer' => sub {
	my $res = $customer->delete_customer({
		customer_id => $customer_id,
	});

	is $res->{object}, 'customer', 'delete_customer object is customer';
	is $res->{id}, $customer_id, 'delete_customer returns deleted customer ID';
	ok $res->{deleted}, 'delete_customer returns deleted customer object';
};

done_testing;
