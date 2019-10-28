use v6;

class Web::Scraper::Rule {
  has $.selector is required;
  has $.value = "text";
  has $.multiple = False;

  multi method extract (@nodes where { !.elems }) {
    $!multiple ?? [] !! Nil;
  }

  multi method extract (@nodes) {
    $!multiple
      ?? [@nodes.map: {$.extract($_)}]
      !! $.extract(@nodes[0]);
  }

  multi method extract ($node) {
    given $!value {
      when *.isa("Web::Scraper") {
        $!value.extract($node);
      }
      when "text" {
        $node.textContent;
      }
      when "html" {
        $node.toString;
      }
      when /^ '@' / {
        $node.findvalue($!value);
      }
    }
  }
}
