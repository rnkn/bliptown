use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest qw(create_app);

my $app = create_app;

my $token = Bliptown::Model::Token->new(
	db => $app->db,
);

subtest 'create_login_token' => sub {
    my $tk = $token->create_login_token({ username => 'alice' });
    ok defined $tk, 'create_login_token returns a token';
    ok length($tk) == 40, 'create_login_token token has correct length';
};

subtest 'create_login_token fail' => sub {
    my $tk = $token->create_login_token({ username => '' });
    ok !$tk, 'create_login_token omits token without username';
};

subtest 'read_login_token' => sub {
    my $tk = $token->create_login_token({ username => 'bob' });
    my $token_rec = $token->read_login_token({ token => $tk });
    ok defined $token_rec, 'read_login_token retrieves record';
    is $token_rec->{username}, 'bob', 'read_login_token returns username';
    is $token_rec->{token}, $tk, 'read_login_token returns token';
};

subtest 'read_login_token fail' => sub {
    my $token_rec = $token->read_login_token({ token => 'nonexistent' });
    ok !defined $token_rec, 'read_login_token omits record for invalid token';
};

subtest 'delete_login_token' => sub {
    my $tk = $token->create_login_token({ username => 'carol' });
    my $token_rec = $token->read_login_token({ token => $tk });
    my $ok = $token->delete_login_token({ token => $tk });
    ok $ok, 'delete_login_token returns success';
    $token_rec = $token->read_login_token({ token => $tk });
    ok !defined $token_rec, 'delete_login_token deletes token record';
};

subtest 'delete_login_token abort' => sub {
    my $ok = $token->delete_login_token({ token => '' });
    ok !defined $ok, 'delete_login_token aborts with empty token';
};

subtest 'validate_login_token_rec' => sub {
    my $tk = $token->create_login_token({ username => 'dave' });
    my $token_rec = $token->read_login_token({ token => $tk });
    ok $token->validate_login_token_rec({ token_rec => $token_rec }), 'validate_login_token_rec validates record';
};

subtest 'validate_login_token_rec expired' => sub {
    my $tk = $token->create_login_token({ username => 'erin' });
    my $token_rec = $token->read_login_token({ token => $tk });
    $token_rec->{expires} = time - 1;
    ok !$token->validate_login_token_rec({ token_rec => $token_rec }), 'validate_login_token_rec rejects expired record';
};

done_testing;
