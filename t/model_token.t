use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);
use Bliptown::Model::Token;

my $db = create_db;
my $token = Bliptown::Model::Token->new(db => $db);

subtest 'create_token returns a token string' => sub {
    my $t = $token->create_token({ username => 'alice' });
    ok defined $t, 'token is defined';
    ok length($t) == 40, 'token has correct length';
};

subtest 'create_token requires username' => sub {
    my $t = $token->create_token({ username => '' });
    ok !defined $t, 'no token created with empty username';
};

subtest 'read_token retrieves record' => sub {
    my $t = $token->create_token({ username => 'bob' });
    my $record = $token->read_token({ token => $t });
    ok defined $record, 'record retrieved';
    is $record->{username}, 'bob', 'username matched';
    is $record->{token}, $t, 'token matched';
};

subtest 'read_token returns nothing for invalid token' => sub {
    my $record = $token->read_token({ token => 'nonexistent' });
    ok !defined $record, 'no record for invalid token';
};

subtest 'read_token returns nothing for empty token' => sub {
    my $record = $token->read_token;
    ok !defined $record, 'no record for empty token';
};

subtest 'delete_token removes record' => sub {
    my $t = $token->create_token({ username => 'carol' });
    my $record = $token->read_token({ token => $t });
    my $ok = $token->delete_token({ token => $t });
    ok $ok, 'delete returned true';
    $record = $token->read_token({ token => $t });
    ok !defined $record, 'no record for deleted token';
};

subtest 'delete_token returns nothing for empty token' => sub {
    my $ok = $token->delete_token({ token => '' });
    ok !defined $ok, 'delete returned nothing for empty token';
};

subtest 'token expires' => sub {
    my $t = $token->create_token({ username => 'dave' });
    ok defined $t, 'token created';
    $db->update('login_tokens', { expires => time - 1 }, { token => $t });
    my $record = $token->read_token({ token => $t });
    cmp_ok $record->{expires}, '<=', time, 'token has expired';
};

done_testing;
