use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use_ok qw(Bliptown::Model::Token);

my $db = create_db;
my $token = Bliptown::Model::Token->new(db => $db);

subtest 'create_token token string' => sub {
    my $tk = $token->create_token({ username => 'alice' });
    ok defined $tk, 'create_token returns a token';
    ok length($tk) == 40, 'create_token token has correct length';
};

subtest 'create_token username' => sub {
    my $tk = $token->create_token({ username => '' });
    ok !defined $tk, 'create_token omits token without username';
};

subtest 'read_token retrieves record' => sub {
    my $tk = $token->create_token({ username => 'bob' });
    my $token_rec = $token->read_token({ token => $tk });
    ok defined $token_rec, 'read_token retrieves record';
    is $token_rec->{username}, 'bob', 'read_token returns username';
    is $token_rec->{token}, $tk, 'read_token returns token';
};

subtest 'read_token invalid token' => sub {
    my $token_rec = $token->read_token({ token => 'nonexistent' });
    ok !defined $token_rec, 'read_token omits record for invalid token';
};

subtest 'read_token empty token' => sub {
    my $token_rec = $token->read_token;
    ok !defined $token_rec, 'read_token omits record for empty token';
};

subtest 'delete_token' => sub {
    my $tk = $token->create_token({ username => 'carol' });
    my $token_rec = $token->read_token({ token => $tk });
    my $ok = $token->delete_token({ token => $tk });
    ok $ok, 'delete_token returns true';
    $token_rec = $token->read_token({ token => $tk });
    ok !defined $token_rec, 'delete_token deletes token record';
};

subtest 'delete_token abort' => sub {
    my $ok = $token->delete_token({ token => '' });
    ok !defined $ok, 'delete_token aborts with empty token';
};

subtest 'token expiry' => sub {
    my $tk = $token->create_token({ username => 'dave' });
    $db->update('login_tokens', { expires => time - 1 }, { token => $tk });
    my $token_rec = $token->read_token({ token => $tk });
    cmp_ok $token_rec->{expires}, '<=', time, 'read_token returns expired token';
};

done_testing;
