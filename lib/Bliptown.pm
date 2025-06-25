package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use Text::Markdown;

sub startup {
	my $app = shift;
	$app->secrets([ $ENV{'BLIPTOWN_SECRET'} ]);
	$app->config(
		hypnotoad => {
			proxy  => 1
		});

	$app->helper(
		sqlite => sub {
			state $sql = Mojo::SQLite->new('sqlite:users.db');
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate;

	$app->helper(
		users => sub {
			state $users = Bliptown::Model::User->new(sqlite => shift->sqlite)
		});

	my $r = $app->routes;

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->get('/join')->to(controller => 'Email', action => 'email_confirmation')->name('email_confirmation');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
    $r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	$r->get('/')->to(controller => 'Page', action => 'render_page')->name('render_page');

	my $protected = $r->under(
		sub {
			my $c = shift;
			return 1 if $c->session('user_id');
		});
}

return 1;
