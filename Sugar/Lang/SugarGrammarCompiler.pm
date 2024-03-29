#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';

package Sugar::Lang::SugarGrammarCompiler;

	sub new {
		my ($self, $args) = @_;
		$self = bless {}, $self;
		if (exists($args->{compile_standalone})) {
			$self->{compile_standalone} = $args->{compile_standalone};
		} else {
			$self->{compile_standalone} = 0;
		}
		if (exists($args->{syntax_definition_intermediate})) {
			$self->load_syntax_definition_intermediate($args->{syntax_definition_intermediate});
		} else {
			die "syntax_definition_intermediate argument required for Sugar::Lang::SugarGrammarCompiler";
		}
		return $self;
	}
	
	sub load_syntax_definition_intermediate {
		my ($self, $intermediate) = @_;
		$self->{syntax_definition_intermediate} = $intermediate;
		$self->{global_variable_names} = $self->{syntax_definition_intermediate}->{global_variable_names};
		$self->{global_variable_expressions} = $self->{syntax_definition_intermediate}->{global_variable_expressions};
		$self->{variables_scope} = { '$_' => ('$context_value') };
		$self->{tokens_scope_count} = 0;
		$self->{token_definitions} = [];
		$self->{ignored_tokens} = $self->{syntax_definition_intermediate}->{ignored_tokens};
		$self->{contexts} = $self->{syntax_definition_intermediate}->{contexts};
		$self->{contexts_by_name} = $self->{syntax_definition_intermediate}->{contexts_by_name};
		$self->{subroutines} = $self->{syntax_definition_intermediate}->{subroutines};
		$self->{code_definitions} = {};
		if (exists($self->{syntax_definition_intermediate}->{package_identifier})) {
			$self->{package_identifier} = $self->{syntax_definition_intermediate}->{package_identifier};
		} else {
			$self->{package_identifier} = 'PACKAGE_NAME';
		}
	}
	
	sub to_package {
		my ($self) = @_;
		my $code = '';
		$code .= "#!/usr/bin/env perl
package $self->{package_identifier};
";
		if (($self->{compile_standalone} == 0)) {
			$code .= "use parent 'Sugar::Lang::BaseSyntaxParser';\n";
		}
		$code .= "use strict;
use warnings;

use feature 'say';



";
		$code .= "\n\n##############################\n##### variables and settings\n##############################\n\n";
		if ((0 < scalar(@{$self->{global_variable_names}}))) {
			foreach my $key (@{$self->{global_variable_names}}) {
				my $value = $self->{global_variable_expressions}->{$key};
				$code .= "our \$var_$key = $value;\n";
			}
		}
		$code .= "\n\n";
		$code .= "our \$tokens = [\n";
		if ((0 < scalar(@{$self->{token_definitions}}))) {
			foreach my $token_definition (@{$self->{token_definitions}}) {
				$code .= "\t'$token_definition->{key}' => $token_definition->{value},\n";
			}
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
		if ($self->{compile_standalone}) {
			$code .= $self->get_standalone_functionality();
		} else {
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
		}
		$code .= "\n\n##############################\n##### sugar contexts functions\n##############################\n\n";
		foreach my $context (@{$self->{contexts}}) {
			$code .= $self->{code_definitions}->{$context->{identifier}};
		}
		$code .= "\n\n##############################\n##### native perl functions\n##############################\n\n";
		foreach my $subroutine (@{$self->{subroutines}}) {
			my $subroutine_code = $subroutine->{code_block};
			$subroutine_code = ($subroutine_code =~ s/\A\{\{(.*)\}\}\Z/{$1}/sr);
			$code .= "sub $subroutine->{identifier} $subroutine_code\n\n";
			if (($subroutine->{identifier} eq 'main')) {
				$code .= "caller or main(\@ARGV);\n\n";
			}
		}
		$code .= "\n\n1;\n\n";
		return $code;
	}
	
	sub confess_at_current_line {
		my ($self, $msg) = @_;
		die "syntax error on line $self->{current_line}: $msg";
	}
	
	sub get_variable {
		my ($self, $variable) = @_;
		if (not (exists($self->{variables_scope}->{$variable}))) {
			$self->confess_at_current_line("undefined variable requested: '$variable'");
		}
		return $self->{variables_scope}->{$variable};
	}
	
	sub exists_variable {
		my ($self, $variable) = @_;
		return exists($self->{variables_scope}->{$variable});
	}
	
	sub add_variable {
		my ($self, $variable) = @_;
		if (($variable =~ /\A\$(\w+)\Z/s)) {
			$self->{variables_scope}->{$variable} = "\$var_$1";
			return $self->{variables_scope}->{$variable};
		} else {
			$self->confess_at_current_line("invalid variable in add_variable: '$variable'");
		}
	}
	
	sub get_function_by_name {
		my ($self, $name) = @_;
		if (($name =~ /\A\!(\w++)\Z/)) {
			my $context_identifier = $1;
			if (exists($self->{contexts_by_name}->{$context_identifier})) {
				return "context_$context_identifier";
			} else {
				$self->confess_at_current_line("undefined context requested: '$context_identifier'");
			}
		} elsif (($name =~ /\A\&(\w++)\Z/)) {
			return "$1";
		} else {
			$self->confess_at_current_line("unknown context type requested: '$name'");
		}
	}
	
	sub compile_syntax_intermediate {
		my ($self) = @_;
		foreach my $key (@{$self->{global_variable_names}}) {
			my $value = $self->compile_syntax_token_value($self->{global_variable_expressions}->{$key});
			$self->{global_variable_expressions}->{$key} = $value;
			$self->{variables_scope}->{"\$$key"} = "\$var_$key";
		}
		foreach my $token_definition (@{$self->{syntax_definition_intermediate}->{tokens}}) {
			my $key = $token_definition->{identifier};
			my $value = $self->compile_syntax_token_value($token_definition->{value});
			push @{$self->{token_definitions}}, { key => ($key), value => ($value) };
		}
		foreach my $context (@{$self->{syntax_definition_intermediate}->{contexts}}) {
			$self->{code_definitions}->{$context->{identifier}} = $self->compile_syntax_context($context);
		}
	}
	
	sub compile_syntax_token_value {
		my ($self, $value) = @_;
		if (($value->{type} eq 'regex_value')) {
			return "qr$value->{value}";
		} elsif (($value->{type} eq 'substitution_regex_value')) {
			return "sub { \$_[0] =~ $value->{value}r }";
		} elsif (($value->{type} eq 'variable_value')) {
			return $self->get_variable($value->{value});
		} elsif (($value->{type} eq 'string_value')) {
			return $value->{value};
		} else {
			$self->confess_at_current_line("invalid syntax token value: $value->{type}");
		}
	}
	
	sub compile_syntax_context {
		my ($self, $context) = @_;
		$self->{current_context} = $context;
		my $is_linear_context = 0;
		my $last_action;
		foreach my $action (@{$context->{block}}) {
			$last_action = $action;
		}
		if ($last_action) {
			if (($last_action->{type} eq 'return_statement')) {
				$is_linear_context = 1;
			} elsif (($last_action->{type} eq 'return_expression_statement')) {
				$is_linear_context = 1;
			}
		}
		my $code = [];
		my $args_list = [];
		push @{$args_list}, '$self';
		if (($context->{identifier} ne 'root')) {
			push @{$args_list}, '$context_value';
		}
		my $args_list_string = join(', ', @{$args_list});
		push @{$code}, "my ($args_list_string) = \@_;";
		if (($context->{identifier} eq 'root')) {
			if (($context->{context_type} eq 'object')) {
				push @{$code}, "my \$context_value = {};";
			} elsif (($context->{context_type} eq 'list')) {
				push @{$code}, "my \$context_value = [];";
			} else {
				push @{$code}, "my \$context_value;";
			}
		}
		if ($is_linear_context) {
			push @{$code}, "my \@tokens;";
			push @{$code}, "my \$save_tokens_index = \$self->{tokens_index};";
			$code = [ map { "\t$_" } @{$code} ];
			push @{$code}, '';
			push @{$code}, @{$self->compile_syntax_action(0, $context->{block})};
		} else {
			push @{$code}, "my \$last_loop_index = -1;";
			push @{$code}, "while (1) {";
			push @{$code}, "\t\$self->confess_at_current_offset('infinite loop in context_$context->{identifier}')";
			push @{$code}, "\t\t\tif \$last_loop_index == \$self->{tokens_index};";
			push @{$code}, "\t\$last_loop_index = \$self->{tokens_index};";
			push @{$code}, "\tmy \@tokens;";
			push @{$code}, "my \$save_tokens_index = \$self->{tokens_index};";
			push @{$code}, '';
			push @{$code}, @{$self->compile_syntax_action(0, $context->{block})};
			push @{$code}, "}";
			push @{$code}, "return \$context_value;";
			$code = [ map { "\t$_" } @{$code} ];
		}
		my $all_code = [];
		push @{$all_code}, "sub context_$context->{identifier} {";
		push @{$all_code}, @{$code};
		push @{$all_code}, "}";
		return join('', @{[ map { "$_\n" } @{$all_code} ]});
	}
	
	sub compile_syntax_condition {
		my ($self, $condition, $offset) = @_;
		my $tokens_array_offset = $offset;
		$tokens_array_offset += $self->{tokens_scope_count};
		my $token_condition_string;
		if (($condition->{type} eq 'optional_loop_matchgroup')) {
			my $main_condition = $self->compile_syntax_branching_match_list_offset($condition->{branching_match_list}, $offset);
			return "(do { my \$save_tokens_index = \$self->{tokens_index}; while ($main_condition)
								{ \$save_tokens_index = \$self->{tokens_index}; }
								\$self->{tokens_index} = \$save_tokens_index; 1; })";
		} elsif (($condition->{type} eq 'optional_matchgroup')) {
			my $main_condition = $self->compile_syntax_branching_match_list_offset($condition->{branching_match_list}, $offset);
			return "(do { my \$save_tokens_index = \$self->{tokens_index}; if ($main_condition)
								{ \$save_tokens_index = \$self->{tokens_index}; }
								\$self->{tokens_index} = \$save_tokens_index; 1; })";
		} elsif (($condition->{type} eq 'lookahead_matchgroup')) {
			my $main_condition = $self->compile_syntax_branching_match_list_offset($condition->{branching_match_list}, $offset);
			return "(do { my \$save_tokens_index = \$self->{tokens_index}; my \$lookahead_result = ($main_condition);
								\$self->{tokens_index} = \$save_tokens_index; \$lookahead_result; })";
		} elsif (($condition->{type} eq 'function_match')) {
			my $function = $self->get_function_by_name($condition->{function});
			if (exists($condition->{argument})) {
				my $expression_code = $self->compile_syntax_spawn_expression($condition->{argument});
				my $token_expression = "\$self->$function(\$self->{tokens_index}, $expression_code)";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = $token_memory_expression;
			} else {
				my $token_expression = "\$self->$function(\$self->{tokens_index})";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = $token_memory_expression;
			}
		} elsif (($condition->{type} eq 'context_match')) {
			my $context = $self->get_function_by_name($condition->{identifier});
			if (exists($condition->{argument})) {
				my $expression_code = $self->compile_syntax_spawn_expression($condition->{argument});
				my $token_expression = "\$self->$context($expression_code)";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = $token_memory_expression;
			} else {
				my $token_expression = "\$self->$context";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = $token_memory_expression;
			}
		} elsif (($condition->{type} eq 'variable_match')) {
			if (($condition->{variable} =~ /\A\$(\w++)\Z/s)) {
				my $variable = $self->get_variable($1);
				my $token_expression = "\$self->{tokens}[\$self->{tokens_index}++]";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = "$token_memory_expression\->[1] =~ /\\A($variable)\\Z/";
			} else {
				$self->confess_at_current_line("invalid variable condition value: $condition->{variable}");
			}
		} elsif (($condition->{type} eq 'regex_match')) {
			if (($condition->{regex} =~ /\A\/(.*)\/([msixpodualn]*)\Z/s)) {
				my $token_expression = "\$self->{tokens}[\$self->{tokens_index}++]";
				my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
				$token_condition_string = "$token_memory_expression\->[1] =~ /\\A($1)\\Z/$2";
			} else {
				$self->confess_at_current_line("invalid regex condition value: $condition->{regex}");
			}
		} elsif (($condition->{type} eq 'string_match')) {
			my $token_expression = "\$self->{tokens}[\$self->{tokens_index}++]";
			my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
			$token_condition_string = "$token_memory_expression\->[1] eq $condition->{string}";
		} elsif (($condition->{type} eq 'token_type_match')) {
			my $token_expression = "\$self->{tokens}[\$self->{tokens_index}++]";
			my $token_memory_expression = "(\$tokens[$tokens_array_offset] = $token_expression)";
			$token_condition_string = "$token_memory_expression\->[0] eq '$condition->{value}'";
		} elsif (($condition->{type} eq 'assignment_nonmatch')) {
			$token_condition_string = "1";
		} elsif (($condition->{type} eq 'warn_match')) {
			my $expression = $self->compile_syntax_spawn_expression($condition->{argument});
			$token_condition_string = "(warn($expression) or do { 1 })";
		} elsif (($condition->{type} eq 'death_match')) {
			my $expression = $self->compile_syntax_spawn_expression($condition->{argument});
			$token_condition_string = "\$self->confess_at_current_offset($expression)";
		} elsif (($condition->{type} eq 'return_match')) {
			$token_condition_string = "(return \$context_value)";
		} else {
			$self->confess_at_current_line("invalid syntax condition '$condition->{type}'");
		}
		if (exists($condition->{assign_variable})) {
			my $variable;
			if ($self->exists_variable($condition->{assign_variable})) {
				$variable = $self->get_variable($condition->{assign_variable});
			} else {
				$variable = $self->add_variable($condition->{assign_variable});
				$variable = "my $variable";
			}
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and (($variable = $value_expression) or do { 1 }))";
		}
		if (exists($condition->{assign_object_value})) {
			my $variable = $condition->{assign_object_value};
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and do { \$context_value->{$variable} = $value_expression; 1 })";
		}
		if (exists($condition->{assign_object_list_value})) {
			my $variable = $condition->{assign_object_list_value};
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and do { push \@{\$context_value->{$variable}}, $value_expression; 1 })";
		}
		if (exists($condition->{assign_object_expression_value})) {
			my $key_expression = $self->compile_syntax_spawn_expression($condition->{assign_object_expression_value});
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and do { \$context_value->{$key_expression} = $value_expression; 1 })";
		}
		if (exists($condition->{assign_object_expression_list_value})) {
			my $key_expression = $self->compile_syntax_spawn_expression($condition->{assign_object_expression_list_value});
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and do { push \@{\$context_value->{$key_expression}}, $value_expression; 1 })";
		}
		if (exists($condition->{assign_list_value})) {
			my $value_expression;
			if (($condition->{type} eq 'function_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'context_match')) {
				$value_expression = "\$tokens[$tokens_array_offset]";
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				$value_expression = $self->compile_syntax_spawn_expression($condition->{expression});
			} else {
				$value_expression = "\$tokens[$tokens_array_offset][1]";
			}
			$token_condition_string = "($token_condition_string and do { push \@\$context_value, $value_expression; 1 })";
		}
		if (exists($condition->{assign_object_type})) {
			my $type_value = $condition->{assign_object_type};
			$token_condition_string = "($token_condition_string and \$context_value->{type} = '$type_value')";
		}
		return $token_condition_string;
	}
	
	sub compile_syntax_branching_match_list {
		my ($self, $branching_match_list) = @_;
		return join(" \n\t\t\t\tor ", @{[ map { "($_)" } @{[ map { $self->compile_syntax_match_list_branch($_, 0) } @{$branching_match_list} ]} ]});
	}
	
	sub compile_syntax_branching_match_list_offset {
		my ($self, $branching_match_list, $offset) = @_;
		return join(" \n\t\t\t\tor ", @{[ map { "($_)" } @{[ map { $self->compile_syntax_match_list_branch($_, $offset) } @{$branching_match_list} ]} ]});
	}
	
	sub compile_syntax_match_list_branch {
		my ($self, $match_list_branches, $offset) = @_;
		my $compiled_conditions = [];
		my $match_length = $self->get_match_list_match_length($match_list_branches->{match_conditions});
		push @{$compiled_conditions}, "((\$self->{tokens_index} = \$save_tokens_index) + $match_length <= \@{\$self->{tokens}})";
		push @{$compiled_conditions}, @{$self->compile_syntax_match_list_specific($match_list_branches->{match_conditions}, $offset)};
		return join(' and ', @{$compiled_conditions});
	}
	
	sub compile_syntax_match_list_specific {
		my ($self, $match_list, $i) = @_;
		my $compiled_conditions = [];
		foreach my $condition (@{$match_list}) {
			push @{$compiled_conditions}, $self->compile_syntax_condition($condition, $i);
			$i += 1;
		}
		return $compiled_conditions;
	}
	
	sub get_syntax_match_list_tokens_eaten {
		my ($self, $match_list) = @_;
		my $i = 0;
		foreach my $branch (@{$match_list}) {
			foreach my $condition (@{$branch->{match_conditions}}) {
				if (($condition->{type} eq 'optional_loop_matchgroup')) {
				} elsif (($condition->{type} eq 'optional_matchgroup')) {
				} elsif (($condition->{type} eq 'lookahead_matchgroup')) {
				} elsif (($condition->{type} eq 'assignment_nonmatch')) {
				} elsif (($condition->{type} eq 'warn_match')) {
				} elsif (($condition->{type} eq 'death_match')) {
				} elsif (($condition->{type} eq 'return_match')) {
				} else {
					$i += 1;
				}
			}
		}
		return $i;
	}
	
	sub get_match_list_match_length {
		my ($self, $match_list) = @_;
		my $i = 0;
		foreach my $condition (@{$match_list}) {
			if (($condition->{type} eq 'optional_loop_matchgroup')) {
			} elsif (($condition->{type} eq 'optional_matchgroup')) {
			} elsif (($condition->{type} eq 'lookahead_matchgroup')) {
			} elsif (($condition->{type} eq 'assignment_nonmatch')) {
			} elsif (($condition->{type} eq 'function_match')) {
			} elsif (($condition->{type} eq 'context_match')) {
			} elsif (($condition->{type} eq 'warn_match')) {
			} elsif (($condition->{type} eq 'death_match')) {
			} elsif (($condition->{type} eq 'return_match')) {
			} else {
				$i += 1;
			}
		}
		return $i;
	}
	
	sub get_syntax_match_list_tokens_list {
		my ($self, $match_list) = @_;
		my $token_count = scalar(@{$match_list->{match_conditions}});
		my $i = 0;
		my $tokens_list = [];
		while (($i < $token_count)) {
			push @{$tokens_list}, "\$token$i";
			$i += 1;
		}
		return join(', ', @{$tokens_list});
	}
	
	sub syntax_match_list_as_string {
		my ($self, $match_list) = @_;
		return join(' or ', @{[ map { $self->syntax_match_list_branch_as_string($_) } @{$match_list} ]});
	}
	
	sub syntax_match_list_branch_as_string {
		my ($self, $match_list) = @_;
		my $conditions_string = join(', ', @{[ map { $self->syntax_condition_as_string($_) } @{$match_list->{match_conditions}} ]});
		return $conditions_string;
	}
	
	sub syntax_condition_as_string {
		my ($self, $condition) = @_;
		if (($condition->{type} eq 'optional_loop_matchgroup')) {
			return $self->syntax_match_list_as_string($condition->{branching_match_list});
		} elsif (($condition->{type} eq 'optional_matchgroup')) {
			my $condition_string = $self->syntax_match_list_as_string($condition->{branching_match_list});
			return "[ $condition_string ]";
		} elsif (($condition->{type} eq 'lookahead_matchgroup')) {
			my $condition_string = $self->syntax_match_list_as_string($condition->{branching_match_list});
			return "( $condition_string )";
		} elsif (($condition->{type} eq 'function_match')) {
			return "$condition->{function}";
		} elsif (($condition->{type} eq 'context_match')) {
			return "$condition->{identifier}";
		} elsif (($condition->{type} eq 'variable_match')) {
			return $self->get_variable($condition->{variable});
		} elsif (($condition->{type} eq 'regex_match')) {
			return ("$condition->{regex}" =~ s/([\\'])/\\$1/gr);
		} elsif (($condition->{type} eq 'string_match')) {
			return ("$condition->{string}" =~ s/([\\'])/\\$1/gr);
		} elsif (($condition->{type} eq 'token_type_match')) {
			return "$condition->{value} token";
		} elsif (($condition->{type} eq 'warn_match')) {
			return "";
		} elsif (($condition->{type} eq 'death_match')) {
			return "";
		} elsif (($condition->{type} eq 'return_match')) {
			return "";
		} elsif (($condition->{type} eq 'assignment_nonmatch')) {
			return "";
		} else {
			$self->confess_at_current_line("invalid syntax condition '$condition->{type}'");
		}
	}
	
	sub compile_syntax_action {
		my ($self, $match_list, $actions_list) = @_;
		my $code = [];
		my $previous_variables_scope = $self->{variables_scope};
		$self->{variables_scope} = { %{$previous_variables_scope} };
		my $previous_tokens_scope_count = $self->{tokens_scope_count};
		if ($match_list) {
			my $count = $self->get_syntax_match_list_tokens_eaten($match_list);
			if (($count > 0)) {
				push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
				$self->{tokens_scope_count} += $count;
			}
		}
		foreach my $action (@{$actions_list}) {
			$self->{current_line} = $action->{line_number};
			if (($action->{type} eq 'push_statement')) {
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				if (($self->{current_context}->{context_type} eq 'list')) {
					push @{$code}, "push \@\$context_value, $expression;";
				} else {
					$self->confess_at_current_line("use of push in $self->{current_context}{type}");
				}
			} elsif (($action->{type} eq 'assign_item_statement')) {
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				if ($self->exists_variable($action->{variable})) {
					my $variable = $self->get_variable($action->{variable});
					push @{$code}, "$variable = $expression;";
				} else {
					my $variable = $self->add_variable($action->{variable});
					push @{$code}, "my $variable = $expression;";
				}
			} elsif (($action->{type} eq 'assign_field_statement')) {
				my $key = $self->compile_syntax_spawn_expression($action->{key});
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				my $variable = $self->get_variable($action->{variable});
				push @{$code}, "$variable\->{$key} = $expression;";
			} elsif (($action->{type} eq 'assign_array_field_statement')) {
				my $key = $self->compile_syntax_spawn_expression($action->{key});
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				my $variable = $self->get_variable($action->{variable});
				push @{$code}, "push \@{$variable\->{$key}}, $expression;";
			} elsif (($action->{type} eq 'assign_object_field_statement')) {
				my $key = $self->compile_syntax_spawn_expression($action->{key});
				my $subkey = $self->compile_syntax_spawn_expression($action->{subkey});
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				my $variable = $self->get_variable($action->{variable});
				push @{$code}, "$variable\->{$key}{$subkey} = $expression;";
			} elsif (($action->{type} eq 'return_statement')) {
				push @{$code}, "return \$context_value;";
				if (not ($self->{context_default_case})) {
					$self->{context_default_case} = [ { type => ('die_statement'), expression => ({ type => ('string'), string => ("'unexpected token'") }) } ];
				}
			} elsif (($action->{type} eq 'return_expression_statement')) {
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				push @{$code}, "return $expression;";
				if (not ($self->{context_default_case})) {
					$self->{context_default_case} = [ { type => ('die_statement'), expression => ({ type => ('string'), string => ("'unexpected token'") }) } ];
				}
			} elsif (($action->{type} eq 'match_statement')) {
				my $death_expression;
				if ($action->{death_expression}) {
					$death_expression = $self->compile_syntax_spawn_expression($action->{death_expression});
				} else {
					my $match_description = $self->syntax_match_list_as_string($action->{match_list});
					$death_expression = "'expected $match_description'";
				}
				my $match_expression = $self->compile_syntax_branching_match_list($action->{match_list});
				push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, "\$self->confess_at_offset($death_expression, \$save_tokens_index)";
				push @{$code}, "\tunless $match_expression;";
				my $count = $self->get_syntax_match_list_tokens_eaten($action->{match_list});
				if (($count > 0)) {
					push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
					$self->{tokens_scope_count} += $count;
				}
			} elsif (($action->{type} eq 'if_statement')) {
				my $condition_code = $self->compile_syntax_branching_match_list($action->{match_list});
				my $action_code = $self->compile_syntax_action($action->{match_list}, $action->{block});
				push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, "if ($condition_code) {";
				push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, @{$action_code};
				push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
				my $branch = $action;
				while (exists($branch->{branch})) {
					$branch = $branch->{branch};
					if (($branch->{type} eq 'elsif_statement')) {
						my $condition_code = $self->compile_syntax_branching_match_list($branch->{match_list});
						my $action_code = $self->compile_syntax_action($branch->{match_list}, $branch->{block});
						push @{$code}, "} elsif ($condition_code) {";
						push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
						push @{$code}, @{$action_code};
						push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
					} else {
						my $action_code = $self->compile_syntax_action($branch->{match_list}, $branch->{block});
						push @{$code}, "} else {";
						push @{$code}, "\t\$self->{tokens_index} = \$save_tokens_index;";
						push @{$code}, @{$action_code};
						push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
					}
				}
				push @{$code}, "}";
				push @{$code}, "\$self->{tokens_index} = \$save_tokens_index;";
			} elsif (($action->{type} eq 'switch_statement')) {
				my $first = 1;
				foreach my $case (@{$action->{switch_cases}}) {
					$self->{current_line} = $case->{line_number};
					if (($case->{type} eq 'match_case')) {
						my $condition_code = $self->compile_syntax_branching_match_list($case->{match_list});
						my $action_code = $self->compile_syntax_action($case->{match_list}, $case->{block});
						if ($first) {
							push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
							push @{$code}, "if ($condition_code) {";
							push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
							push @{$code}, @{$action_code};
							push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
							$first = 0;
						} else {
							push @{$code}, "} elsif ($condition_code) {";
							push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
							push @{$code}, @{$action_code};
							push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
						}
					} elsif (($case->{type} eq 'default_case')) {
						my $action_code = $self->compile_syntax_action(0, $case->{block});
						push @{$code}, "} else {";
						push @{$code}, "\t\$self->{tokens_index} = \$save_tokens_index;";
						push @{$code}, @{$action_code};
						push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
					} else {
						$self->confess_at_current_line("invalid switch case type: $case->{type}");
					}
				}
				if (not ($first)) {
					push @{$code}, "}";
				}
				push @{$code}, "\$self->{tokens_index} = \$save_tokens_index;";
			} elsif (($action->{type} eq 'while_statement')) {
				my $condition_code = $self->compile_syntax_branching_match_list($action->{match_list});
				my $action_code = $self->compile_syntax_action($action->{match_list}, $action->{block});
				push @{$code}, "\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, "while ($condition_code) {";
				push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, @{$action_code};
				push @{$code}, "\t\$save_tokens_index = \$self->{tokens_index};";
				push @{$code}, "}";
				push @{$code}, "\$self->{tokens_index} = \$save_tokens_index;";
			} elsif (($action->{type} eq 'warn_statement')) {
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				push @{$code}, "warn ($expression);";
			} elsif (($action->{type} eq 'die_statement')) {
				my $expression = $self->compile_syntax_spawn_expression($action->{expression});
				push @{$code}, "\$self->confess_at_current_offset($expression);";
			} else {
				die "undefined action '$action->{type}'";
			}
		}
		$self->{variables_scope} = $previous_variables_scope;
		$self->{tokens_scope_count} = $previous_tokens_scope_count;
		return [ map { "\t$_" } @{$code} ];
	}
	
	sub compile_syntax_spawn_expression {
		my ($self, $expression) = @_;
		if (($expression->{type} eq 'access')) {
			my $left = $self->compile_syntax_spawn_expression($expression->{left_expression});
			my $right = $self->compile_syntax_spawn_expression($expression->{right_expression});
			return "${left}->{$right}";
		} elsif (($expression->{type} eq 'undef')) {
			return 'undef';
		} elsif (($expression->{type} eq 'get_raw_token')) {
			if (($expression->{token} =~ /\A\$(\d+)\Z/s)) {
				return "\$tokens[$1]";
			} else {
				$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'");
			}
		} elsif (($expression->{type} eq 'get_token_type')) {
			if (($expression->{token} =~ /\A\$(\d+)\Z/s)) {
				return "\$tokens[$1][0]";
			} else {
				$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'");
			}
		} elsif (($expression->{type} eq 'get_token_text')) {
			if (($expression->{token} =~ /\A\$(\d+)\Z/s)) {
				return "\$tokens[$1][1]";
			} else {
				$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'");
			}
		} elsif (($expression->{type} eq 'get_token_line_number')) {
			if (($expression->{token} =~ /\A\$(\d+)\Z/s)) {
				return "\$tokens[$1][2]";
			} else {
				$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'");
			}
		} elsif (($expression->{type} eq 'get_token_line_offset')) {
			if (($expression->{token} =~ /\A\$(\d+)\Z/s)) {
				return "\$tokens[$1][3]";
			} else {
				$self->confess_at_current_line("invalid spawn expression token: '$expression->{token}'");
			}
		} elsif (($expression->{type} eq 'get_context')) {
			return "\$context_value";
		} elsif (($expression->{type} eq 'pop_list')) {
			if (($self->{current_context}->{context_type} eq 'list_context')) {
				return "pop \@\$context_value";
			} else {
				$self->confess_at_current_line("use of pop in $self->{current_context}{type}");
			}
		} elsif (($expression->{type} eq 'call_context')) {
			my $context = $self->get_function_by_name($expression->{context});
			if (exists($expression->{argument})) {
				my $expression_code = $self->compile_syntax_spawn_expression($expression->{argument});
				return "\$self->$context($expression_code)";
			} else {
				return "\$self->$context";
			}
		} elsif (($expression->{type} eq 'call_function')) {
			my $function = $self->get_function_by_name($expression->{function});
			if (exists($expression->{argument})) {
				my $expression_code = $self->compile_syntax_spawn_expression($expression->{argument});
				return "\$self->$function($expression_code)";
			} else {
				return "\$self->$function";
			}
		} elsif (($expression->{type} eq 'call_variable')) {
			my $variable = $self->get_variable($expression->{variable});
			my $expression_code = $self->compile_syntax_spawn_expression($expression->{argument});
			return "$variable\->($expression_code)";
		} elsif (($expression->{type} eq 'variable_value')) {
			my $variable = $self->get_variable($expression->{variable});
			return "$variable";
		} elsif (($expression->{type} eq 'call_substitution')) {
			my $expression_code = $self->compile_syntax_spawn_expression($expression->{argument});
			return "$expression_code =~ $expression->{regex}r";
		} elsif (($expression->{type} eq 'string')) {
			return "$expression->{string}";
		} elsif (($expression->{type} eq 'bareword_string')) {
			return "'$expression->{value}'";
		} elsif (($expression->{type} eq 'bareword')) {
			return "$expression->{value}";
		} elsif (($expression->{type} eq 'empty_list')) {
			return '[]';
		} elsif (($expression->{type} eq 'empty_hash')) {
			return '{}';
		} elsif (($expression->{type} eq 'list_constructor')) {
			my $code = "[ ";
			foreach my $field (@{$expression->{arguments}}) {
				my $field_expression_code = $self->compile_syntax_spawn_expression($field);
				$code .= "$field_expression_code, ";
			}
			$code .= "]";
			return $code;
		} elsif (($expression->{type} eq 'hash_constructor')) {
			my $code = "{ ";
			my $arguments = $expression->{arguments};
			my $items = [ @{$arguments} ];
			while ((0 < scalar(@{$items}))) {
				my $field = shift(@{$items});
				my $value = shift(@{$items});
				my $field_expression_code = $self->compile_syntax_spawn_expression($field);
				my $value_expression_code = $self->compile_syntax_spawn_expression($value);
				$code .= "$field_expression_code => $value_expression_code, ";
			}
			$code .= "}";
			return $code;
		} else {
			$self->confess_at_current_line("invalid spawn expression: '$expression->{type}'");
		}
	}
	
	sub get_standalone_functionality {
		my ($self) = @_;
		return '

sub new {
	my ($class, %opts) = @_;
	my $self = bless {}, $class;

	$self->{filepath} = Sugar::IO::File->new($opts{filepath}) if defined $opts{filepath};
	$self->{text} = $opts{text} if defined $opts{text};

	$self->{token_regexes} = $tokens // die "token_regexes argument required for Sugar::Lang::Tokenizer";
	$self->{ignored_tokens} = $ignored_tokens;

	$self->compile_tokenizer_regex;

	return $self
}

sub parse {
	my ($self) = @_;
	return $self->parse_from_context("context_root");
}

sub parse_from_context {
	my ($self, $context) = @_;
	$self->parse_tokens;

	$self->{syntax_tree} = $self->$context($self->{syntax_tree});
	$self->confess_at_current_offset("more tokens after parsing complete") if $self->{tokens_index} < @{$self->{tokens}};

	return $self->{syntax_tree};
}

sub compile_tokenizer_regex {
	my ($self) = @_;
	use re \'eval\';
	my $token_pieces = join \'|\',
			map "($self->{token_regexes}[$_*2+1])(?{\'$self->{token_regexes}[$_*2]\'})",
				0 .. $#{$self->{token_regexes}} / 2;
	$self->{tokenizer_regex} = qr/$token_pieces/s;

# 	# optimized selector for token names, because %+ is slow
# 	my @index_names = map $self->{token_regexes}[$_*2], 0 .. $#{$self->{token_regexes}} / 2;
# 	my @index_variables = map "\$$_", 1 .. @index_names;
# 	my $index_selectors = join "\n\tels",
# 			map "if (defined $index_variables[$_]) { return \'$index_names[$_]\', $index_variables[$_]; }",
# 			0 .. $#index_names;

# 	$self->{token_selector_callback} = eval "
# sub {
# 	$index_selectors
# }
# ";
}

sub parse_tokens {
	my ($self) = @_;

	my $text;
	$text = $self->{filepath}->read if defined $self->{filepath};
	$text = $self->{text} unless defined $text;

	die "no text or filepath specified before parsing" unless defined $text;

	return $self->parse_tokens_in_text($text)
}


sub parse_tokens_in_text {
	my ($self, $text) = @_;
	$self->{text} = $text;
	
	my @tokens;

	my $line_number = 1;
	my $offset = 0;

	# study $text;
	while ($text =~ /\G$self->{tokenizer_regex}/gc) {
		# despite the absurdity of this solution, this is still faster than loading %+
		# my ($token_type, $token_text) = each %+;
		# my ($token_type, $token_text) = $self->{token_selector_callback}->();
		my ($token_type, $token_text) = ($^R, $^N);

		push @tokens, [ $token_type => $token_text, $line_number, $offset ];
		$offset = pos $text;
		# amazingly, this is faster than a regex or an index count
		# must be because perl optimizes out the string modification, and just performs a count
		$line_number += $token_text =~ y/\n//;
	}

	die "parsing error on line $line_number:\nHERE ---->" . substr ($text, pos $text // 0, 200) . "\n\n\n"
			if not defined pos $text or pos $text != length $text;

	if (defined $self->{ignored_tokens}) {
		foreach my $ignored_token (@{$self->{ignored_tokens}}) {
			@tokens = grep $_->[0] ne $ignored_token, @tokens;
		}
	}

	# @tokens = $self->filter_tokens(@tokens);

	$self->{tokens} = \@tokens;
	$self->{tokens_index} = 0;
	$self->{save_tokens_index} = 0;

	return $self->{tokens}
}

sub confess_at_current_offset {
	my ($self, $msg) = @_;

	my $position;
	my $next_token = \'\';
	if ($self->{tokens_index} < @{$self->{tokens}}) {
		$position = \'line \' . $self->{tokens}[$self->{tokens_index}][2];
		my ($type, $val) = @{$self->{tokens}[$self->{tokens_index}]};
		$next_token = " (next token is $type => <$val>)";
	} else {
		$position = \'end of file\';
	}

	# say $self->dump_at_current_offset;

	die "error on $position: $msg$next_token";
}
sub confess_at_offset {
	my ($self, $msg, $offset) = @_;

	my $position;
	my $next_token = \'\';
	if ($offset < @{$self->{tokens}}) {
		$position = \'line \' . $self->{tokens}[$offset][2];
		my ($type, $val) = ($self->{tokens}[$offset][0], $self->{tokens}[$offset][1]);
		$next_token = " (next token is $type => <$val>)";
	} else {
		$position = \'end of file\';
	}

	# say $self->dump_at_current_offset;

	die "error on $position: $msg$next_token";
}

';
	}
	
	sub main {
		my ($self) = @_;
	
	my ($files_list) = @_;

	# require Data::Dumper;
	require Sugar::IO::File;
	use Sugar::Lang::SugarGrammarParser;
	# use Sugar::Lang::SugarGrammarCompiler;

	my %compile_args;
	foreach my $file (@$files_list) {
		if ($file eq '--standalone') {
			$compile_args{compile_standalone} = 1;
			next;
		}

		my $parser = Sugar::Lang::SugarGrammarParser->new;
		$parser->{filepath} = Sugar::IO::File->new($file);
		my $tree = $parser->parse;
		# say Dumper $tree;

		my $compiler = Sugar::Lang::SugarGrammarCompiler->new({syntax_definition_intermediate => $tree, %compile_args});
		$compiler->compile_syntax_intermediate;
		say $compiler->to_package;
	}

	}
	
	caller or main(\@ARGV);
	

1;

