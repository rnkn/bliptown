use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;
use Test::Mojo;

use BliptownTest qw(create_test create_app);

use_ok qw(Bliptown::Controller::Settings);

my $t			= create_test;
my $app			= create_app;

my $util		= Bliptown::Model::Util->new;
my $customer	= Bliptown::Model::Customer->new(
	util => $util,
);
my $user		= Bliptown::Model::User->new(
	db => $app->db,
	customer => $customer,
);

$ENV{BLIPTOWN_DATA_HOME} = tempdir;

my $username	= 'testuser';
my $email		= 'testuser@example.com';
my $user_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#username', 'value', $username)
	->attr_is('input#email', 'value', $email)
	->element_exists_not('input#create-backups[checked]');

$t->post_ok($app->url_for('save_settings') => { Host => $user_domain } => form => {
	email => 'newemail@mydomain.org',
	create_backups => 1,
})->status_is(302);

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#email', 'value', 'newemail@mydomain.org')
	->element_exists('input#create-backups[checked]');

done_testing;
