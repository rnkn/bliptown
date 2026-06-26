package Bliptown::Model::File;
use Mojo::Base -base;
use Mojo::File;
use Mojo::URL;
use Mojo::UserAgent;

sub read_file {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	return unless -r $file;
	my $chars = $file->slurp('utf-8');
	return { chars => $chars };
}

sub purge_cdn_file {
	my ($self, $args) = @_;
	my $url = Mojo::URL->new;
	$url->host($ENV{BLIPTOWN_CDN_API_HOST});
	$url->scheme('https');
	$url->path('/purge');
	$url->query(url => $args->{url});

	my $ua = Mojo::UserAgent->new;
	my $res = $ua->post($url => { 'AccessKey' => $ENV{BLIPTOWN_CDN_API_KEY} })->result;
	return $res;
}

return 1;
