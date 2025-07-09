package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib')->to_string;

use Bliptown::Model::User;
use Bliptown::Model::Page;
use Bliptown::Model::Source;

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
			state $user = Bliptown::Model::User->new(sqlite => shift->sqlite);
		});

	$app->helper(
		page => sub {
			state $page = Bliptown::Model::Page->new;
		});

	$app->helper(
		source => sub {
			state $src = Bliptown::Model::Source->new;
		});

	$app->helper(
		get_user => sub {
			my $c = shift;
			my @hostname = split(/\./, $c->req->url->to_abs->host);
			return @hostname >= 3 ? $hostname[-3] : 'mayor';
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $file_html = $app->home->child($c->get_src_dir, $c->get_user, $slug . '.html');
			my $file_css = $app->home->child($c->get_src_dir, $c->get_user, $slug . '.css');
			my $file_md = $app->home->child($c->get_src_dir, $c->get_user, $slug . '.md');
			return $file_html if -r $file_html;
			return $file_css if -r $file_css;
			return $file_md if -r $file_md;
		}
	);

	$app->helper(
		get_home => sub {
			my $c = shift;
			state $home = $app->home;
		}
	);

	$app->helper(
		get_src_dir => sub {
			state $src = $ENV{'BLIPTOWN_SRC'};
			return $src;
		}
	);

	$app->helper(
		get_pages => sub {
			my $c = shift;
			my $paths = $app->home->child($app->get_src, $app->get_user)->list->to_array;
			my %pages;
			foreach (@$paths) {
				$pages{$_} = basename($_);
			}
			return \%pages;
		}
	);

	my $r = $app->routes;

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
	$r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	$r->get(
		'/uploads/*catchall' => sub {
			my $c = shift;
			my $file = $app->home->child($c->get_src_dir, $c->get_user, 'uploads', $c->param('catchall'));
			if (-r $file) {
				return $c->reply->file($file);
			} else {
				return $c->reply->not_found;
			}
		});

	my $protected = $r->under(
		'/' => sub {
			my $c = shift;
			if ($c->session('username') eq $c->get_user) {
				$c->stash(auth => 1);
				return 1;
			}
		});

	$protected->get('/pages')->to(controller => 'Page', action => 'list_pages')->name('list_pages');
	$protected->get('/uploads')->to(controller => 'Uploads', action => 'list_uploads')->name('list_uploads');
	$protected->get('/edit/*catchall')->to(controller => 'Page', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Page', action => 'save_page', catchall => '')->name('save_page');

	$r->get('/raw/*catchall')->to(controller => 'Page', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
