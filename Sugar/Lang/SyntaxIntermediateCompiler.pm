package Sugar::Lang::SyntaxIntermediateCompiler;
use strict;
use warnings;

use feature 'say';

use Carp;
use Data::Dumper;



sub new {
	my ($class, %opts) = @_;
	my $self = bless {}, $class;

	$self->{syntax_definition_intermediate} = $opts{syntax_definition_intermediate}
			// croak "syntax_definition_intermediate argument required for Sugar::Lang::SyntaxIntermediateCompiler";

	# $self->{variables} = $self->{syntax_definition_intermediate}{variables};
	$self->{global_variable_names} = $self->{syntax_definition_intermediate}{global_variable_names};
	$self->{global_variable_expressions} = $self->{syntax_definition_intermediate}{global_variable_expressions};
	$self->{variables_scope} = { '$_' => '$context_value' };
	$self->{token_definitions} = [];
	$self->{ignored_tokens} = $self->{syntax_definition_intermediate}{ignored_tokens};
	$self->{contexts} = $self->{syntax_definition_intermediate}{contexts};
	$self->{contexts_by_name} = $self->{syntax_definition_intermediate}{contexts_by_name};
	# $self->{context_order} = $self->{syntax_definition_intermediate}{context_order};
	# $self->{item_contexts} = $self->{syntax_definition_intermediate}{item_contexts};
	# $self->{list_contexts} = $self->{syntax_definition_intermediate}{list_contexts};
	# $self->{object_contexts} = $self->{syntax_definition_intermediate}{object_contexts};
	# $self->{subroutine_order} = $self->{syntax_definition_intermediate}{subroutine_order};
	$self->{subroutines} = $self->{syntax_definition_intermediate}{subroutines};
	$self->{code_definitions} = {};
	$self->{package_identifier} = $self->{syntax_definition_intermediate}{package_identifier} // 'PACKAGE_NAME';
	$self->compile_syntax_intermediate;

	return $self
}

sub to_package {
	my ($self) = @_;

	my $code = '';

	$code .= "#!/usr/bin/env perl
package $self->{package_identifier};
use parent 'Sugar::Lang::BaseSyntaxParser';
use strict;
use warnings;

use feature 'say';



";

	$code .= "\n\n##############################\n##### variables and settings\n##############################\n\n";


	if (@{$self->{global_variable_names}}) {
		foreach my $key (@{$self->{global_variable_names}}) {
			my $value = $self->{global_variable_expressions}{$key};
			$code .= "our \$var_$key = $value;\n";
		}
		# foreach my $i (0 .. $#{$self->{variables}} / 2) {
		# 	my $var_name = $self->{variables}[$i*2];
		# 	my $var_value = $self->{variables_by_name}{$var_name};
		# 	$code .= "our \$var_$var_name = $var_value;\n";
		# }
	}
	$code .= "\n\n";

	$code .= "our \$tokens = [\n";
	if (@{$self->{token_definitions}}) {
		foreach my $token_definition (@{$self->{token_definitions}}) {
			$code .= "\t'$token_definition->{key}' => $token_definition->{value},\n";
		}
		# foreach my $i (0 .. $#{$self->{tokens}} / 2) {
		# 	$code .= "\t'$self->{tokens}[$i*2]' => $self->{tokens}[$i*2+1],\n";
		# }
	}
	$code .= "];\n\n";

	$code .= "our \$ignored_tokens = [\n";
	foreach my $token (@{$self->{ignored_tokens}}) {
		$code .= "\t'$token',\n";
	}
	$code .= "];\n\n";

	$code .= "our \$contexts = {\n";
	foreach my $context (@{$self->{contexts}}) {
		$code .= "\t$context->{identifier} => 'context_$context->{identifier}',\n";
	}
	$code .= "};\n\n";

	$code .= "\n\n##############################\n##### api\n##############################\n\n";

	$code .= '

sub new {
	my ($class, %opts) = @_;

	$opts{token_regexes} = $tokens;
	$opts{ignored_tokens} = $ignored_tokens;
	$opts{contexts} = $contexts;

	my $self = $class->SUPER::new(%opts);

	return $self
}

sub parse {
	my ($self, @args) = @_;
	return $self->SUPER::parse(@args)
}

';

	$code .= "\n\n##############################\n##### sugar contexts functions\n##############################\n\n";

	foreach my $context (@{$self->{contexts}}) {
		$code .= $self->{code_definitions}{$context->{identifier}};
		# my $identifier = $context->{identifier};
		# $code .= $self->{code_definitions}{$identifier} =~ s/\A(\s*)sub \{/$1sub context_$identifier {/r;
	}

	$code .= "\n\n##############################\n##### native perl functions\n##############################\n\n";

	foreach my $subroutine (@{$self->{subroutines}}) {
		my $subroutine_code = $subroutine->{code_block};
		$subroutine_code =~ s/\A\{\{(.*)\}\}\Z/{$1}/s;
		$code .= "sub $subroutine->{identifier} $subroutine_code\n\n";

		$code .= "caller or main(\@ARGV);\n\n" if $subroutine->{identifier} eq 'main';
	}

	$code .= "\n\n1;\n\n";

	return $code
}

