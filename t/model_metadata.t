use Mojo::Base -strict;
use lib 't/lib';

use Test::More;

use Bliptown::Model::Metadata;

my $meta = Bliptown::Model::Metadata->new;

subtest 'read_metadata parses title and date' => sub {
	my $yaml = "---\ntitle: My Post\ndate: 2024-01-15\n---\n";
	my $data = $meta->read_metadata($yaml);
	is $data->{title}, 'My Post', 'title parsed';
	is $data->{date}, '2024-01-15', 'date parsed';
};

subtest 'read_metadata parses layout key' => sub {
	my $yaml = "---\nlayout: wide\n---\n";
	my $data = $meta->read_metadata($yaml);
	is $data->{layout}, 'wide', 'layout parsed';
};

subtest 'read_metadata returns empty hashref for empty YAML' => sub {
	my $data = $meta->read_metadata("---\n---\n");
	ok ref($data) eq 'HASH', 'returns a hashref';
};

subtest 'read_metadata returns empty hashref for invalid YAML' => sub {
	my $data = $meta->read_metadata('not yaml at all {{{');
	ok ref($data) eq 'HASH', 'returns a hashref even for invalid input';
};

subtest 'read_metadata handles multiple keys' => sub {
	my $yaml = "---\ntitle: Hello\ndate: 2023-06-01\nlayout: two-column\n---\n";
	my $data = $meta->read_metadata($yaml);
	is $data->{title}, 'Hello', 'title correct';
	is $data->{date}, '2023-06-01', 'date correct';
	is $data->{layout}, 'two-column', 'layout correct';
};

done_testing;
