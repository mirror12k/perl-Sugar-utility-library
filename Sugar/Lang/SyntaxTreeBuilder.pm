package Sugar::Lang::SyntaxTreeBuilder;
use parent 'Sugar::Lang::Tokenizer';
use strict;
use warnings;

use feature 'say';

use Carp;
use Data::Dumper;



sub new {
	my ($class, %opts) = @_;
	my $self = $class->SUPER::new(%opts);

	$self->{syntax_definition} = $opts{syntax_definition} // croak "syntax_definition argument required for Sugar::Lang::SyntaxTreeBuilder";
	$self->{syntax_definition} = { map { $_ => $self->compile_syntax_context($_ => $self->{syntax_definition}{$_}) } keys %{$self->{syntax_definition}} };

	return $self
}

sub parse {
	my ($self) = @_;
	$self->SUPER::parse;

	$self->{current_context} = { type => 'context', context_type => 'root_context' };
	$self->{syntax_tree} = $self->{current_context};
	$self->{context_stack} = [];
	$self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};

	while ($self->more_tokens) {
		$self->{current_syntax_context}->($self);
	}

	return $self->{syntax_tree}
}

sub enter_context {
	my ($self, $context_type) = @_;

	my $new_context = { type => 'context', context_type => $context_type };
	# push @{$self->{current_context}{children}}, $new_context;
	push @{$self->{context_stack}}, $self->{current_context};
	$self->{current_context} = $new_context;
	$self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub exit_context {
	my ($self) = @_;
	confess 'attempt to exit root context' if $self->{current_context}{context_type} eq 'root_context';

	$self->{current_context} = pop @{$self->{context_stack}};
	$self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub switch_context {
	my ($self, $context_type) = @_;
	confess 'attempt to switch context on root context' if $self->{current_context}{context_type} eq 'root_context';

	$self->{current_context}{context_type} = $context_type;
	$self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub extract_context_result {
	my ($self, $context_type) = @_;

	my $previous_context = $self->{current_context};
	$self->enter_context($context_type);
	my $saved_context = $self->{current_context};

	while ($self->{current_context} != $previous_context) {
		say "debug", Dumper $self->{current_context};
		$self->{current_syntax_context}->($self);
	}
	my ($result) = @{$saved_context->{children}};
	say 'got result: ', Dumper $result;
	return $result
}

sub extract_context {
	my ($self, $context_type) = @_;

	my $previous_context = $self->{current_context};
	$self->enter_context($context_type);
	my $saved_context = $self->{current_context};

	while ($self->{current_context} != $previous_context) {
		say "debug", Dumper $self->{current_context};
		$self->{current_syntax_context}->($self);
	}
	$saved_context->{type} = $saved_context->{context_type};
	return $saved_context
}

sub compile_syntax_context {
	my ($self, $context_name, $context) = @_;

	my $code = '
	sub {
		my ($self) = @_;
		say "in ' .$context_name. ' context";
';
	my @items = @$context;
	my $first_item = 1;
	$self->{context_default_case} = undef;
	while (@items) {
		my $condition = shift @items;
		unless (defined $condition) {
			$self->{context_default_case} = shift @items;
			next
		}
		my $condition_code = $self->compile_syntax_condition($condition);
		my $action = shift @items;
		my $action_code = $self->compile_syntax_action($action);

		$code .= "\t\t" if $first_item;
		$code .= "if ($condition_code) { say 'in case $condition';$action_code\t\t} els";

		$first_item = 0;
	}

	$self->{context_default_case} //= { exit_context => 1 };
	my $action_code = $self->compile_syntax_default_action($self->{context_default_case});
	$code .= "e {$action_code\t\t}\n";

	$code .= "
		return;
	}
";
	say "compiled code: ", $code;
	return eval $code
}

sub compile_syntax_condition {
	my ($self, $condition, $offset) = @_;
	$offset //= 0;
	if (ref $condition eq 'ARRAY') {
		my @conditions = @$condition;
		foreach my $i (0 .. $#conditions) {
			$conditions[$i] = $self->compile_syntax_condition($conditions[$i], $i);
		}
		return join ' and ', @conditions
	} elsif (ref $condition eq 'Regexp') {
		return "\$self->is_token_val('*' => qr/$condition/, $offset)"
	} else {
		return "\$self->is_token_val('*' => '$condition', $offset)"
	}
}

sub compile_syntax_action {
	my ($self, $action) = @_;

	my @actions;
	if (defined $action->{follows}) {
		push @actions, "\$self->confess_at_current_offset('$action->{else}') unless "
			. $self->compile_syntax_condition($action->{follows}) . ';';

		if (ref $action->{follows}) {
			push @actions, "\$self->next_token;" foreach 0 .. $#{$action->{follows}};
		} else {
			push @actions, "\$self->next_token;";
		}
	}

	if (defined $action->{spawn}) {
		push @actions, "push \@{\$self->{current_context}{children}}, $action->{spawn};";
	} elsif (defined $action->{extract}) {
		my @extract_items = @{$action->{extract}};
		while (@extract_items) {
			my $field = quotemeta shift @extract_items;
			my $context_type = quotemeta shift @extract_items;
			push @actions, "\$self->{current_context}{'$field'} = \$self->extract_context_result('$context_type');";
		}
	} elsif (defined $action->{extract_context}) {
		my $context_type = quotemeta $action->{extract_context};
		push @actions, "push \@{\$self->{current_context}{children}}, \$self->extract_context('$context_type');";
	}

	if (defined $action->{exit_context}) {
		push @actions, "\$self->exit_context;";
		$self->{context_default_case} = { die => 'unexpected token' } unless defined $self->{context_default_case};
	} elsif (defined $action->{enter_context}) {
		my $context_type = quotemeta $action->{enter_context};
		push @actions, "\$self->enter_context('$context_type');";
	} elsif (defined $action->{switch_context}) {
		my $context_type = quotemeta $action->{switch_context};
		push @actions, "\$self->switch_context('$context_type');";
	}

	if (defined $action->{die}) {
		my $msg = quotemeta $action->{die};
		push @actions, "\$self->confess_at_current_offset('$msg');";
	}

	if (defined $action->{warn}) {
		my $msg = quotemeta $action->{warn};
		push @actions, "warn '$msg';";
	}

	return join ("\n\t\t\t", '', '$self->next_token;', @actions) . "\n";
}

sub compile_syntax_default_action {
	my ($self, $action) = @_;

	my @actions;
	if (defined $action->{spawn}) {
		push @actions, "push \@{\$self->{current_context}{children}}, $action->{spawn};";
	}

	if (defined $action->{exit_context}) {
		push @actions, "\$self->exit_context;";
		$self->{context_default_case} = { die => 'unexpected token' } unless defined $self->{context_default_case};
	} elsif (defined $action->{enter_context}) {
		push @actions, "\$self->enter_context('$action->{enter_context}');";
	}

	if (defined $action->{die}) {
		push @actions, "\$self->confess_at_current_offset('$action->{die}');";
	}

	if (defined $action->{warn}) {
		push @actions, "warn '$action->{warn}';";
	}

	return join ("\n\t\t\t", '', @actions) . "\n";
}

1;