sub confess_at_current_line {
	my ($self, $msg) = @_;
	confess "syntax error on line $self->{current_line}: $msg";
}

sub get_variable {
	my ($self, $variable) = @_;
	$self->confess_at_current_line("undefined variable requested: '$variable'") unless exists $self->{variables_scope}{$variable};
	return $self->{variables_scope}{$variable}
}

sub exists_variable {
	my ($self, $variable) = @_;
	return exists $self->{variables_scope}{$variable}
}

sub add_variable {
	my ($self, $variable) = @_;
	if ($variable =~ /\A\$(\w+)\Z/s) {
		$self->{variables_scope}{$variable} = "\$var_$1";
		return $self->{variables_scope}{$variable};
	} else {
		$self->confess_at_current_line("invalid variable in add_variable: '$variable'");
	}
}

sub get_function_by_name {
	my ($self, $value) = @_;
	if ($value =~ /\A\!(\w++)\Z/) {
		my $context_identifier = $1;
		if (exists $self->{contexts_by_name}{$context_identifier}) {
			return "context_$context_identifier";
		}
		# foreach my $context (@{$self->{contexts}}) {
		# 	if ($context->{identifier} eq $context_identifier) {
		# 		return "context_$context_identifier";
		# 	}
		# }
		# if (defined $self->{object_contexts}{$context_type}) {
		# 	return "context_$context_type"
		# } elsif (defined $self->{list_contexts}{$context_type}) {
		# 	return "context_$context_type"
		# } elsif (defined $self->{item_contexts}{$context_type}) {
		# 	return "context_$context_type"
		# } else {
			$self->confess_at_current_line("undefined context requested: '$context_identifier'");
		# }

	} elsif ($value =~ /\A\&(\w++)\Z/) {
		return "$1"

	} else {
		$self->confess_at_current_line("unknown context type requested: '$value'");
	}
}

sub compile_syntax_intermediate {
	my ($self) = @_;

	foreach my $key (@{$self->{global_variable_names}}) {
		my $value = $self->compile_syntax_token_value($self->{global_variable_expressions}{$key});
		$self->{global_variable_expressions}{$key} = $value;
		$self->{variables_scope}{"\$$key"} = "\$var_$key";
	}
	# my @variables = @{$self->{syntax_definition_intermediate}{variables}};
	# while (@variables) {
	# 	my $key = shift @variables;
	# 	my $value = $self->compile_syntax_token_value(shift @variables);
	# 	$self->{variables_by_name}{$key} = $value;
	# }

	foreach my $token_definition (@{$self->{syntax_definition_intermediate}{tokens}}) {
		my $key = $token_definition->{identifier};
		my $value = $self->compile_syntax_token_value($token_definition->{value});
		push @{$self->{token_definitions}}, {
			key => $key,
			value => $value,
		};
	}
	# my @token_definitions = @{$self->{syntax_definition_intermediate}{tokens}};
	# while (@token_definitions) {
	# 	my $key = shift @token_definitions;
	# 	my $value = $self->compile_syntax_token_value(shift @token_definitions);
	# 	push @{$self->{tokens}}, $key, $value;
	# }
	foreach my $context (@{$self->{syntax_definition_intermediate}{contexts}}) {
		$self->{code_definitions}{$context->{identifier}} = $self->compile_syntax_context($context);
	}
	# foreach my $context_name (keys %{$self->{syntax_definition_intermediate}{item_contexts}}) {
	# 	my $context_definition = $self->{syntax_definition_intermediate}{item_contexts}{$context_name};
	# 	$self->{code_definitions}{$context_name} = $self->compile_syntax_context('item_context', $context_name, $context_definition);
	# }
	# foreach my $context_name (keys %{$self->{syntax_definition_intermediate}{list_contexts}}) {
	# 	my $context_definition = $self->{syntax_definition_intermediate}{list_contexts}{$context_name};
	# 	$self->{code_definitions}{$context_name} = $self->compile_syntax_context('list_context', $context_name, $context_definition);
	# }
	# foreach my $context_name (keys %{$self->{syntax_definition_intermediate}{object_contexts}}) {
	# 	my $context_definition = $self->{syntax_definition_intermediate}{object_contexts}{$context_name};
	# 	$self->{code_definitions}{$context_name} = $self->compile_syntax_context('object_context', $context_name, $context_definition);
	# }
}

