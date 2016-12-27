#!/usr/bin/env perl
package Sugar::Lang::Grammar;
use parent 'Sugar::Lang::SyntaxTreeBuilder';
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use Sugar::IO::File;
use Sugar::Lang::SyntaxIntermediateCompiler;



our @keywords = qw/
	context
	root

	default

	assign
	spawn
	respawn
	enter_context
	switch_context
	nest_context
	exit_context

	undef
/;
our $keyword_chain = join '|', map quotemeta, @keywords;
our $keywords_regex = qr/\b($keyword_chain)\b/;

our @symbols = (qw/
	{ } [ ] => =
/, ',');
our $symbol_chain = join '|', map quotemeta, @symbols;
our $symbols_regex = qr/$symbol_chain/;

our $string_regex = qr/'([^\\']|\\[\\'])*+'/s;
our $regex_regex = qr#/([^\\/]|\\.)*+/[msixpodualn]*#s;
our $variable_regex = qr/\$\w++/;
our $context_reference_regex = qr/\!\w++/;
our $identifier_regex = qr/[a-zA-Z_][a-zA-Z0-9_]*+/;

our $comment_regex = qr/\#[^\n]*+\n/s;
our $whitespace_regex = qr/\s++/s;

sub new {
	my ($class, %args) = @_;

	$args{token_regexes} = [
		keyword => $keywords_regex,
		symbol => $symbols_regex,

		string => $string_regex,
		variable => $variable_regex,
		context_reference => $context_reference_regex,
		identifier => $identifier_regex,
		regex => $regex_regex,

		comment => $comment_regex,
		whitespace => $whitespace_regex,
	];
	$args{ignored_tokens} = [qw/ comment whitespace /];

	$args{syntax_definition_intermediate} = {
		variables => {
			regex_regex => "/\\/([^\\\\\\/]|\\\\.)*+\\/[msixpodualn]*/",
		},
		contexts => {
			root => [
				[ "/$identifier_regex/", "'='" ] => [
					assign => [
						"'variables'" => {} => '$0' => '!def_value',
					],
				],
				[ "'context'", "/$identifier_regex/", "'{'" ] => [
					assign => [
						"'contexts'" => {} => '$1' => [ '!context_definition' ],
					]
				],
				undef
					=> [ die => "'expected definition statement'" ],
			],
			def_value => [
				"/$string_regex/" => [
					spawn => '$0',
					'exit_context'
				],
				"\$regex_regex" => [
					spawn => '$0',
					'exit_context',
				],
				undef
					=> [ die => "'expected value'" ],
			],
			context_definition => [
				"'}'" => [
					'exit_context',
				],
				"'default'" => [
					spawn => undef,
					spawn => [ '!enter_match_action' ],
				],
				undef
					=> [
						spawn => [ '!match_list' ],
						spawn => [ '!enter_match_action' ],
					]
			],

			match_list => [
				[ "/$variable_regex/", "','" ] => [
					spawn => '$0',
				],
				"/$variable_regex/" => [
					spawn => '$0',
					'exit_context',
				],
				[ "\$regex_regex", "','" ] => [
					spawn => '$0',
				],
				"\$regex_regex" => [
					spawn => '$0',
					'exit_context',
				],
				[ "/$string_regex/", "','" ] => [
					spawn => '$0',
				],
				"/$string_regex/" => [
					spawn => '$0',
					'exit_context',
				],
				undef
					=> [
						die => "'unexpected end of match list'",
					],
			],
			# match_list_more => [
			# 	',' => [
			# 		switch_context => '!match_list',
			# 	],
			# 	undef
			# 		=> [ 'exit_context' ]
			# ],

			enter_match_action => [
				"'{'" => [
					switch_context => '!match_action',
				],
				undef
					=> [ die => "'expected \\'{\\' after match directive'" ],
			],
			match_action => [
				[ "'assign'", "'{'" ] => [
					spawn => "'assign'",
					spawn => [ '!assign_scope' ],
				],
				"'spawn'" => [
					spawn => "'spawn'",
					nest_context => '!spawn_expression',
				],
				[ "'enter_context'", "/$context_reference_regex/" ] => [
					spawn => "'enter_context'",
					spawn => '$1',
				],
				[ "'switch_context'", "/$context_reference_regex/" ] => [
					spawn => "'switch_context'",
					spawn => '$1',
				],
				[ "'nest_context'", "/$context_reference_regex/" ] => [
					spawn => "'nest_context'",
					spawn => '$1',
				],
				"'exit_context'" => [
					spawn => "'exit_context'",
				],
				[ "'warn'", "/$string_regex/" ] => [
					spawn => "'warn'",
					spawn => '$1',
				],
				[ "'die'", "/$string_regex/" ] => [
					spawn => "'die'",
					spawn => '$1',
				],
				"'}'" => [
					'exit_context',
				],
				undef
					=> [ die => "'expected \\'}\\' to close match actions list'" ],
			],
			spawn_expression => [
				'/\\$\\d++/' => [
					spawn => '$0',
					'exit_context',
				],
				'/!\\w++/' => [
					spawn => '$0',
					'exit_context',
				],
				"'undef'" => [
					spawn => undef,
					'exit_context',
				],
				"/$string_regex/" => [
					spawn => '$0',
					'exit_context',
				],
				[ "'['", "']'" ] => [
					spawn => [],
					'exit_context',
				],
				[ "'{'", "'}'" ] => [
					spawn => {},
					'exit_context',
				],
				[ "'['", ] => [
					spawn => [ '!spawn_expression_list' ],
					'exit_context',
				],
				# '$previous' => [
				# 	spawn => '$0',
				# ],
				undef
					=> [ die => "'expression expected'" ],
			],
			spawn_expression_list => [
				[ '/!\\w++/', "']'" ] => [
					spawn => '$0',
					'exit_context',
				],
				undef
					=> [ die => "'spawn expression list expected'" ],
			],
			assign_scope => [
				[ "/$string_regex/", "'=>'" ] => [
					spawn => '$0',
					nest_context => '!spawn_expression',
				],
				[ "/$string_regex/", "'['", "']'", "'=>'" ] => [
					spawn => '$0',
					spawn => [],
					nest_context => '!spawn_expression',
				],
				[ "/$string_regex/", "'{'" ] => [
					spawn => '$0',
					spawn => {},
					spawn => '!spawn_expression',
					nest_context => '!assign_hash',
				],
				"'}'" => [
					'exit_context'
				],
				undef
					=> [ die => "'assign expression expected'" ],
			],

			assign_hash => [
				[ "'}'", "'=>'" ] => [
					switch_context => '!spawn_expression',
				],
				undef
					=> [ die => "'\\'}\\' expected to close hash assignment'" ],
			],
		},
	};
	$args{syntax_definition_intermediate} = {
          'variables' => {
                           'regex_regex' => '/\\/([^\\\\\\/]|\\\\.)*+\\/[msixpodualn]*/s',
                           'identifier_regex' => '/[a-zA-Z_][a-zA-Z0-9_]*+/',
                           'context_reference_regex' => '/!\\w++/',
                           'string_regex' => '/\'([^\\\\\']|\\\\[\\\\\'])*+\'/s',
                           'variable_regex' => '/\\$\\w++/'
                         },
          'contexts' => {
                          'spawn_expression_list' => [
                                                       [
                                                         '$context_reference_regex',
                                                         '\']\''
                                                       ],
                                                       [
                                                         'spawn',
                                                         '$0',
                                                         'exit_context'
                                                       ],
                                                       undef,
                                                       [
                                                         'die',
                                                         '\'spawn expression list expected\''
                                                       ]
                                                     ],
                          'context_definition' => [
                                                    [
                                                      '\'}\''
                                                    ],
                                                    [
                                                      'exit_context'
                                                    ],
                                                    [
                                                      '\'default\''
                                                    ],
                                                    [
                                                      'spawn',
                                                      undef,
                                                      'spawn',
                                                      [
                                                        '!enter_match_action'
                                                      ]
                                                    ],
                                                    undef,
                                                    [
                                                      'spawn',
                                                      [
                                                        '!match_list'
                                                      ],
                                                      'spawn',
                                                      [
                                                        '!enter_match_action'
                                                      ]
                                                    ]
                                                  ],
                          'enter_match_action' => [
                                                    [
                                                      '\'{\''
                                                    ],
                                                    [
                                                      'switch_context',
                                                      '!match_action'
                                                    ],
                                                    undef,
                                                    [
                                                      'die',
                                                      '\'expected \\\'{\\\' after match directive\''
                                                    ]
                                                  ],
                          'assign_scope' => [
                                              [
                                                '$string_regex',
                                                '\'=>\''
                                              ],
                                              [
                                                'spawn',
                                                '$0',
                                                'nest_context',
                                                '!spawn_expression'
                                              ],
                                              [
                                                '$string_regex',
                                                '\'[\'',
                                                '\']\'',
                                                '\'=>\''
                                              ],
                                              [
                                                'spawn',
                                                '$0',
                                                'spawn',
                                                [],
                                                'nest_context',
                                                '!spawn_expression'
                                              ],
                                              [
                                                '$string_regex',
                                                '\'{\''
                                              ],
                                              [
                                                'spawn',
                                                '$0',
                                                'spawn',
                                                {},
                                                'spawn',
                                                '!spawn_expression',
                                                'nest_context',
                                                '!assign_hash'
                                              ],
                                              [
                                                '\'}\''
                                              ],
                                              [
                                                'exit_context'
                                              ],
                                              undef,
                                              [
                                                'die',
                                                '\'assign expression expected\''
                                              ]
                                            ],
                          'ignored_tokens_list' => [
                                                     [
                                                       '\'}\''
                                                     ],
                                                     [
                                                       'exit_context'
                                                     ],
                                                     [
                                                       '$identifier_regex'
                                                     ],
                                                     [
                                                       'spawn',
                                                       '$0'
                                                     ],
                                                     undef,
                                                     [
                                                       'die',
                                                       '\'unexpected token in ignored_tokens_list\''
                                                     ]
                                                   ],
                          'token_definition' => [
                                                  [
                                                    '\'}\''
                                                  ],
                                                  [
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '$identifier_regex',
                                                    '\'=>\''
                                                  ],
                                                  [
                                                    'spawn',
                                                    '$0',
                                                    'spawn',
                                                    '!def_value'
                                                  ],
                                                  undef,
                                                  [
                                                    'die',
                                                    '\'unexpected token in token_definition\''
                                                  ]
                                                ],
                          'def_value' => [
                                           [
                                             '$string_regex'
                                           ],
                                           [
                                             'spawn',
                                             '$0',
                                             'exit_context'
                                           ],
                                           [
                                             '$regex_regex'
                                           ],
                                           [
                                             'spawn',
                                             '$0',
                                             'exit_context'
                                           ],
                                           [
                                             '$variable_regex'
                                           ],
                                           [
                                             'spawn',
                                             '$0',
                                             'exit_context'
                                           ],
                                           undef,
                                           [
                                             'die',
                                             '\'unexpected token in def_value\''
                                           ]
                                         ],
                          'spawn_expression' => [
                                                  [
                                                    '/\\$\\d++/'
                                                  ],
                                                  [
                                                    'spawn',
                                                    '$0',
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '$context_reference_regex'
                                                  ],
                                                  [
                                                    'spawn',
                                                    '$0',
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '$string_regex'
                                                  ],
                                                  [
                                                    'spawn',
                                                    '$0',
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '\'undef\''
                                                  ],
                                                  [
                                                    'spawn',
                                                    undef,
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '\'[\'',
                                                    '\']\''
                                                  ],
                                                  [
                                                    'spawn',
                                                    [],
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '\'{\'',
                                                    '\'}\''
                                                  ],
                                                  [
                                                    'spawn',
                                                    {},
                                                    'exit_context'
                                                  ],
                                                  [
                                                    '\'[\''
                                                  ],
                                                  [
                                                    'spawn',
                                                    [
                                                      '!spawn_expression_list'
                                                    ],
                                                    'exit_context'
                                                  ],
                                                  undef,
                                                  [
                                                    'die',
                                                    '\'spawn expression expected\''
                                                  ]
                                                ],
                          'match_list' => [
                                            [
                                              '$variable_regex',
                                              '\',\''
                                            ],
                                            [
                                              'spawn',
                                              '$0'
                                            ],
                                            [
                                              '$variable_regex'
                                            ],
                                            [
                                              'spawn',
                                              '$0',
                                              'exit_context'
                                            ],
                                            [
                                              '$regex_regex',
                                              '\',\''
                                            ],
                                            [
                                              'spawn',
                                              '$0'
                                            ],
                                            [
                                              '$regex_regex'
                                            ],
                                            [
                                              'spawn',
                                              '$0',
                                              'exit_context'
                                            ],
                                            [
                                              '$string_regex',
                                              '\',\''
                                            ],
                                            [
                                              'spawn',
                                              '$0'
                                            ],
                                            [
                                              '$string_regex'
                                            ],
                                            [
                                              'spawn',
                                              '$0',
                                              'exit_context'
                                            ],
                                            undef,
                                            [
                                              'die',
                                              '\'unexpected end of match list\''
                                            ]
                                          ],
                          'root' => [
                                      [
                                        '$identifier_regex',
                                        '\'=\''
                                      ],
                                      [
                                        'assign',
                                        [
                                          '\'variables\'',
                                          {},
                                          '$0',
                                          '!def_value'
                                        ]
                                      ],
                                      [
                                        '\'tokens\'',
                                        '\'{\''
                                      ],
                                      [
                                        'assign',
                                        [
                                          '\'tokens\'',
                                          [
                                            '!token_definition'
                                          ]
                                        ]
                                      ],
                                      [
                                        '\'ignored_tokens\'',
                                        '\'{\''
                                      ],
                                      [
                                        'assign',
                                        [
                                          '\'ignored_tokens\'',
                                          [
                                            '!ignored_tokens_list'
                                          ]
                                        ]
                                      ],
                                      [
                                        '\'context\'',
                                        '$identifier_regex',
                                        '\'{\''
                                      ],
                                      [
                                        'assign',
                                        [
                                          '\'contexts\'',
                                          {},
                                          '$1',
                                          [
                                            '!context_definition'
                                          ]
                                        ]
                                      ]
                                    ],
                          'assign_hash' => [
                                             [
                                               '\'}\'',
                                               '\'=>\''
                                             ],
                                             [
                                               'switch_context',
                                               '!spawn_expression'
                                             ],
                                             undef,
                                             [
                                               'die',
                                               '\'\\\'}\\\' expected to close hash assignment\''
                                             ]
                                           ],
                          'match_action' => [
                                              [
                                                '\'assign\'',
                                                '\'{\''
                                              ],
                                              [
                                                'spawn',
                                                '\'assign\'',
                                                'spawn',
                                                [
                                                  '!assign_scope'
                                                ]
                                              ],
                                              [
                                                '\'spawn\''
                                              ],
                                              [
                                                'spawn',
                                                '\'spawn\'',
                                                'nest_context',
                                                '!spawn_expression'
                                              ],
                                              [
                                                '\'enter_context\'',
                                                '$context_reference_regex'
                                              ],
                                              [
                                                'spawn',
                                                '\'enter_context\'',
                                                'spawn',
                                                '$1'
                                              ],
                                              [
                                                '\'switch_context\'',
                                                '$context_reference_regex'
                                              ],
                                              [
                                                'spawn',
                                                '\'switch_context\'',
                                                'spawn',
                                                '$1'
                                              ],
                                              [
                                                '\'nest_context\'',
                                                '$context_reference_regex'
                                              ],
                                              [
                                                'spawn',
                                                '\'nest_context\'',
                                                'spawn',
                                                '$1'
                                              ],
                                              [
                                                '\'exit_context\''
                                              ],
                                              [
                                                'spawn',
                                                '\'exit_context\''
                                              ],
                                              [
                                                '\'warn\'',
                                                '$string_regex'
                                              ],
                                              [
                                                'spawn',
                                                '\'warn\'',
                                                'spawn',
                                                '$1'
                                              ],
                                              [
                                                '\'die\'',
                                                '$string_regex'
                                              ],
                                              [
                                                'spawn',
                                                '\'die\'',
                                                'spawn',
                                                '$1'
                                              ],
                                              [
                                                '\'}\''
                                              ],
                                              [
                                                'exit_context'
                                              ],
                                              undef,
                                              [
                                                'die',
                                                '\'expected \\\'}\\\' to close match actions list\''
                                              ]
                                            ]
                        },
          'tokens' => [
                        'identifier',
                        '$identifier_regex',
                        'string',
                        '$string_regex',
                        'regex',
                        '$regex_regex',
                        'variable',
                        '$variable_regex',
                        'context_reference',
                        '$context_reference_regex'
                      ],
          'context_type' => 'root'
        };

	my $self = $class->SUPER::new(%args);

	return $self
}

sub main {
	my $parser = Sugar::Lang::Grammar->new;
	foreach my $file (@_) {
		$parser->{filepath} = Sugar::IO::File->new($file);
		my $tree = $parser->parse;
		# say Dumper $tree;

		my $compiler = Sugar::Lang::SyntaxIntermediateCompiler->new(syntax_definition_intermediate => $tree);
		say $compiler->to_package;
	}
}

caller or main(@ARGV);
