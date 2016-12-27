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

	$self->{syntax_definition_intermediate} = $opts{syntax_definition_intermediate}
			// croak "syntax_definition_intermediate argument required for Sugar::Lang::SyntaxTreeBuilder";
	$self->compile_syntax_intermediate;

	return $self
}

sub parse {
	my ($self) = @_;
	$self->SUPER::parse;

	$self->{current_context} = { context_type => 'root' };
	$self->{syntax_tree} = $self->{current_context};
	$self->{context_stack} = [];
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};

	while ($self->more_tokens) {
		# confess "undefined context_type referenced '$self->{current_context}{context_type}'"
		# 		unless defined $self->{syntax_definition}{$self->{current_context}{context_type}};
		$self->{syntax_definition}{$self->{current_context}{context_type}}->($self);
	}

	return $self->{syntax_tree}
}

sub get_variable {
	my ($self, $identifier) = @_;
	confess "undefined variable requested: '$identifier'" unless exists $self->{syntax_definition_intermediate}{variables}{$identifier};
	return $self->{syntax_definition_intermediate}{variables}{$identifier}
}

sub get_context {
	my ($self, $value) = @_;
	if ($value =~ /\A\!(\w++)\Z/) {
		my $context_type = $1;
		confess "undefined context requested: '$context_type'" unless defined $self->{syntax_definition}{$context_type};
		return $context_type

	} else {
		confess "unknown context type requested: '$value'";
	}
}

