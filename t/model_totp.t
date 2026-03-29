use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use BliptownTest;

use Bliptown::Model::TOTP;

my $totp = Bliptown::Model::TOTP->new;

subtest 'create_secret returns a non-empty string' => sub {
	my $secret = $totp->create_secret;
	ok defined $secret && length($secret) > 0, 'secret is non-empty';
	ok $secret =~ /^[A-Z2-7]+=*$/, 'secret looks like a Base32 string';
};

subtest 'create_secret generates unique secrets' => sub {
	my $s1 = $totp->create_secret;
	my $s2 = $totp->create_secret;
	isnt $s1, $s2, 'two calls produce different secrets';
};

subtest 'read_totp returns a pair of TOTP codes' => sub {
	my $secret = $totp->create_secret;
	my @pair = $totp->read_totp({ totp_secret => $secret });
	is scalar @pair, 2, 'returns exactly two codes';
	ok $pair[0] =~ /^\d{6}$/, 'current code is 6 digits';
	ok $pair[1] =~ /^\d{6}$/, 'previous code is 6 digits';
};

subtest 'check_totp succeeds with correct current code' => sub {
	my $secret = $totp->create_secret;
	my @pair = $totp->read_totp({ totp_secret => $secret });
	my $result = $totp->check_totp({
		totp => $pair[0],
		totp_expected_pair => \@pair,
	});
	ok $result, 'current TOTP code passes check';
};

subtest 'check_totp succeeds with previous (old) code' => sub {
	my $secret = $totp->create_secret;
	my @pair = $totp->read_totp({ totp_secret => $secret });
	my $result = $totp->check_totp({
		totp => $pair[1],
		totp_expected_pair => \@pair,
	});
	ok $result, 'previous TOTP code passes check';
};

subtest 'check_totp fails with wrong code' => sub {
	my $secret = $totp->create_secret;
	my @pair = $totp->read_totp({ totp_secret => $secret });
	my $wrong = ($pair[0] eq '000000') ? '111111' : '000000';
	my $result = $totp->check_totp({
		totp => $wrong,
		totp_expected_pair => \@pair,
	});
	ok !$result, 'wrong TOTP code fails check';
};

done_testing;