sub compile_syntax_token_value {
	my ($self, $value) = @_;
	if ($value->{type} eq 'regex_value') {
		return "qr$value->{value}"
	} elsif ($value->{type} eq 'substitution_regex') {
		return "sub { \$_[0] =~ $value->{value}r }"
	} elsif ($value->{type} eq 'variable_value') {
		return $self->get_variable($value->{value});
	} elsif ($value->{type} eq 'string_value') {
		return $value->{value};
	} else {
		$self->confess_at_current_line("invalid syntax token value: $value");
	}

	# if ($value =~ m#\A$Sugar::Lang::SugarGrammarParser::var_regex_regex\Z#s) {
	# 	return "qr$value"
	# } elsif ($value =~ m#\A$Sugar::Lang::SugarGrammarParser::var_substitution_regex_regex\Z#s) {
	# 	return "sub { \$_[0] =~ ${value}r }"
	# } elsif ($value =~ /\A\$\w++\Z/) {
	# 	# verify that the variable exists
	# 	return $self->get_variable($value);
	# 	# return "\$var_$1"
	# 	# return $self->compile_syntax_token_value($self->get_variable($1))
	# } else {
	# 	confess "invalid syntax token value: $value";
	# }
}

sub compile_syntax_context {
	my ($self, $context) = @_;
	# my ($self, $context_type, $context_name, $context) = @_;

	my $is_linear_context = ($context->{block}[-1]{type} eq 'return_statement'
			or $context->{block}[-1]{type} eq 'return_expression_statement');

	my @code;
# 	my $code = '
# sub {';
	my @args_list = ('$self');
	if ($context->{identifier} ne 'root') {
		push @args_list, '$context_value';
		# if ($context->{type} eq 'object_context') {
		# } elsif ($context->{type} eq 'list_context') {
		# 	push @args_list, '$context_value';
		# } else {
		# 	push @args_list, '$context_value';
		# }
	}
	my $args_list_string = join ', ', @args_list;
	push @code, "my ($args_list_string) = \@_;";

	if ($context->{identifier} eq 'root') {
		if ($context->{type} eq 'object_context') {
			push @code, "my \$context_value = {};";
		} elsif ($context->{type} eq 'list_context') {
			push @code, "my \$context_value = [];";
		} else {
			push @code, "my \$context_value;";
		}
	}

	unless ($is_linear_context) {
		# $code .= "\t\tsay 'in context $context_name';\n"; # DEBUG INLINE TREE BUILDER
		push @code, "while (\$self->more_tokens) {";

		push @code, "\tmy \@tokens;";
		push @code, '';
		push @code, $self->compile_syntax_action($context->{type}, undef, $context->{block});

		push @code, "}";
		# $code .= "\t}\n";

		push @code, "return \$context_value;";
		# if ($context->{type} eq 'object_context') {
		# 	push @code, "return \$context_value;";
		# } elsif ($context->{type} eq 'list_context') {
		# 	push @code, "return \$context_value;";
		# } else {
		# 	push @code, "return \$context_value;";
		# }

		@code = map "\t$_", @code;
	} else {
		push @code, "my \@tokens;";
		@code = map "\t$_", @code;

		push @code, '';
		push @code, $self->compile_syntax_action($context->{type}, undef, $context->{block});
	}

	# $code .= "\tmy \@tokens;\n";

	# @action_code = map "\t$_", @action_code unless $is_linear_context;
	# push @code, @action_code;

	# unless ($is_linear_context) {

	# }

	# $code .= "}\n";
	# say "compiled code: ", $code; # DEBUG INLINE TREE BUILDER
	# my $compiled = eval $code;
	# if ($@) {
	# 	confess "error compiling context type '$context_name': $@";
	# }
	# return $compiled
	# return $code

	# @code = map "\t$_", @code;

	return join '', map "$_\n", "sub context_$context->{identifier} {", @code, "}";
}