sub enter_context {
	my ($self, $context_type) = @_;

	my $new_context = { context_type => $context_type };
	# push @{$self->{current_context}{children}}, $new_context;
	push @{$self->{context_stack}}, $self->{current_context};
	$self->{current_context} = $new_context;
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub nest_context {
	my ($self, $context_type) = @_;
	$self->{current_context}{children} //= [];
	my $new_context = { context_type => $context_type, children => $self->{current_context}{children} };
	# push @{$self->{current_context}{children}}, $new_context;
	push @{$self->{context_stack}}, $self->{current_context};
	$self->{current_context} = $new_context;
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub exit_context {
	my ($self) = @_;
	confess 'attempt to exit root context' if $self->{current_context}{context_type} eq 'root';

	$self->{current_context} = pop @{$self->{context_stack}};
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub switch_context {
	my ($self, $context_type) = @_;
	confess 'attempt to switch context on root context' if $self->{current_context}{context_type} eq 'root';

	$self->{current_context}{context_type} = $context_type;
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};
}

sub extract_context_result {
	my ($self, $context_type, $modifier) = @_;

	my $previous_context = $self->{current_context};
	$self->enter_context($context_type);
	my $saved_context = $self->{current_context};

	while ($self->{current_context} != $previous_context) {
		# say "debug", Dumper $self->{current_context};
		# confess "undefined context_type referenced '$self->{current_context}{context_type}'"
		# 		unless defined $self->{syntax_definition}{$self->{current_context}{context_type}};
		$self->{syntax_definition}{$self->{current_context}{context_type}}->($self);
	}
	my $result;
	if (defined $modifier and $modifier eq 'ARRAY') {
		$result = [ @{$saved_context->{children} // []} ];
	} else {
		($result) = @{$saved_context->{children}};
	}
	# say 'got result: ', Dumper $result;
	return $result
}

sub into_context {
	my ($self, $context_object) = @_;
	# my $store_type = $context_object->{type};
	# $context_object->{type} = 'context';
	my $previous_context = $self->{current_context};
	push @{$self->{context_stack}}, $self->{current_context};
	$self->{current_context} = $context_object;
	# $self->{current_syntax_context} = $self->{syntax_definition}{$self->{current_context}{context_type}};

	while ($self->{current_context} != $previous_context) {
		# confess "undefined context_type referenced '$self->{current_context}{context_type}'"
		# 		unless defined $self->{syntax_definition}{$self->{current_context}{context_type}};
		$self->{syntax_definition}{$self->{current_context}{context_type}}->($self);
	}

	return $context_object
}

sub compile_syntax_intermediate {
	my ($self) = @_;

	$self->{syntax_definition} = {};
	foreach my $context_type (keys %{$self->{syntax_definition_intermediate}{contexts}}) {
		my $context_definition = $self->{syntax_definition_intermediate}{contexts}{$context_type};
		$self->{syntax_definition}{$context_type} = $self->compile_syntax_context($context_type, $context_definition);
	}
}

sub compile_syntax_context {
	my ($self, $context_name, $context) = @_;

	my $code = '
	sub {
		my ($self) = @_;
';
	# $code .= "\t\tsay 'in context $context_name';\n"; # DEBUG INLINE TREE BUILDER

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
		my $action_code = $self->compile_syntax_action($condition, $action);

		my $debug_code = '';
		# $debug_code = "\n\t\t\tsay 'in case " . (ref $condition eq 'ARRAY' ? join ', ', @$condition : $condition) =~ s/'/\\'/gr . "';"; # DEBUG INLINE TREE BUILDER


		$code .= "\t\t" if $first_item;
		$code .= "if ($condition_code) {$debug_code$action_code\t\t} els";

		$first_item = 0;
	}

	$self->{context_default_case} //= [ 'exit_context' ];
	my $action_code = $self->compile_syntax_action(undef, $self->{context_default_case});
	unless ($first_item) {
		$code .= "e {$action_code\t\t}\n";
	} else {
		$code .= "$action_code\n";
	}

	$code .= "
		return;
	}
";
	# say "compiled code: ", $code; # DEBUG INLINE TREE BUILDER
	my $compiled = eval $code;
	if ($@) {
		confess "error compiling context type '$context_name': $@";
	}
	return $compiled
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
		$condition =~ s#/#\\/#g;
		return "\$self->is_token_val('*' => qr/$condition/, $offset)"
	} elsif ($condition =~ m#\A\$(\w++)\Z#s) {
		my $value = $self->get_variable($1);
		return $self->compile_syntax_condition($value, $offset)
	} elsif ($condition =~ m#\A/(.*)/([msixpodualn]*)\Z#s) {
		return "\$self->is_token_val('*' => qr/\\A$1\\Z/$2, $offset)"
	} elsif ($condition =~ /\A'.*'\Z/s) {
		return "\$self->is_token_val('*' => $condition, $offset)"
	} else {
		confess "invalid syntax condition '$condition'";
	}
}

sub compile_syntax_action {
	my ($self, $condition, $actions_list) = @_;

	my @code;
	push @code, "my \@tokens;";

	if (defined $condition and ref $condition eq 'ARRAY') {
		push @code, "push \@tokens, \$self->next_token->[1];" foreach 0 .. $#$condition;
	} elsif (defined $condition) {
		push @code, "push \@tokens, \$self->next_token->[1];";
	}
	
	my @actions = @$actions_list;
	while (@actions) {
		my $action = shift @actions;

		if ($action eq 'spawn') {
			push @code, "push \@{\$self->{current_context}{children}}, " . $self->compile_syntax_spawn_expression(shift @actions) . ";";
		# } elsif ($action eq 'spawn_into_context') {
		# 	push @code, "push \@{\$self->{current_context}{children}}, \$self->into_context("
		# 			. $self->compile_syntax_spawn_expression(shift @actions) . ");";
		} elsif ($action eq 'assign') {
			my @assign_items = @{shift @actions};
			while (@assign_items) {
				my $field = shift @assign_items;
				my $value = shift @assign_items;
				if (ref $value eq 'HASH') {
					my $key = shift @assign_items;
					$key = $self->compile_syntax_spawn_sub_expression($key);
					$value = shift @assign_items;
					$field = $self->compile_syntax_spawn_sub_expression($field);
					push @code, "\$self->{current_context}{$field}{$key} = " . $self->compile_syntax_spawn_expression($value) . ";";
				} elsif (ref $value eq 'ARRAY' and @$value == 0) {
					$value = shift @assign_items;
					$field = $self->compile_syntax_spawn_sub_expression($field);
					push @code, "push \@{\$self->{current_context}{$field}}, " . $self->compile_syntax_spawn_expression($value) . ";";
				} else {
					$field = $self->compile_syntax_spawn_sub_expression($field);
					push @code, "\$self->{current_context}{$field} = " . $self->compile_syntax_spawn_expression($value) . ";";
				}
			}
		}

		if ($action eq 'exit_context') {
			push @code, "\$self->exit_context;";
			$self->{context_default_case} = [ die => 'unexpected token' ] unless defined $self->{context_default_case};
		} elsif ($action eq 'enter_context') {
			my $context_type = shift (@actions) =~ s/(['\\])/\\$1/gr;
			push @code, "\$self->enter_context(\$self->get_context('$context_type'));";
		} elsif ($action eq 'switch_context') {
			my $context_type = shift (@actions) =~ s/(['\\])/\\$1/gr;
			push @code, "\$self->switch_context(\$self->get_context('$context_type'));";
		} elsif ($action eq 'nest_context') {
			my $context_type = shift (@actions) =~ s/(['\\])/\\$1/gr;
			push @code, "\$self->nest_context(\$self->get_context('$context_type'));";
		}

		if ($action eq 'die') {
			# my $msg = shift (@actions) =~ s/(['\\])/\\$1/gr;
			push @code, "\$self->confess_at_current_offset(" . $self->compile_syntax_spawn_sub_expression(shift @actions) . ");";
			# push @code, "\$self->confess_at_current_offset('$msg');";
		}

		if ($action eq 'warn') {
			# my $msg = shift (@actions) =~ s/(['\\])/\\$1/gr;
			push @code, "warn " . $self->compile_syntax_spawn_sub_expression(shift @actions) . ";";
		}
	}



	return join ("\n\t\t\t", '', @code) . "\n";
}

sub compile_syntax_spawn_expression {
	my ($self, $expression) = @_;
	if (not defined $expression) {
		return 'undef'
	} elsif (ref $expression eq 'HASH') {
		return '{}'
	} elsif (ref $expression eq 'ARRAY' and @$expression == 0) {
		return '[]'
	} elsif (ref $expression eq 'ARRAY' and @$expression == 1) {
		my $context_type = $expression->[0] =~ s/'/\\'/gr;
		return "\$self->extract_context_result(\$self->get_context('$context_type'), 'ARRAY')"
	} elsif (ref $expression eq 'ARRAY') {
		my $code = "{ ";
		my @items = @$expression;
		while (@items) {
			my $field = quotemeta shift @items;
			my $value = shift @items;
			$code .= "'$field' => " . $self->compile_syntax_spawn_sub_expression($value) . ", ";
		}
		$code .= "}";
		return $code
	} else {
		return $self->compile_syntax_spawn_sub_expression($expression)
	}
}

sub compile_syntax_spawn_sub_expression {
	my ($self, $expression) = @_;

	if (not defined $expression) {
		return "undef";
	} elsif ($expression =~ /\A\![a-zA-Z_][a-zA-Z_0-9]*\Z/) {
		return "\$self->extract_context_result(\$self->get_context('$expression'))";
	} elsif ($expression =~ /\A\$previous_spawn\Z/) {
		return "pop \@{\$self->{current_context}{children}}";
	} elsif ($expression =~ /\A\$(\d+)\Z/) {
		return "\$tokens[$1]";
	} elsif ($expression =~ /\A'(.*)'\Z/s) {
		my $value = $1;
		return "'$value'";
	} else {
		confess "invalid spawn expression: '$expression'";
	}
}

1;
