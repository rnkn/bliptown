use Mojo::Base -strict;

use Test::More;
use Test::Mojo;
use Mojo::File qw(path tempdir);
use Mojo::Util qw(generate_secret);

# Setup test environment
my $tmpdir = tempdir();
my $test_db = $tmpdir->child('test.db');
my $test_user_home = $tmpdir->child('users');
my $test_log_home = $tmpdir->child('logs');
my $test_health_file = $tmpdir->child('health');

$test_user_home->make_path;
$test_log_home->make_path;

local $ENV{BLIPTOWN_DB} = "$test_db";
local $ENV{BLIPTOWN_USER_HOME} = "$test_user_home";
local $ENV{BLIPTOWN_LOG_HOME} = "$test_log_home";
local $ENV{BLIPTOWN_HEALTH_FILE} = "$test_health_file";
local $ENV{BLIPTOWN_SECRET} = generate_secret();
local $ENV{BLIPTOWN_DOMAIN} = 'test.local';
local $ENV{BLIPTOWN_GEOIP_DB} = $tmpdir->child('geoip.db');

# Touch geoip db file
path($ENV{BLIPTOWN_GEOIP_DB})->touch;

my $t = Test::Mojo->new('Bliptown');

# Test user registration
subtest 'User registration flow' => sub {
	my $username = 'testuser';
	my $email = 'test@example.com';
	my $password = 'testpassword123';

	# Test invalid credentials
	$t->post_ok('/join' => form => {
		username => 'a',  # too short
		email => 'invalid-email',
		password => 'short',
		back_to => '/'
	})->status_is(302);

	# Verify user was NOT created for invalid input
	my $invalid_user = $t->app->user->read_user({ key => 'username', username => 'a' });
	ok(!$invalid_user, 'Invalid user was not created');

	# Test duplicate username
	$t->post_ok('/join' => form => {
		username => $username,
		email => $email,
		password => $password,
		back_to => '/'
	})->status_is(302);

	# Verify user was created
	my $user = $t->app->user->read_user({ key => 'username', username => $username });
	ok($user, 'User was created');
	is($user->{username}, $username, 'Username matches');
	is($user->{email}, $email, 'Email matches');
	is($user->{email_verified}, 0, 'Email not verified initially');
	ok($user->{totp_secret}, 'TOTP secret was created');

	# Test duplicate email
	$t->post_ok('/join' => form => {
		username => 'another_user',
		email => $email,
		password => $password,
		back_to => '/'
	})->status_is(302);

	# Test duplicate username
	$t->post_ok('/join' => form => {
		username => $username,
		email => 'another@example.com',
		password => $password,
		back_to => '/'
	})->status_is(302);
};

# Test email verification
subtest 'Email verification flow' => sub {
	my $username = 'verifyuser';
	my $email = 'verify@example.com';
	my $password = 'testpassword123';

	# Create user
	$t->app->user->create_user({
		username => $username,
		email => $email,
		password => $password,
		email_verified => 0,
	});

	# Create verification token
	my $token = $t->app->email_verification->create_token({ username => $username });
	ok($token, 'Verification token created');

	# Test invalid token
	$t->get_ok('/verify-email?token=invalid_token')
		->status_is(403)
		->content_like(qr/invalid or expired/i);

	# Test valid token
	$t->get_ok("/verify-email?token=$token")
		->status_is(302);

	# Verify user email was marked as verified
	my $user = $t->app->user->read_user({ key => 'username', username => $username });
	is($user->{email_verified}, 1, 'Email was verified');

	# Verify token was deleted
	my $token_record = $t->app->email_verification->read_token({ token => $token });
	ok(!$token_record, 'Verification token was deleted');
};

# Test payment token and subscription page
subtest 'Subscription page flow' => sub {
	my $username = 'payuser';

	# Create payment token
	my $token = $t->app->payment_token->create_token({ username => $username });
	ok($token, 'Payment token created');

	# Create user
	$t->app->user->create_user({
		username => $username,
		email => 'pay@example.com',
		password => 'testpassword123',
		email_verified => 1,
	});

	# Test invalid token
	$t->get_ok('/subscribe?token=invalid_token')
		->status_is(403)
		->content_like(qr/invalid payment token/i);

	# Test valid token
	$t->get_ok("/subscribe?token=$token")
		->status_is(200)
		->content_like(qr/Subscribe to Bliptown/i)
		->content_like(qr/$username/i);
};

# Test models
subtest 'Model tests' => sub {
	# Test EmailVerification model
	my $username = 'modeltest';
	my $token = $t->app->email_verification->create_token({ username => $username });
	ok($token, 'Email verification token created');

	my $record = $t->app->email_verification->read_token({ token => $token });
	ok($record, 'Token record retrieved');
	is($record->{username}, $username, 'Username matches in token record');
	ok($record->{expires} > time, 'Token has not expired');

	$t->app->email_verification->delete_token({ token => $token });
	my $deleted_record = $t->app->email_verification->read_token({ token => $token });
	ok(!$deleted_record, 'Token was deleted');

	# Test PaymentToken model
	my $payment_token = $t->app->payment_token->create_token({ username => $username });
	ok($payment_token, 'Payment token created');

	my $payment_record = $t->app->payment_token->read_token({ token => $payment_token });
	ok($payment_record, 'Payment token record retrieved');
	is($payment_record->{username}, $username, 'Username matches in payment token record');

	$t->app->payment_token->delete_token({ token => $payment_token });
	my $deleted_payment = $t->app->payment_token->read_token({ token => $payment_token });
	ok(!$deleted_payment, 'Payment token was deleted');
};

done_testing();