sub compile_syntax_condition {
	my ($self, $context_type, $condition, $offset) = @_;
	$offset //= 0;
	if ($condition->{type} eq 'function_match') {
		my $function = $self->get_function_by_name($condition->{function});
		if (exists $condition->{argument}) {
			my $expression_code = $self->compile_syntax_spawn_expression($context_type, $condition->{argument});
			return "\$self->$function(\$self->{tokens_index} + $offset, $expression_code)";
		} else {
			return "\$self->$function(\$self->{tokens_index} + $offset)";
		}

	} elsif ($condition->{type} eq 'variable_match') {
		$self->confess_at_current_line("invalid variable condition value: $condition->{variable}")
				unless $condition->{variable} =~ m#\A\$(\w++)\Z#s;
		# verify that the variable exists
		my $variable = $self->get_variable($1);
		# $self->get_variable($1);
		return "\$self->{tokens}[\$self->{tokens_index} + $offset][1] =~ /\\A($variable)\\Z/"

	} elsif ($condition->{type} eq 'regex_match') {
		$self->confess_at_current_line("invalid regex condition value: $condition->{regex}")
				unless $condition->{regex} =~ m#\A/(.*)/([msixpodualn]*)\Z#s;
		return "\$self->{tokens}[\$self->{tokens_index} + $offset][1] =~ /\\A($1)\\Z/$2"

	} elsif ($condition->{type} eq 'string_match') {
		$self->confess_at_current_line("invalid string condition value: $condition->{string}") unless $condition->{string} =~ /\A'.*'\Z/s;
		return "\$self->{tokens}[\$self->{tokens_index} + $offset][1] eq $condition->{string}"

	} elsif ($condition->{type} eq 'token_type_match') {
		# $self->confess_at_current_line("invalid string condition value: $condition->{string}") unless $condition->{string} =~ /\A'.*'\Z/s;
		return "\$self->{tokens}[\$self->{tokens_index} + $offset][0] eq '$condition->{value}'"

	} else {
		$self->confess_at_current_line("invalid syntax condition '$condition->{type}'");
	}
}

sub compile_syntax_match_list {
	my ($self, $context_type, $condition, $offset) = @_;
	$offset //= 0;

	my @conditions = (@{$condition->{match_conditions}}, @{$condition->{look_ahead_conditons}});
	foreach my $i (0 .. $#conditions) {
		$conditions[$i] = $self->compile_syntax_condition($context_type, $conditions[$i], $offset + $i);
	}
	return join ' and ', '$self->more_tokens', @conditions
}

sub get_syntax_match_list_tokens_eaten {
	my ($self, $condition) = @_;
	return scalar @{$condition->{match_conditions}};
}

