package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib')->to_string;

use Bliptown::Model::User;
use Bliptown::Model::Page;

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
		user => sub {
			state $user = Bliptown::Model::User->new;
		});

	$app->helper(
		page => sub {
			state $page = Bliptown::Model::Page->new;
		});

	$app->helper(
		get_home => sub {
			my $c = shift;
			state $home = $app->home;
		}
	);

	$app->helper(
		get_user => sub {
			my $c = shift;
			my @hostname = split(/\./, $c->req->url->to_abs->host);
			return @hostname >= 3 ? $hostname[-3] : 'mayor';
		});

	my $r = $app->routes;

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
	$r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	$r->get(
		'/uploads/*catchall' => sub {
			my $c = shift;
			my $filepath = $app->home->child('src', $c->get_user, 'uploads', $c->param('catchall'));
			if (-r $filepath) {
				return $c->reply->file($filepath);
			} else {
				return $c->reply->not_found;
			}
		});

	$r->get('/admin/uploads')->to(controller => 'Uploads', action => 'list_uploads')->name('list_uploads');

	$r->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');

	my $protected = $r->under(
		sub {
			my $c = shift;
			return 1 if $c->session('username');
		});

	# $protected->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
