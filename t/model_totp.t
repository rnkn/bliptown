use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Mojo::Util qw(generate_secret secure_compare);
use Digest::SHA qw(sha1_hex);
use MIME::Base32 qw(encode_base32 decode_base32);
use Test::More;

use_ok('Bliptown::Model::TOTP');

my $totp = Bliptown::Model::TOTP->new;

subtest 'create_secret' => sub {
    my $secret = $totp->create_secret;

    is length($secret), 37, 'create_secret returns secret 37 characters long';
    like $secret, qr/^[A-Z2-7]+$/, 'create_secret returns secret containing only valid base32 characters';
};

subtest 'read_totp' => sub {
    my $secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    my $time = 1_000_000_000;
    my @totp_pair = $totp->read_totp({ totp_secret => $secret, time => $time });

    is scalar(@totp_pair), 2, 'read_totp returns a pair of values';
	is $totp_pair[0], '855786', 'read_totp returns correct current TOTP';
	is $totp_pair[1], '742818', 'read_totp returns correct old TOTP';
};

subtest 'check_totp' => sub {
    my $secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    my $time = 1_000_000_000;
    my @totp_pair = qw(855786 742818);

    ok $totp->check_totp({
		totp => $totp_pair[0],
		totp_expected_pair => \@totp_pair
	}), 'check_totp accepts current TOTP';

    ok $totp->check_totp({
		totp => $totp_pair[1],
		totp_expected_pair => \@totp_pair
	}), 'check_totp accepts old TOTP';

    ok ! $totp->check_totp({
		totp => '000000',
		totp_expected_pair => \@totp_pair
	}), 'check_totp rejects incorrect TOTP';

    ok ! $totp->check_totp({
		totp => '',
		totp_expected_pair => \@totp_pair
	}), 'check_totp rejects empty TOTP';

	ok ! $totp->check_totp({
		totp => $totp_pair[0]
	}), 'check_totp rejects missing TOTP expected pair';
};

done_testing;