sub syntax_match_list_as_string {
	my ($self, $condition) = @_;

	my $string = join ', ', map $self->syntax_condition_as_string($_), @{$condition->{match_conditions}};

	if (@{$condition->{look_ahead_conditons}}) {
		my $look_ahead_string = join ', ', map $self->syntax_condition_as_string($_), @{$condition->{look_ahead_conditons}};
		if ($string) {
			$string = "$string, (look-ahead: $look_ahead_string)";
		} else {
			$string = "(look-ahead: $look_ahead_string)";
		}
	}

	$string =~ s/([\\'])/\\$1/g;

	return $string;
}

sub syntax_condition_as_string {
	my ($self, $condition) = @_;
	if ($condition->{type} eq 'function_match') {
		return "$condition->{function}"

	} elsif ($condition->{type} eq 'variable_match') {
		$self->confess_at_current_line("invalid variable condition value: $condition->{variable}") unless $condition->{variable} =~ m#\A\$(\w++)\Z#s;
		return $self->get_variable($1);

	} elsif ($condition->{type} eq 'regex_match') {
		return "$condition->{regex}"

	} elsif ($condition->{type} eq 'string_match') {
		return "$condition->{string}"

	} elsif ($condition->{type} eq 'token_type_match') {
		return "$condition->{value} token"

	} else {
		$self->confess_at_current_line("invalid syntax condition '$condition->{type}'");
	}
}

sub compile_syntax_action {
	my ($self, $context_type, $condition, $actions_list) = @_;

	my @code;

	# create a new variable scope
	my $previous_variables_scope = $self->{variables_scope};
	$self->{variables_scope} = { %{$self->{variables_scope}} };

	if (defined $condition) {
		my $count = $self->get_syntax_match_list_tokens_eaten($condition);
		push @code, "my \@tokens = (\@tokens, \$self->step_tokens($count));" if $count > 0;
	# } elsif (defined $condition) {
	# 	push @code, "my \@tokens = (\@tokens, \$self->next_token->[1]);";
	# } else {
		# push @code, "my \@tokens;";
	}
	
	# my @actions = @$actions_list;
	# while (@actions) {
		# my $action = shift @actions;
	foreach my $action (@$actions_list) {
		$self->{current_line} = $action->{line_number};

		if ($action->{type} eq 'push_statement') {
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});
			if ($context_type eq 'list_context') {
				push @code, "push \@\$context_value, $expression;";
			} else {
				$self->confess_at_current_line("use of push in $context_type");
			}
		} elsif ($action->{type} eq 'assign_item_statement') {
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});
			if ($action->{variable} eq '$_') {
				push @code, "\$context_value = $expression;";
				# if ($context_type eq 'object_context') {
				# } elsif ($context_type eq 'list_context') {
				# 	push @code, "\$context_value = $expression;";
				# } else {
				# 	push @code, "\$context_value = $expression;";
				# }
			} else {
				# my $var_name = $action->{variable} =~ s/\A\$//r;
				# push @code, "\$var_$var_name = $expression;";
				if ($self->exists_variable($action->{variable})) {
					my $variable = $self->get_variable($action->{variable});
					push @code, "$variable = $expression;";
				} else {
					my $variable = $self->add_variable($action->{variable});
					push @code, "my $variable = $expression;";
				}
			}
			
		} elsif ($action->{type} eq 'assign_field_statement') {
			my $key = $self->compile_syntax_spawn_expression($context_type, $action->{key});
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});

			my $variable = $self->get_variable($action->{variable});
			# my $var_name = $action->{variable} =~ s/\A\$//r;
			# my $var_ref = $var_name eq '_' ? "\$context_value" : $self->get_variable($var_name);
			push @code, "$variable\->{$key} = $expression;";
			
		} elsif ($action->{type} eq 'assign_array_field_statement') {
			my $key = $self->compile_syntax_spawn_expression($context_type, $action->{key});
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});

			my $variable = $self->get_variable($action->{variable});
			# my $var_name = $action->{variable} =~ s/\A\$//r;
			# my $var_ref = $var_name eq '_' ? "\$context_value" : $self->get_variable($var_name);
			push @code, "push \@{$variable\->{$key}}, $expression;";
			
		} elsif ($action->{type} eq 'assign_object_field_statement') {
			my $key = $self->compile_syntax_spawn_expression($context_type, $action->{key});
			my $subkey = $self->compile_syntax_spawn_expression($context_type, $action->{subkey});
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});

			my $variable = $self->get_variable($action->{variable});
			# my $var_name = $action->{variable} =~ s/\A\$//r;
			# my $var_ref = $var_name eq '_' ? "\$context_value" : $self->get_variable($var_name);
			push @code, "$variable\->{$key}{$subkey} = $expression;";

		} elsif ($action->{type} eq 'return_statement') {
			push @code, "return \$context_value;";
			# if ($context_type eq 'object_context') {
			# } elsif ($context_type eq 'list_context') {
			# 	push @code, "return \$context_value;";
			# } else {
			# 	push @code, "return \$context_value;";
			# }

			$self->{context_default_case} //= [ { type => 'die_statement', expression => { type => 'string', string => "'unexpected token'" } } ];

		} elsif ($action->{type} eq 'return_expression_statement') {
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});
			push @code, "return $expression;";

			$self->{context_default_case} //= [ { type => 'die_statement', expression => { type => 'string', string => "'unexpected token'" } } ];

		} elsif ($action->{type} eq 'match_statement') {
			my $death_expression;
			if (defined $action->{death_expression}) {
				$death_expression = $self->compile_syntax_spawn_expression($context_type, $action->{death_expression});
			} else {
				my $match_description = $self->syntax_match_list_as_string($action->{match_list});
				$death_expression = "'expected $match_description'";
			}
			push @code, "\$self->confess_at_current_offset($death_expression)";
			push @code, "\tunless " . $self->compile_syntax_match_list($context_type, $action->{match_list}) . ";";

			my $count = $self->get_syntax_match_list_tokens_eaten($action->{match_list});
			push @code, "\@tokens = (\@tokens, \$self->step_tokens($count));" if $count > 0;

		} elsif ($action->{type} eq 'if_statement') {
			my $condition_code = $self->compile_syntax_match_list($context_type, $action->{match_list});
			my @action_code = $self->compile_syntax_action($context_type, $action->{match_list}, $action->{block});

			push @code, "if ($condition_code) {";
			push @code, @action_code;
			# push @code, "}";

			while (exists $action->{branch}) {
				$action = $action->{branch};
				if ($action->{type} eq 'elsif_statement') {
					my $condition_code = $self->compile_syntax_match_list($context_type, $action->{match_list});
					my @action_code = $self->compile_syntax_action($context_type, $action->{match_list}, $action->{block});

					push @code, "} elsif ($condition_code) {";
					push @code, @action_code;
					# push @code, "}";
				} else {
					my @action_code = $self->compile_syntax_action($context_type, $action->{match_list}, $action->{block});

					push @code, "} else {";
					push @code, @action_code;
					# push @code, "}";
				}
			}
			push @code, "}";

		} elsif ($action->{type} eq 'switch_statement') {
			my $first = 1;
			foreach my $case (@{$action->{switch_cases}}) {
				$self->{current_line} = $case->{line_number};
				if ($case->{type} eq 'match_case') {
					my $condition_code = $self->compile_syntax_match_list($context_type, $case->{match_list});
					my @action_code = $self->compile_syntax_action($context_type, $case->{match_list}, $case->{block});

					if ($first) {
						# push @code, "if ($condition_code) {$action_code\t\t\t}";
						push @code, "if ($condition_code) {";
						push @code, @action_code;
						# push @code, "}";
						$first = 0;
					} else {
						# push @code, "elsif ($condition_code) {$action_code\t\t\t}";
						push @code, "} elsif ($condition_code) {";
						push @code, @action_code;
						# push @code, "}";
					}
				} elsif ($case->{type} eq 'default_case') {
					my @action_code = $self->compile_syntax_action($context_type, undef, $case->{block});
					# push @code, "else {$action_code\t\t\t}";
					push @code, "} else {";
					push @code, @action_code;
					# push @code, "}";
				} else {
					$self->confess_at_current_line("invalid switch case type: $case->{type}");
				}
			}
			push @code, "}" unless $first;

		} elsif ($action->{type} eq 'while_statement') {
			my $condition_code = $self->compile_syntax_match_list($context_type, $action->{match_list});
			my @action_code = $self->compile_syntax_action($context_type, $action->{match_list}, $action->{block});

			# push @code, "while ($condition_code) {$action_code\t\t\t}";
			push @code, "while ($condition_code) {";
			push @code, @action_code;
			push @code, "}";


		} elsif ($action->{type} eq 'warn_statement') {
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});
			push @code, "warn ($expression);";

		} elsif ($action->{type} eq 'die_statement') {
			my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});
			push @code, "\$self->confess_at_current_offset($expression);";

		# } elsif ($action->{type} eq 'variable_assignment_statement') {
		# 	my $var_name = $action->{variable} =~ s/\A\$//r;
		# 	my $expression = $self->compile_syntax_spawn_expression($context_type, $action->{expression});

		# 	if ($self->exists_variable($var_name)) {
		# 		push @code, "\$var_$var_name = $expression;";
		# 	} else {
		# 		$self->{variables_scope}{$var_name} = "\$var_$var_name";
		# 		push @code, "my \$var_$var_name = $expression;";
		# 	}

		} else {
			die "undefined action '$action->{type}'";
		}
	}

	# unscope
	$self->{variables_scope} = $previous_variables_scope;

	return map "\t$_", @code;
	# return join ("\n\t\t\t", '', @code) . "\n";
}

