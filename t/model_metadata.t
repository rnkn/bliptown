use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;

my $metadata = Bliptown::Model::Metadata->new;

subtest 'read_metadata parses YAML keys' => sub {
	my $yaml = <<'EOF';
---
title: My Post
date: 2999-12-31
layout: one-column
---
EOF
	my $data = $metadata->read_metadata($yaml);
	is $data->{title}, 'My Post', 'read_metadata parses title';
	is $data->{date}, '2999-12-31', 'read_metadata parses date';
	is $data->{layout}, 'one-column', 'read_metadata parses layout';
};

subtest 'read_metadata empty YAML' => sub {
	my $yaml = <<'EOF';
---
---
EOF
	my $data = $metadata->read_metadata($yaml);
	isa_ok $data, 'HASH', 'read_metadata returns a hashref for empty YAML';
 	not ok $data, 'read_metadata returns an empty hashref for empty YAML';
};

subtest 'read_metadata returns hashref for invalid YAML' => sub {
	my $yaml = <<'EOF';
zzz
EOF
	my $data = $metadata->read_metadata($yaml);
	isa_ok $data, 'HASH', 'read_metadata returns a hashref for invalid YAML';
	not ok $data, 'read_metadata returns an empty hashref for invalid YAML';
};

done_testing;
