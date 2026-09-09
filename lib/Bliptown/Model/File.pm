package Bliptown::Model::File;
use Mojo::Base -base;
use Mojo::File qw(path);
use Mojo::URL;
use Mojo::UserAgent;

sub read_file {
	my ($self, $args) = @_;
	my $path = path($args->{filename});
	return unless -r $path;
	my $chars = $path->slurp('UTF-8');
	return { chars => $chars };
}

sub purge_cdn_file {
	my ($self, $args) = @_;

	my $path = path($args->{filename});
	$path = $path->to_rel($ENV{BLIPTOWN_DATA_HOME}, 'users');

	my $cdn_url = "https://cdn.blip.town/$path";

	my $purge_url = Mojo::URL->new;
	$purge_url->host($ENV{BLIPTOWN_CDN_API_HOST});
	$purge_url->scheme('https');
	$purge_url->path('/purge');
	$purge_url->query(url => $cdn_url);

	my $ua = Mojo::UserAgent->new;
	my $res = $ua->post($purge_url => { 'AccessKey' => $ENV{BLIPTOWN_CDN_API_KEY} })->result;
	return $res;
}

return 1;
