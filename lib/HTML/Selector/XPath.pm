use v6;

my $IDENT   = rx{ <!after [<[0..9]>|\-<[- 0..9]>]><[ - _ a..z A..Z 0..9 ]>+ };
my $ELEMENT = rx{ ^(<[#\.]>?) (<-[\s\'\"#\./:@,=~>()\[\]|]>*)((\|)(<[a..zA..Z0..9\\*_-]>*))?};
my $ATTR1   = rx{^\[ \s* (<$IDENT>) \s* \]};
my $BADATTR = rx{^\[};
my $ATTRN   = rx{ ^\:not\( };
my $PSEUDO  = rx{ ^\:(<[ ( ) a..z A..Z 0..9 _ + - ]>+) };
my $COMBINATOR = rx{ ^ ( \s* <[>+~\s]> <!before \,> ) };
my $COMMA = rx{ ^ \s* \, \s* };
my $ATTR2 = rx{
    ^\[ \s* ($IDENT) \s*
    ( <[ ~ | * ^ $ ! ]>? \= ) \s*
    [ (<$IDENT>) | \" (<-["]>*) \" | \'(<-[']>*)\' ] \s* \]
};

class HTML::Selector::XPath::Rule {
  has $.selector = '';
  has $.match;

  method chars { $!selector.chars }
  method trim  { $!selector.=trim }

  method test($pattern) {
    $!selector ~~ /<$pattern>/;
  }

  method nibble($pattern) {
    $!selector.=subst: $pattern, '';
    $!match = $/;
  }
}

class HTML::Selector::XPath {
  has Str $.selector;

  sub convert-attribute-match($match) {
    my ($left, $op, $right) = ($match[0], $match[1], $match.tail);

    # negation (e.g. [input!="text"]) isn't implemented in CSS, but include it anyway:
    given $op {
      when '!=' { "@$left!='$right'" }
      when '~=' { "contains(concat(' ', @$left, ' '), ' $right ')" }
      when '*=' { "contains(@$left, '$right')" }
      when '|=' { "@$left='$right' or starts-with(@$left, '$right-')" }
      when '^=' { "starts-with(@$left,'$right')" }
      when '$=' {
        my $n = $right.chars - 1;
        "substring(@$left,string-length(@$left)-$n)='$right'";
      }
      default { "\@$left='$right'" }
    }
  }

  sub generate-child($direction, $a, $b) {
    if ($a == 0) { # 0n+b
      $b--;
      "[count({$direction}-sibling::*) = $b and parent::*]"
    } elsif ($a > 0) { # an + b
      return "[not((count({$direction}-sibling::*)+1)<$b) and ((count({$direction}-sibling::*) + 1) - $b) mod $a = 0 and parent::*]"
    } else { # -an + $b
      $a = -$a;
      return "[not((count({$direction}-sibling::*)+1)>$b) and (($b - (count({$direction}-sibling::*) + 1)) mod $a) = 0 and parent::*]"
    }
  }

  sub nth-child($a, $b?) {
    if (!$b) {
      ($a,$b) = (0,$a);
    }
    generate-child('preceding', $a, $b);
  }

  sub nth-last-child($a, $b?) {
    if (!$b) {
      ($a,$b) = (0,$a);
    }
    generate-child('following', $a, $b);
  }

  # A hacky recursive descent
  # Only descends for :not(...)
  method consume($rule, %parms) {
    my $root = %parms<root> || '/';

    return [$rule,''] if $rule.test(rx!^\/!); # If we start with a slash, we're already an XPath?!

    my @parts = ("$root/");
    my $last-rule = '';
    my $wrote-tag;
    my $root-index = 0; # points to the current root

    # Loop through each "unit" of the rule
    while $rule.chars && $rule.selector ne $last-rule {
      $last-rule = $rule.selector;

      $rule.trim;
      last unless $rule.chars;

      # Prepend explicit first selector if we have an implicit selector
      # (that is, if we start with a combinator)
      if $rule.test($COMBINATOR) {
        $rule.selector = "* {$rule.selector}";
      }

      # Match elements
      if ($rule.nibble($ELEMENT)) {
        my ($id-class,$name,$lang) = ($rule.match[0],$rule.match[1],$rule.match[2]);

        my $tag = $id-class.Str eq '' ?? $name || '*' !! '*';

        if %parms<prefix> and not $tag ~~ /<[*:|]>/ {
          $tag = %parms<prefix> ~ ':' ~ $tag;
        }

        if ! $wrote-tag++ {
          @parts.push: $tag;
        }

        # XXX Shouldn't the RE allow both, ID and class?
        given $id-class {
          when '#' { # ID
            @parts.push: "[@id='$name']";
          }
          when '.' { # class
            @parts.push: "[contains(concat(' ', normalize-space(\@class), ' '), ' $name ')]";
          }
        }
      }

      # Match attribute selectors

      if $rule.nibble($ATTR2) {
        @parts.push: "[", convert-attribute-match( $rule.match ), "]";
      } elsif $rule.nibble($ATTR1) {
        # If we have no tag output yet, write the tag:
        if ! $wrote-tag++ {
          @parts.push: '*';
        }
        @parts.push: "[\@{$rule.match[0]}]";
      } elsif $rule.test($BADATTR) {
        die "Invalid attribute-value selector '$rule'";
      }

      # Match negation
      if $rule.nibble($ATTRN) {
        # Now we parse the rest, and after parsing the subexpression
        # has stopped, we must find a matching closing parenthesis:
        if $rule.nibble($ATTR2) {
          @parts.push: "[not(", convert-attribute-match( $rule.match), ")]";
        } elsif $rule.nibble($ATTR1) {
          @parts.push: "[not(\@{$rule.match[0]})]";
        } elsif $rule.test($BADATTR) {
          die "Invalid negated attribute-value selector ':not({$rule.selector})'";
        } else {
          my ( @new-parts, $leftover ) = $.consume( $rule, %parms );
          @new-parts.shift; # remove '//'
          my $xpath = @new-parts.join: '';

          @parts.push: "[not(self::$xpath)]";
          $rule.selector = $leftover;
        }
        $rule.nibble(/^\s*\)/)
          or die "Unbalanced parentheses at '$rule'";
      }

      # Ignore pseudoclasses/pseudoelements
      while $rule.nibble($PSEUDO) {
        given $rule.match[0] {
          when 'disabled'    { @parts.push: '[@disabled]' }
          when 'checked'     { @parts.push: '[@checked]' }
          when 'selected'    { @parts.push: '[@selected]' }
          when 'text'        { @parts.push: '*[@type="text"]' }
          when 'first-child' { @parts.push: nth-child(1) }
          when 'last-child'  { @parts.push: nth-last-child(1) }
          when 'only-child'  { @parts.push: nth-child(1), nth-last-child(1) }

          when /^lang\((<[\w\-]>+)\)$/ {
            @parts.push: "[\@xml:lang='$_' or starts-with(\@xml:lang, '$_-')]";
          }

          when 'nth-child(odd)'        { @parts.push: nth-child(2, 1) }
          when 'nth-child(even)'       { @parts.push: nth-child(2, 0) }
          when /^nth\-child\((\d+)\)$/ { @parts.push: nth-child($_) }

          when /^nth\-child\((\d+)n<[\+(\d+)]>?\)$/ {
            @parts.push: nth-child($_, $rule.match[1]||0);
          }
          when /^nth\-last\-child\((\d+)\)$/ {
            @parts.push: nth-last-child($_);
          }
          when /^nth\-last\-child\((\d+)n<[\+(\d+)]>?\)$/ {
            @parts.push: nth-last-child($_, $rule.match[1]||0);
          }

          when 'first-of-type'            { @parts.push: "[1]" }
          when /^nth\-of\-type\((\d+)\)$/ { @parts.push: "[$_]" }
          when 'last-of-type'             { @parts.push: "[last()]" }

          when 'contains(' {
            if $rule.nibble(/^\s*\"(<-["]>*)\"\s*\)/) {
              @parts.push: qq{[text()[contains(string(.),"{$rule.match[0]}")]]};
            } elsif $rule.nibble(/^\s*\'(<-[']>*)\'\s*\)/ ) {
              @parts.push: qq{[text()[contains(string(.),"{$rule.match[0]}")]]};
            } else {
              return @parts, $rule;
              #die "Malformed string in :contains(): '$rule'";
            };
          }

          # This will give surprising results if you do E > F:root
          when 'root'  { @parts[$root-index] = $root }
          when 'empty' { @parts.push: "[not(* or text())]" }
          default      { die "Can't translate '$_' pseudo-class" }
        }
      }

      # Match combinators (whitespace, >, + and ~)
      if $rule.nibble($COMBINATOR) {
        given $rule.match[0] {
          when /\>/    { @parts.push: "/" }
          when /\+/    { @parts.push: "/following-sibling::*[1]/self::" }
          when /\~/    { @parts.push: "/following-sibling::" }
          when /^\s*$/ { @parts.push: "//" }
          default      { die "Weird combinator '$_'" }
        }

        # new context
        $wrote-tag = 0;
      }

      # Match commas
      if $rule.nibble($COMMA) {
        @parts.push: " | ", "$root/"; # ending one rule and beginning another
        $root-index = @parts.elems;
        $wrote-tag = 0;
      }
    }
    return @parts, $rule.selector;
  }

  method to-xpath(*%parms) {
    my $rule = HTML::Selector::XPath::Rule.new(:$!selector);

    my ($result,$leftover) = $.consume( $rule, %parms );
    $leftover
      and die "Invalid rule, couldn't parse '$leftover'";
    return join '', @$result;
  }
}
