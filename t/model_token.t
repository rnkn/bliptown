use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use BliptownTest qw(new_sqlite_with_users);

use Bliptown::Model::Token;

my $sql   = new_sqlite_with_users();
my $token = Bliptown::Model::Token->new(sqlite => $sql);

subtest 'create_token' => sub {
	my $tok = $token->create_token({ username => 'alice' });
	ok $tok, 'token string is returned';
	ok length($tok) >= 20, 'token has adequate length';
};

subtest 'read_token finds existing token' => sub {
	my $tok = $token->create_token({ username => 'bob' });
	my $record = $token->read_token({ token => $tok });
	ok $record, 'record found';
	is $record->{username}, 'bob', 'username matches';
	ok $record->{token}, 'token field present';
	ok $record->{expires} > time, 'expires is in the future';
};

subtest 'read_token returns undef for nonexistent token' => sub {
	my $record = $token->read_token({ token => 'nonexistent_token_xyz' });
	ok !defined $record, 'returns undef for unknown token';
};

subtest 'read_token returns undef when token key is missing' => sub {
	my $record = $token->read_token({});
	ok !defined $record, 'returns undef when no token provided';
};

subtest 'delete_token removes the token' => sub {
	my $tok = $token->create_token({ username => 'carol' });
	ok $token->read_token({ token => $tok }), 'token exists before delete';
	$token->delete_token({ token => $tok });
	ok !defined $token->read_token({ token => $tok }), 'token gone after delete';
};

subtest 'delete_token returns undef when token key is missing' => sub {
	my $result = $token->delete_token({});
	ok !defined $result, 'returns undef when no token provided';
};

subtest 'token expiry time is approximately 30 seconds from now' => sub {
	my $before = time;
	my $tok = $token->create_token({ username => 'dave' });
	my $after = time;
	my $record = $token->read_token({ token => $tok });
	ok $record->{expires} >= $before + 30, 'expires at least 30s from creation time';
	ok $record->{expires} <= $after + 30, 'expires no more than 30s after now';
};

done_testing;
