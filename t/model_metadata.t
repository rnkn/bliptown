use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::Metadata);

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

subtest 'read_metadata returns hashref for empty YAML' => sub {
	my $yaml = <<'EOF';
---
---
EOF
	my $data = $metadata->read_metadata($yaml);
	isa_ok $data, 'HASH', 'read_metadata returns a hashref';
};

subtest 'read_metadata returns hashref for invalid YAML' => sub {
	my $yaml = <<'EOF';
zzz
EOF
	my $data = $metadata->read_metadata($yaml);
	isa_ok $data, 'HASH', 'read_metadata returns a hashref';
};

done_testing;