sub compile_syntax_spawn_expression {
	my ($self, $context_type, $expression) = @_;

	# say "debug:", Dumper $expression;
	if ($expression->{type} eq 'access') {
		my $left = $self->compile_syntax_spawn_expression($context_type, $expression->{left_expression});
		my $right = $self->compile_syntax_spawn_expression($context_type, $expression->{right_expression});
		return "${left}->{$right}"

	} elsif ($expression->{type} eq 'undef') {
		return 'undef'

	} elsif ($expression->{type} eq 'get_token_line_number') {
		$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'")
				unless $expression->{token} =~ /\A\$(\d+)\Z/s;
		return "\$tokens[$1][2]";
	} elsif ($expression->{type} eq 'get_token_line_offset') {
		$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'")
				unless $expression->{token} =~ /\A\$(\d+)\Z/s;
		return "\$tokens[$1][3]";
	} elsif ($expression->{type} eq 'get_token_text') {
		$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'")
				unless $expression->{token} =~ /\A\$(\d+)\Z/s;
		return "\$tokens[$1][1]";

	} elsif ($expression->{type} eq 'get_context') {
		return "\$context_value"
		# if ($context_type eq 'object_context') {
		# } elsif ($context_type eq 'list_context') {
		# 	return "\$context_value"
		# } else {
		# 	return "\$context_value"
		# }

	} elsif ($expression->{type} eq 'pop_list') {
		if ($context_type eq 'list_context') {
			return "pop \@\$context_value";
		} else {
			$self->confess_at_current_line("use of pop in $context_type");
		}

	} elsif ($expression->{type} eq 'call_context') {
		# warn "got call_context: $expression";
		my $context = $self->get_function_by_name($expression->{context});
		if (exists $expression->{argument}) {
			my $expression_code = $self->compile_syntax_spawn_expression($context_type, $expression->{argument});
			return "\$self->$context($expression_code)";
		} else {
			return "\$self->$context";
		}

	} elsif ($expression->{type} eq 'call_function') {
		# warn "got call_function: $expression";
		my $function = $self->get_function_by_name($expression->{function});
		if (exists $expression->{argument}) {
			my $expression_code = $self->compile_syntax_spawn_expression($context_type, $expression->{argument});
			return "\$self->$function($expression_code)";
		} else {
			return "\$self->$function";
		}

	} elsif ($expression->{type} eq 'call_variable') {
		# warn "got call_variable: $expression->{variable}";
			my $variable = $self->get_variable($expression->{variable});
		# my $var_name = $expression->{variable} =~ s/\A\$//r;
		# $self->get_variable($var_name);
		my $expression_code = $self->compile_syntax_spawn_expression($context_type, $expression->{argument});
		return "$variable\->($expression_code)";

	} elsif ($expression->{type} eq 'variable_value') {
			my $variable = $self->get_variable($expression->{variable});
		# my $var_name = $expression->{variable} =~ s/\A\$//r;
		# $self->get_variable($var_name);
		return "$variable";

	} elsif ($expression->{type} eq 'call_substitution') {
		# warn "got call_substitution: $expression";
		my $expression_code = $self->compile_syntax_spawn_expression($context_type, $expression->{argument});
		return "$expression_code =~ $expression->{regex}r";

	} elsif ($expression->{type} eq 'string') {
		$self->confess_at_current_line("invalid spawn expression string: '$expression->{string}'") unless $expression->{string} =~ /\A'(.*)'\Z/s;
		return "'$1'";
	} elsif ($expression->{type} eq 'bareword_string') {
		return "'$expression->{value}'";
	} elsif ($expression->{type} eq 'bareword') {
		return "$expression->{value}";
	} elsif ($expression->{type} eq 'empty_list') {
		return '[]'
	} elsif ($expression->{type} eq 'empty_hash') {
		return '{}'
	} elsif ($expression->{type} eq 'list_constructor') {
		my $code = "[ ";
		foreach my $field (@{$expression->{arguments}}) {
			$code .= $self->compile_syntax_spawn_expression($context_type, $field) . ", ";
		}
		$code .= "]";
		return $code
	} elsif ($expression->{type} eq 'hash_constructor') {
		my $code = "{ ";
		my @items = @{$expression->{arguments}};
		while (@items) {
			my $field = shift @items;
			my $value = shift @items;
			$code .= $self->compile_syntax_spawn_expression($context_type, $field). " => "
					. $self->compile_syntax_spawn_expression($context_type, $value) . ", ";
		}
		$code .= "}";
		return $code

	} else {
		$self->confess_at_current_line("invalid spawn expression: '$expression->{type}'");
	}

}

1;
